import UIKit
import SwiftUI
import CoreText
import CryptoKit

/// Research candidate: QCF V2 page fonts and authored V2 row alignment.
/// Word IDs always come from Content Sync; QUL's token IDs are never imported.
struct OriginalMushafRows: Decodable {
    struct Row: Decodable { let page: Int; let line: Int; let type: String; let centered: Bool; let chapter: Int? }
    let rows: [Row]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "qpc-v2-line-layout", withExtension: "json") else { throw QCFV2Snapshot.Invalid.page }
        let bytes = try Data(contentsOf: url)
        guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == "51b0ecce36ea708b974756348f25ec0031ed002871249a884c3386eeed5ca828" else { throw QCFV2Snapshot.Invalid.page }
        let result = try JSONDecoder().decode(Self.self, from: bytes)
        guard result.rows.count == 9046, result.rows.filter({ $0.type == "basmallah" }).count == 112,
              Set(result.rows.map(\.page)) == Set(1...604),
              Set(result.rows.map { "\($0.page):\($0.line)" }).count == result.rows.count,
              result.rows.filter({ $0.type == "surah_name" }).compactMap(\.chapter) == Array(1...114),
              result.rows.allSatisfy({ (1...($0.page <= 2 ? 8 : 15)).contains($0.line) && ["ayah", "surah_name", "basmallah"].contains($0.type) }) else { throw QCFV2Snapshot.Invalid.page }
        return result
    }
    func validate(_ snapshot: QCFV2Snapshot) throws {
        let body = Set(snapshot.records.filter { $0.record_type == "mushaf_word" }.map { "\($0.page_number!):\($0.line_number! - ($0.page_number! <= 2 ? 7 : 0))" })
        guard body == Set(rows.filter { $0.type == "ayah" }.map { "\($0.page):\($0.line)" }) else { throw QCFV2Snapshot.Invalid.page }
    }
}

@MainActor enum OriginalMushafCompanion {
    static let name = "QCF2BSML"
    static func register() throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: url)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == "457cd1bf2174e9c10b31eab25bc5eda20c12abbafe5f47bdea473c64036f411e",
              let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
              let verifiedName = font.postScriptName, verifiedName as String == name else { throw CocoaError(.fileReadCorruptFile) }
        CTFontManagerRegisterGraphicsFont(font, nil)
        guard UIFont(name: name, size: 32) != nil else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func title(_ chapter: Int) -> String {
        let value = chapter <= 37 ? 0xFB8C + chapter : 0xFBD3 + chapter - 38
        return "\u{FB8C} " + String(UnicodeScalar(value)!)
    }
    // Authored calligraphic glyphs, independent of the Unicode copying corpus.
    static let basmala = "\u{FB5A} \u{FB5B} \u{FB5C} \u{FB5D}"
}

struct OriginalPageWord {
    let id: Int; let verse: String; let code: String; let line: Int; let order: Int
}
struct OriginalPageData {
    let number: Int; let words: [OriginalPageWord]; let rows: [OriginalMushafRows.Row]
    static func page(_ number: Int, snapshot: QCFV2Snapshot, rows: OriginalMushafRows, keys: [String]) -> Self {
        let words = snapshot.records.filter { $0.record_type == "mushaf_word" && $0.page_number == number }.sorted { $0.position_in_page! < $1.position_in_page! }.map {
            OriginalPageWord(id: $0.id, verse: keys[$0.verse_id! - 1], code: $0.text!, line: $0.line_number! - (number <= 2 ? 7 : 0), order: $0.position_in_page!)
        }
        return Self(number: number, words: words, rows: rows.rows.filter { $0.page == number })
    }
}

/// One immutable coordinate space. Lines are shaped whole, without justification,
/// artificial kashida, per-line fitting, or font substitution.
@MainActor final class OriginalMushafCanvas: UIView {
    static let pageSize = CGSize(width: 560, height: 940)
    /// The edition has one reference grid; the viewport scales the entire page.
    /// Companion glyphs use a different em from page fonts. Their point sizes
    /// cannot express the intended visual proportion without measuring the ink.
    private enum Metrics {
        static let bodyPointSize: CGFloat = 32
        static let horizontalMargin: CGFloat = 15
        static let verticalMargin: CGFloat = 7
        static let baselineInterval: CGFloat = 61
        static let baselineOffset: CGFloat = 48
        static let openingTop: CGFloat = 214
        static let headingGap = baselineInterval / 20
        static let titleHeightFraction: CGFloat = 0.64
        static let titleWidthFraction: CGFloat = 0.46
    }
    struct Hit { let word: Int; let verse: String; let rect: CGRect; let paths: [CGPath] }
    private(set) var regions: [Hit] = []
    private(set) var renderedSuccessfully = false
    private(set) var failureReason: String?
    private var lines: [(CTLine, CGPoint)] = []
    private var shapedTexts: [NSAttributedString] = []
    private var lineWordRanges: [[(NSRange, Int)]] = []
    var hiddenWordIDs: Set<Int> = [] {
        didSet {
            guard oldValue != hiddenWordIDs else { return }
            refreshAccessibilityLabels(); updateHighlight(); ink.setNeedsDisplay()
        }
    }
    var allowsVerseSelection = true {
        didSet { if oldValue != allowsVerseSelection { refreshAccessibilityLabels() } }
    }
    private var decorationPaths: [CGPath] = []
    var ornamentBounds: [CGRect] { decorationPaths.map(\.boundingBoxOfPath) }
    struct RowGeometry { let line: Int; let kind: String; var ink: CGRect }
    private(set) var rowGeometry: [RowGeometry] = []
    private(set) var headerClearances: [CGFloat] = []
    var onVerse: ((String?) -> Void)?
    var onFailure: (() -> Void)?
    var reduceMotion = false
    var selected: String? { didSet { if oldValue != selected { updateHighlight() } } }
    private let highlight = CAShapeLayer()
    private var ink: OriginalMushafInk!
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false
        highlight.fillColor = selectionColor.resolvedColor(with: traitCollection).cgColor
        layer.addSublayer(highlight)
        ink = OriginalMushafInk(frame: CGRect(origin: .zero, size: Self.pageSize))
        ink.owner = self; ink.isUserInteractionEnabled = false; ink.backgroundColor = .clear
        ink.isOpaque = false; addSubview(ink)
        accessibilityIdentifier = "reader.page.canvas"
        shouldGroupAccessibilityChildren = true
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func configure(page: OriginalPageData, corpus: [Surah]) {
        lines = []; shapedTexts = []; lineWordRanges = []; regions = []; decorationPaths = []; rowGeometry = []; headerClearances = []; renderedSuccessfully = false; failureReason = nil
        guard let body = UIFont(name: String(format: "QCF2%03d", page.number), size: Metrics.bodyPointSize),
              let companion = UIFont(name: OriginalMushafCompanion.name, size: Metrics.bodyPointSize) else { fail("Missing page or companion font"); return }
        // Content Sync contains ASCII separators both between logical words and
        // inside multi-glyph words. Some page fonts omit FB50 entirely. Keep
        // their codes intact and use the explicit companion blank (81 units),
        // converted from its 2048-unit em to the body's 2500-unit em.
        // No Qur'anic glyph is permitted to use this separator font.
        let space = companion.withSize(Metrics.bodyPointSize * 2048 / 2500)
        let rowHeight = Metrics.baselineInterval
        let top = page.number <= 2 ? Metrics.openingTop : Metrics.verticalMargin
        for row in page.rows {
            var ranges: [(NSRange, OriginalPageWord)] = []
            var text = ""
            let header = row.type != "ayah"
            if row.type == "surah_name", let chapter = row.chapter {
                text = OriginalMushafCompanion.title(chapter)
            } else if row.type == "basmallah" { text = OriginalMushafCompanion.basmala }
            else {
                for word in page.words.filter({ $0.line == row.line }) {
                    if !text.isEmpty { text += " " }
                    let offset = (text as NSString).length
                    text += word.code
                    ranges.append((NSRange(location: offset, length: (word.code as NSString).length), word))
                }
            }
            guard !text.isEmpty else { fail("Empty authored row \(row.line)"); return }
            let font = header ? companion : body
            let direction = NSWritingDirection.rightToLeft.rawValue | NSWritingDirectionFormatType.override.rawValue
            let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label, .writingDirection: [direction]])
            if !header {
                for (offset, scalar) in text.utf16.enumerated() where scalar == 0x20 {
                    attributed.addAttribute(.font, value: space, range: NSRange(location: offset, length: 1))
                }
            }
            let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // Original stop and vowel marks may exceed one baseline interval.
            // Validate full-page ink below; never clip or reject them by row height.
            guard !ink.isNull, !ink.isInfinite, ink.width > 0, ink.width <= 532, ink.height > 0 else { fail("Invalid authored row ink \(row.line): \(ink)"); return }
            // Baselines are fixed; vowel bounds never change line spacing.
            let rowTop = top + CGFloat(row.line - 1) * rowHeight
            // Center title ink within its original vector frame. Body and
            // basmala baselines retain the immutable authored row grid.
            let baseline = row.type == "surah_name"
                ? rowTop + 30.5 + ink.midY
                : rowTop + Metrics.baselineOffset
            let origin = CGPoint(x: row.centered ? Self.pageSize.width / 2 - ink.midX : Self.pageSize.width - Metrics.horizontalMargin - ink.maxX, y: baseline)
            let pageInk = CGRect(x: origin.x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            guard pageInk.minX >= 0, pageInk.maxX <= Self.pageSize.width,
                  pageInk.minY >= 0, pageInk.maxY <= Self.pageSize.height else {
                fail("Authored row \(row.line) exceeds page canvas: \(pageInk)"); return
            }
            lines.append((line, origin))
            shapedTexts.append(attributed.copy() as! NSAttributedString)
            lineWordRanges.append(ranges.map { ($0.0, $0.1.id) })
            rowGeometry.append(.init(line: row.line, kind: row.type, ink: pageInk))
            var wordRects: [Int: CGRect] = [:]
            var wordPaths: [Int: [CGPath]] = [:]
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let runFontValue = attributes[kCTFontAttributeName] else { fail("Missing Core Text run font"); return }
                let runFont = runFontValue as! CTFont
                let family = CTFontCopyPostScriptName(runFont) as String
                let stringRange = CTRunGetStringRange(run)
                let substring = (text as NSString).substring(with: NSRange(location: stringRange.location, length: stringRange.length))
                guard family == font.fontName || (!header && family == companion.fontName && substring.allSatisfy({ $0 == " " })) else {
                    fail("Unexpected font \(family), row \(row.line)"); return
                }
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                guard !glyphs.contains(0) else { fail("Missing shaped glyph, row \(row.line)"); return }
                for i in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                    let box = path.boundingBoxOfPath
                    guard !box.isEmpty, let entry = ranges.first(where: { NSLocationInRange(indices[i], $0.0) }) else { continue }
                    let rect = CGRect(x: origin.x + positions[i].x + box.minX,
                                      y: baseline - positions[i].y - box.maxY,
                                      width: box.width, height: box.height)
                    wordRects[entry.1.id] = wordRects[entry.1.id].map { $0.union(rect) } ?? rect
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                        tx: origin.x + positions[i].x, ty: baseline - positions[i].y)
                    if let placed = path.copy(using: &transform) { wordPaths[entry.1.id, default: []].append(placed) }
                }
            }
            for (_, word) in ranges {
                guard let rect = wordRects[word.id], rect.minX >= 0, rect.maxX <= Self.pageSize.width, rect.minY >= 0, rect.maxY <= Self.pageSize.height else { fail("Missing or clipped ink for word \(word.id), row \(row.line): \(String(describing: wordRects[word.id]))"); return }
                regions.append(Hit(word: word.id, verse: word.verse, rect: rect, paths: wordPaths[word.id] ?? []))
            }
        }
        guard arrangeHeadingGroups(top: top) else { return }
        // Authored FC20 ornament paths remain independent of title text.
        // Matching the target edition and distribution rights are review gates.
        renderedSuccessfully = true
        accessibilityElements = orderedKeys(page).compactMap { key -> UIAccessibilityElement? in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1) else { return nil }
            let element = MushafVerseAccessibility(accessibilityContainer: self)
            element.accessibilityIdentifier = "reader.verse.\(key)"
            element.verseKey = key
            element.heading = "\(corpus[parts[0] - 1].name)، الآية \(parts[1])"
            element.fullText = corpus[parts[0] - 1].ayahs[parts[1] - 1].text
            element.accessibilityTraits = .button
            element.accessibilityLanguage = "ar"
            element.action = { [weak self] in self?.onVerse?(key) }
            element.accessibilityFrameInContainerSpace = regions.first { $0.verse == key }?.rect ?? .zero
            return element
        }
        refreshAccessibilityLabels(); updateHighlight(); ink.setNeedsDisplay()
    }
    private func refreshAccessibilityLabels() {
        let hiddenVerses = Set(regions.filter { hiddenWordIDs.contains($0.word) }.map(\.verse))
        for element in accessibilityElements as? [MushafVerseAccessibility] ?? [] {
            let key = element.verseKey
            element.accessibilityTraits = allowsVerseSelection ? .button : .staticText
            element.action = allowsVerseSelection ? { [weak self] in self?.onVerse?(key) } : nil
            element.accessibilityLabel = element.heading + ". " + (hiddenVerses.contains(element.verseKey)
                ? "نص الآية مخفي للتدريب. استخدم كشف الآية لقراءتها بقارئ الشاشة؛ تُسجّل المساعدة." : element.fullText)
        }
    }
    /// A title and its separate basmala share the space between actual body ink.
    /// Body baselines, line breaks and glyph advances are never moved or resized.
    /// The same rule covers every header, including page-edge/opening groups.
    private func arrangeHeadingGroups(top: CGFloat) -> Bool {
        let font = CTFontCreateWithName(OriginalMushafCompanion.name as CFString, Metrics.bodyPointSize, nil)
        var scalar: UniChar = 0xFC20; var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &scalar, &glyph, 1), glyph != 0,
              let frame = CTFontCreatePathForGlyph(font, glyph, nil) else {
            fail("Missing original FC20 vector ornament"); return false
        }
        let box = frame.boundingBoxOfPath
        let preferredScale = (Self.pageSize.width - 2 * Metrics.horizontalMargin) / box.width
        var index = 0
        while index < rowGeometry.count {
            if rowGeometry[index].kind == "ayah" { index += 1; continue }
            let start = index
            while index < rowGeometry.count && rowGeometry[index].kind != "ayah" { index += 1 }
            let lower = start == 0 ? top : rowGeometry[start - 1].ink.maxY
            let upper = index == rowGeometry.count ? Self.pageSize.height - Metrics.verticalMargin : rowGeometry[index].ink.minY
            let titleCount = (start..<index).filter { rowGeometry[$0].kind == "surah_name" }.count
            let otherHeight = (start..<index).filter { rowGeometry[$0].kind != "surah_name" }.reduce(CGFloat.zero) { $0 + rowGeometry[$1].ink.height }
            let freeHeight = upper - lower - otherHeight - Metrics.headingGap * CGFloat(index - start + 1)
            // Preserve the original ornament aspect ratio. When authored body
            // ink leaves less room, fit the whole heading group, never the ayahs.
            let scale = titleCount > 0
                ? min(preferredScale, freeHeight / CGFloat(titleCount) / box.height)
                : preferredScale
            guard scale > 0 else { fail("No space for authored heading group"); return false }
            let frameHeight = box.height * scale
            let heights = (start..<index).map { rowGeometry[$0].kind == "surah_name" ? frameHeight : rowGeometry[$0].ink.height }
            let gap = (upper - lower - heights.reduce(0, +)) / CGFloat(heights.count + 1)
            guard gap >= 3 else { fail("Insufficient heading clearance at row \(rowGeometry[start].line): \(gap)"); return false }
            headerClearances.append(gap)
            var cursor = lower + gap
            for (offset, rowIndex) in (start..<index).enumerated() {
                let center = cursor + heights[offset] / 2
                if rowGeometry[rowIndex].kind == "surah_name" {
                    // Re-shape the title at one uniformly scaled font size to
                    // fit the ornament's central opening. No horizontal stretch.
                    let original = lines[rowIndex].0
                    let text = NSMutableAttributedString(attributedString: shapedTexts[rowIndex])
                    let originalInk = CTLineGetBoundsWithOptions(original, .useGlyphPathBounds)
                    let titleScale = min(frameHeight * Metrics.titleHeightFraction / originalInk.height,
                                         box.width * scale * Metrics.titleWidthFraction / originalInk.width)
                    let titleFont = CTFontCreateCopyWithAttributes(font, Metrics.bodyPointSize * titleScale, nil, nil)
                    text.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: titleFont,
                                      range: NSRange(location: 0, length: text.length))
                    let title = CTLineCreateWithAttributedString(text as CFAttributedString)
                    let titleInk = CTLineGetBoundsWithOptions(title, .useGlyphPathBounds)
                    guard MushafTypesetter.usesExpectedFont(title, postScriptName: OriginalMushafCompanion.name),
                          titleInk.height <= frameHeight * Metrics.titleHeightFraction + 0.01,
                          titleInk.width <= box.width * scale * Metrics.titleWidthFraction + 0.01 else {
                        fail("Title exceeds ornament opening"); return false
                    }
                    lines[rowIndex] = (title, CGPoint(x: Self.pageSize.width / 2 - titleInk.midX,
                                                      y: center + titleInk.midY))
                    rowGeometry[rowIndex].ink = CGRect(x: Self.pageSize.width / 2 - titleInk.width / 2,
                                                       y: center - titleInk.height / 2,
                                                       width: titleInk.width, height: titleInk.height)
                    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                        tx: Self.pageSize.width / 2 - box.midX * scale, ty: center + box.midY * scale)
                    guard let placed = frame.copy(using: &transform) else { fail("Invalid ornament path"); return false }
                    decorationPaths.append(placed)
                } else {
                    let delta = center - rowGeometry[rowIndex].ink.midY
                    lines[rowIndex].1.y += delta
                    rowGeometry[rowIndex].ink = rowGeometry[rowIndex].ink.offsetBy(dx: 0, dy: delta)
                }
                cursor += heights[offset] + gap
            }
        }
        return true
    }
    private func orderedKeys(_ page: OriginalPageData) -> [String] {
        var seen = Set<String>(); return page.words.compactMap { seen.insert($0.verse).inserted ? $0.verse : nil }
    }
    private func fail(_ reason: String) { failureReason = reason; lines = []; regions = []; accessibilityElements = []; ink.setNeedsDisplay(); onFailure?() }
    func redrawInk(atZoom scale: CGFloat) {
        // Re-render text after a pinch; neither shaping nor source coordinates change.
        ink.contentScaleFactor = UIScreen.main.scale * max(1, scale)
        ink.setNeedsDisplay()
    }
    func verse(at point: CGPoint) -> String? {
        let candidates = regions.filter { $0.rect.contains(point) }
        let keys = Set(candidates.map(\.verse))
        if keys.count == 1 { return keys.first }
        // Bounding boxes can overlap due to extended vowel marks. Resolve using
        // the drawn outlines, never the first/nearest neighbouring verse.
        let actual = Set(candidates.filter { $0.paths.contains { $0.contains(point) } }.map(\.verse))
        return actual.count == 1 ? actual.first : nil
    }
    private var selectionColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.86, green: 0.71, blue: 0.49, alpha: 0.28)
                : UIColor(red: 0.45, green: 0.30, blue: 0.13, alpha: 0.16)
        }
    }
    /// Use the same shaped outlines as the ink, including vowels and every line.
    /// Never paint word rectangles or the space between separate verse lines.
    func selectionPath(for key: String?) -> CGPath? {
        guard let key else { return nil }
        let chosen = regions.filter { $0.verse == key && !hiddenWordIDs.contains($0.word) }
        guard !chosen.isEmpty else { return nil }
        let glyphs = CGMutablePath()
        for region in chosen { for path in region.paths { glyphs.addPath(path) } }
        let halo = glyphs.union(glyphs.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 1))
        let neighbors = CGMutablePath()
        for region in regions where region.verse != key && !hiddenWordIDs.contains(region.word)
            && region.rect.insetBy(dx: -2, dy: -2).intersects(halo.boundingBoxOfPath) {
            for path in region.paths {
                neighbors.addPath(path)
                neighbors.addPath(path.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
        }
        return neighbors.isEmpty ? halo : halo.subtracting(neighbors)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            highlight.fillColor = selectionColor.resolvedColor(with: traitCollection).cgColor
        }
    }
    private func updateHighlight() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.path = selectionPath(for: selected)
        CATransaction.commit()
        if !reduceMotion && !UIAccessibility.isReduceMotionEnabled { let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.16; highlight.add(fade, forKey: "select") }
    }
    func drawInk() {
        guard renderedSuccessfully, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(UIColor.secondaryLabel.withAlphaComponent(0.55).cgColor)
        for path in decorationPaths { context.addPath(path); context.fillPath() }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        for (index, entry) in lines.enumerated() {
            let (line, origin) = entry
            context.textPosition = CGPoint(x: origin.x, y: bounds.height - origin.y)
            let ranges = lineWordRanges[index]
            if !ranges.contains(where: { hiddenWordIDs.contains($0.1) }) {
                CTLineDraw(line, context)
            } else {
                // Shape the full authored line once. Suppress only glyphs belonging
                // to hidden word IDs; their advances and every neighbour stay fixed.
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let count = CTRunGetGlyphCount(run)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                    for glyph in 0..<count {
                        let word = ranges.first { NSLocationInRange(indices[glyph], $0.0) }?.1
                        if word.map({ hiddenWordIDs.contains($0) }) != true {
                            // CTRunDraw may mutate the graphics context. Each partial
                            // draw starts from the same authored line origin.
                            context.saveGState()
                            context.textMatrix = .identity
                            context.textPosition = CGPoint(x: origin.x, y: bounds.height - origin.y)
                            CTRunDraw(run, context, CFRange(location: glyph, length: 1))
                            context.restoreGState()
                        }
                    }
                }
            }
        }
        context.restoreGState()
    }
}
@MainActor private final class OriginalMushafInk: UIView {
    weak var owner: OriginalMushafCanvas?
    override func draw(_ rect: CGRect) { owner?.drawInk() }
}
@MainActor private final class MushafVerseAccessibility: UIAccessibilityElement {
    var verseKey = ""
    var heading = ""
    var fullText = ""
    var action: (() -> Void)?
    override func accessibilityActivate() -> Bool { guard let action else { return false }; action(); return true }
}

@MainActor final class OriginalMushafViewport: UIScrollView, UIScrollViewDelegate {
    let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
    private var fitted: CGFloat = 0
    var onTurn: ((Int) -> Void)?
    var onToggleTools: (() -> Void)?
    private var selectionGesture: UILongPressGestureRecognizer?
    var allowsVerseSelection = true {
        didSet { canvas.allowsVerseSelection = allowsVerseSelection; selectionGesture?.isEnabled = allowsVerseSelection }
    }
    private lazy var pagingDelegate = MushafPagingGestureDelegate(viewport: self)
    var canTurnPages: Bool {
        onTurn != nil && canvas.renderedSuccessfully && minimumZoomScale > 0
            && zoomScale <= minimumZoomScale * 1.01
            && pinchGestureRecognizer?.state != .began && pinchGestureRecognizer?.state != .changed
    }
    override init(frame: CGRect) {
        super.init(frame: frame); delegate = self
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        // SwiftUI has already removed the system safe area and reader controls.
        // Applying automatic UIKit insets again shifts the authored page.
        contentInsetAdjustmentBehavior = .never
        bounces = false; bouncesZoom = false; backgroundColor = .clear; addSubview(canvas)
        accessibilityIdentifier = "reader.page.loading"
        contentSize = OriginalMushafCanvas.pageSize
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOnViewport(_:)))
        let selection = UILongPressGestureRecognizer(target: self, action: #selector(selectedOnViewport(_:)))
        selectionGesture = selection
        selection.minimumPressDuration = 0.4
        selection.allowableMovement = 10
        tap.require(toFail: selection)
        addGestureRecognizer(selection)
        for direction in [UISwipeGestureRecognizer.Direction.right, .left] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(turnPage(_:)))
            swipe.direction = direction; swipe.numberOfTouchesRequired = 1
            swipe.delegate = pagingDelegate
            addGestureRecognizer(swipe)
            tap.require(toFail: swipe)
            panGestureRecognizer.require(toFail: swipe)
        }
        tap.require(toFail: panGestureRecognizer)
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    @objc private func turnPage(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended, canTurnPages else { return }
        // RTL: swipe right advances; zoomed swipes only pan the current page.
        onTurn?(gesture.direction == .right ? 1 : -1)
    }
    @objc private func tappedOnViewport(_ tap: UITapGestureRecognizer) {
        if let onToggleTools { onToggleTools(); return }
        // UIKit applies zoom and offset when converting into the fixed canvas.
        // A margin tap stays blank; it never chooses a nearby verse.
        canvas.onVerse?(canvas.verse(at: tap.location(in: canvas)))
    }
    @objc private func selectedOnViewport(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let key = canvas.verse(at: gesture.location(in: canvas)) else { return }
        canvas.onVerse?(key)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { canvas.redrawInk(atZoom: scale) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / OriginalMushafCanvas.pageSize.width, bounds.height / OriginalMushafCanvas.pageSize.height)
        if abs(fitted - fit) > 0.00001 {
            let relativeZoom = fitted > 0 ? zoomScale / fitted : 1
            fitted = fit; minimumZoomScale = fit; maximumZoomScale = fit * 4
            zoomScale = fit * min(4, max(1, relativeZoom))
        }
        let vertical = max(0, (bounds.height - canvas.frame.height) / 2)
        let horizontal = max(0, (bounds.width - canvas.frame.width) / 2)
        let centered = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != centered { contentInset = centered }
        if zoomScale <= minimumZoomScale * 1.0001, !isDragging, !isDecelerating {
            let origin = CGPoint(x: -horizontal, y: -vertical)
            if contentOffset != origin { setContentOffset(origin, animated: false) }
        }
    }
    func resetToFittedPage() {
        setZoomScale(minimumZoomScale, animated: false)
        setNeedsLayout(); layoutIfNeeded()
        setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
    }
}
@MainActor private final class MushafPagingGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var viewport: OriginalMushafViewport?
    init(viewport: OriginalMushafViewport) { self.viewport = viewport }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewport?.canTurnPages == true
    }
}
struct OriginalMushafDrawing: UIViewRepresentable {
    let page: OriginalPageData; let corpus: [Surah]; let selected: String?; let reduceMotion: Bool
    var hiddenWordIDs: Set<Int> = []
    var allowsVerseSelection = true
    let onVerse: (String?) -> Void; let onFailure: () -> Void
    var onTurn: ((Int) -> Void)? = nil
    var onToggleTools: (() -> Void)? = nil
    func makeUIView(context: Context) -> OriginalMushafViewport { OriginalMushafViewport() }
    func updateUIView(_ view: OriginalMushafViewport, context: Context) {
        view.allowsVerseSelection = allowsVerseSelection
        view.canvas.onVerse = onVerse; view.canvas.onFailure = onFailure; view.canvas.reduceMotion = reduceMotion
        view.onTurn = onTurn
        view.onToggleTools = onToggleTools
        if context.coordinator.page != page.number || !view.canvas.renderedSuccessfully {
            let animate = context.coordinator.page != nil && context.coordinator.page != page.number
                && !reduceMotion && !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
            context.coordinator.page = page.number
            let change = {
                view.canvas.configure(page: self.page, corpus: self.corpus)
                view.canvas.selected = self.selected
                view.canvas.hiddenWordIDs = self.hiddenWordIDs
                view.resetToFittedPage()
                view.canvas.setNeedsDisplay(); view.canvas.layoutIfNeeded()
            }
            if animate {
                // Fade the whole authored page, never reshape, stretch or move words.
                UIView.transition(with: view, duration: 0.2,
                    options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState], animations: change, completion: nil)
            } else { UIView.performWithoutAnimation(change) }
        }
        view.accessibilityIdentifier = view.canvas.renderedSuccessfully ? "reader.page.ready" : "reader.page.failed"
        view.canvas.selected = selected
        view.canvas.hiddenWordIDs = hiddenWordIDs
    }
    final class Coordinator { var page: Int? }
    func makeCoordinator() -> Coordinator { Coordinator() }
}
