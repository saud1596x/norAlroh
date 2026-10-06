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
    struct Hit { let word: Int; let verse: String; let rect: CGRect; let paths: [CGPath] }
    private(set) var regions: [Hit] = []
    private(set) var renderedSuccessfully = false
    private(set) var failureReason: String?
    private var lines: [(CTLine, CGPoint)] = []
    private var lineWordRanges: [[(NSRange, Int)]] = []
    var hiddenWordIDs: Set<Int> = [] {
        didSet {
            guard oldValue != hiddenWordIDs else { return }
            refreshAccessibilityLabels(); ink.setNeedsDisplay()
        }
    }
    private var decorationPaths: [CGPath] = []
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
        highlight.fillColor = UIColor.systemYellow.withAlphaComponent(0.22).cgColor
        layer.addSublayer(highlight)
        ink = OriginalMushafInk(frame: CGRect(origin: .zero, size: Self.pageSize))
        ink.owner = self; ink.isUserInteractionEnabled = false; ink.backgroundColor = .clear
        ink.isOpaque = false; addSubview(ink)
        accessibilityIdentifier = "reader.page.canvas"
        shouldGroupAccessibilityChildren = true
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func configure(page: OriginalPageData, corpus: [Surah]) {
        lines = []; lineWordRanges = []; regions = []; decorationPaths = []; rowGeometry = []; headerClearances = []; renderedSuccessfully = false; failureReason = nil
        guard let body = UIFont(name: String(format: "QCF2%03d", page.number), size: 32),
              let companion = UIFont(name: OriginalMushafCompanion.name, size: 32) else { fail("Missing page or companion font"); return }
        // Content Sync contains ASCII separators both between logical words and
        // inside multi-glyph words. Some page fonts omit FB50 entirely. Keep
        // their codes intact and use the explicit companion blank (81 units),
        // converted from its 2048-unit em to the body's 2500-unit em.
        // No Qur'anic glyph is permitted to use this separator font.
        let space = companion.withSize(32 * 2048 / 2500)
        let rowHeight: CGFloat = 61
        let top: CGFloat = page.number <= 2 ? 214 : 7
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
                : rowTop + 48
            let origin = CGPoint(x: row.centered ? Self.pageSize.width / 2 - ink.midX : Self.pageSize.width - 15 - ink.maxX, y: baseline)
            let pageInk = CGRect(x: origin.x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            guard pageInk.minX >= 0, pageInk.maxX <= Self.pageSize.width,
                  pageInk.minY >= 0, pageInk.maxY <= Self.pageSize.height else {
                fail("Authored row \(row.line) exceeds page canvas: \(pageInk)"); return
            }
            lines.append((line, origin))
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
            element.accessibilityLabel = element.heading + ". " + (hiddenVerses.contains(element.verseKey)
                ? "نص الآية مخفي للتدريب. استخدم كشف الكلمات للمساعدة." : element.fullText)
        }
    }
    /// A title and its separate basmala share the space between actual body ink.
    /// Body baselines, line breaks and glyph advances are never moved or resized.
    /// The same rule covers every header, including page-edge/opening groups.
    private func arrangeHeadingGroups(top: CGFloat) -> Bool {
        let font = CTFontCreateWithName(OriginalMushafCompanion.name as CFString, 32, nil)
        var scalar: UniChar = 0xFC20; var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &scalar, &glyph, 1), glyph != 0,
              let frame = CTFontCreatePathForGlyph(font, glyph, nil) else {
            fail("Missing original FC20 vector ornament"); return false
        }
        let box = frame.boundingBoxOfPath
        let scale = min(532 / box.width, 57 / box.height)
        let frameHeight = box.height * scale
        var index = 0
        while index < rowGeometry.count {
            if rowGeometry[index].kind == "ayah" { index += 1; continue }
            let start = index
            while index < rowGeometry.count && rowGeometry[index].kind != "ayah" { index += 1 }
            let lower = start == 0 ? top : rowGeometry[start - 1].ink.maxY
            let upper = index == rowGeometry.count ? Self.pageSize.height - 7 : rowGeometry[index].ink.minY
            let heights = (start..<index).map { rowGeometry[$0].kind == "surah_name" ? frameHeight : rowGeometry[$0].ink.height }
            let gap = (upper - lower - heights.reduce(0, +)) / CGFloat(heights.count + 1)
            guard gap >= 3 else { fail("Insufficient heading clearance at row \(rowGeometry[start].line): \(gap)"); return false }
            headerClearances.append(gap)
            var cursor = lower + gap
            for (offset, rowIndex) in (start..<index).enumerated() {
                let center = cursor + heights[offset] / 2
                let delta = center - rowGeometry[rowIndex].ink.midY
                lines[rowIndex].1.y += delta
                rowGeometry[rowIndex].ink = rowGeometry[rowIndex].ink.offsetBy(dx: 0, dy: delta)
                if rowGeometry[rowIndex].kind == "surah_name" {
                    guard rowGeometry[rowIndex].ink.height < frameHeight - 6 else {
                        fail("Title does not fit original ornament"); return false
                    }
                    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                        tx: Self.pageSize.width / 2 - box.midX * scale, ty: center + box.midY * scale)
                    guard let placed = frame.copy(using: &transform) else { fail("Invalid ornament path"); return false }
                    decorationPaths.append(placed)
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
    private func updateHighlight() {
        let path = UIBezierPath()
        for region in regions where region.verse == selected { path.append(UIBezierPath(roundedRect: region.rect.insetBy(dx: -0.8, dy: -0.8), cornerRadius: 2)) }
        CATransaction.begin(); CATransaction.setDisableActions(true); highlight.path = path.cgPath; CATransaction.commit()
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
                            CTRunDraw(run, context, CFRange(location: glyph, length: 1))
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
    override func accessibilityActivate() -> Bool { action?(); return true }
}

@MainActor final class OriginalMushafViewport: UIScrollView, UIScrollViewDelegate {
    let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
    private var fitted: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame); delegate = self
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        bouncesZoom = true; backgroundColor = .clear; addSubview(canvas)
        accessibilityIdentifier = "reader.page.loading"
        contentSize = OriginalMushafCanvas.pageSize
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOnViewport(_:)))
        tap.require(toFail: panGestureRecognizer)
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    @objc private func tappedOnViewport(_ tap: UITapGestureRecognizer) {
        // UIKit applies zoom and offset when converting into the fixed canvas.
        // A margin tap stays blank; it never chooses a nearby verse.
        canvas.onVerse?(canvas.verse(at: tap.location(in: canvas)))
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { canvas.redrawInk(atZoom: scale) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / OriginalMushafCanvas.pageSize.width, bounds.height / OriginalMushafCanvas.pageSize.height)
        if abs(fitted - fit) > 0.001 {
            fitted = fit; minimumZoomScale = fit; maximumZoomScale = fit * 4; zoomScale = fit
        }
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - canvas.frame.height) / 2), left: max(0, (bounds.width - canvas.frame.width) / 2), bottom: 0, right: 0)
    }
}
struct OriginalMushafDrawing: UIViewRepresentable {
    let page: OriginalPageData; let corpus: [Surah]; let selected: String?; let reduceMotion: Bool
    var hiddenWordIDs: Set<Int> = []
    let onVerse: (String?) -> Void; let onFailure: () -> Void
    func makeUIView(context: Context) -> OriginalMushafViewport { OriginalMushafViewport() }
    func updateUIView(_ view: OriginalMushafViewport, context: Context) {
        view.canvas.onVerse = onVerse; view.canvas.onFailure = onFailure; view.canvas.reduceMotion = reduceMotion
        if context.coordinator.page != page.number || !view.canvas.renderedSuccessfully {
            context.coordinator.page = page.number
            view.canvas.configure(page: page, corpus: corpus)
            view.setZoomScale(view.minimumZoomScale, animated: false)
        }
        view.accessibilityIdentifier = view.canvas.renderedSuccessfully ? "reader.page.ready" : "reader.page.failed"
        view.canvas.selected = selected
        view.canvas.hiddenWordIDs = hiddenWordIDs
    }
    final class Coordinator { var page: Int? }
    func makeCoordinator() -> Coordinator { Coordinator() }
}
