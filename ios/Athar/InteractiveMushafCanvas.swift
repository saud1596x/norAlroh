import UIKit
import SwiftUI
import CoreText
import CryptoKit

/// Research candidate: QCF V2 page fonts and authored V2 row alignment.
/// Word IDs always come from Content Sync; QUL's token IDs are never imported.
struct OriginalMushafRows: Decodable, Sendable {
    struct Row: Decodable, Sendable, Equatable { let page: Int; let line: Int; let type: String; let centered: Bool; let chapter: Int? }
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

struct OriginalPageWord: Equatable {
    let id: Int; let verse: String; let code: String; let line: Int; let order: Int
}
struct OriginalPageData: Equatable {
    let number: Int; let words: [OriginalPageWord]; let rows: [OriginalMushafRows.Row]
    static func index(snapshot: QCFV2Snapshot, rows: OriginalMushafRows, keys: [String]) -> [Int: Self] {
        let records = Dictionary(grouping: snapshot.records.filter { $0.record_type == "mushaf_word" }, by: { $0.page_number! })
        let pageRows = Dictionary(grouping: rows.rows, by: \.page)
        return Dictionary(uniqueKeysWithValues: (1...604).map { number in
            let words = (records[number] ?? []).sorted { $0.position_in_page! < $1.position_in_page! }.map {
                OriginalPageWord(id: $0.id, verse: keys[$0.verse_id! - 1], code: $0.text!,
                    line: $0.line_number! - (number <= 2 ? 7 : 0), order: $0.position_in_page!)
            }
            return (number, Self(number: number, words: words, rows: pageRows[number] ?? []))
        })
    }
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
    private var wordLines: [Int: Int] = [:]
    var tajweedEnabled = false
    private var coloredInk: [(Int, CGPath, UIColor)] = []
    private struct ShapedPage {
        let page: OriginalPageData
        let style: UIUserInterfaceStyle
        let tajweed: Bool
        let coloredInk: [(Int, CGPath, UIColor)]
        let lines: [(CTLine, CGPoint)]
        let texts: [NSAttributedString]
        let ranges: [[(NSRange, Int)]]
        let regions: [Hit]
        let wordLines: [Int: Int]
        let decorations: [CGPath]
        let geometry: [RowGeometry]
        let clearances: [CGFloat]
    }
    // Bound the cache to nearby pages, and validate the complete authored page
    // rather than only its number. Never retain reader/session highlights here.
    private var shapedPages: [ShapedPage] = []
    private(set) var shapingPasses = 0
    var hiddenWordIDs: Set<Int> = [] {
        didSet {
            guard oldValue != hiddenWordIDs else { return }
            refreshAccessibilityLabels(); updateHighlight(); ink.setNeedsDisplay()
        }
    }
    var reviewWordIDs: Set<Int> = [] {
        didSet { if oldValue != reviewWordIDs { refreshAccessibilityLabels(); updateHighlight() } }
    }
    var hiddenTextAccessibilityHint = "نص الآية مخفي للتدريب. استخدم كشف الآية لقراءتها بقارئ الشاشة؛ تُسجّل المساعدة." {
        didSet { if oldValue != hiddenTextAccessibilityHint { refreshAccessibilityLabels() } }
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
    var selected: String? { didSet { if oldValue != selected { updateHighlight(animateSelection: true) } } }
    var activeWordID: Int? { didSet { if oldValue != activeWordID { updateActiveWord() } } }
    private let highlight = CAShapeLayer()
    private let activeWord = CAShapeLayer()
    private let reviewUnderline = CAShapeLayer()
    private var ink: OriginalMushafInk!
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false
        highlight.fillColor = selectionColor.resolvedColor(with: traitCollection).cgColor
        layer.addSublayer(highlight)
        activeWord.fillColor = nil
        activeWord.lineWidth = 2.5
        activeWord.lineCap = .round
        layer.addSublayer(activeWord)
        reviewUnderline.fillColor = nil
        reviewUnderline.strokeColor = UIColor.secondaryLabel.cgColor
        reviewUnderline.lineWidth = 1.5; reviewUnderline.lineDashPattern = [3, 3]
        layer.addSublayer(reviewUnderline)
        ink = OriginalMushafInk(frame: CGRect(origin: .zero, size: Self.pageSize))
        ink.owner = self; ink.isUserInteractionEnabled = false; ink.backgroundColor = .clear
        ink.isOpaque = false; addSubview(ink)
        accessibilityIdentifier = "reader.page.canvas"
        shouldGroupAccessibilityChildren = true
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    /// V2 and V4 have different advances. Match the original page's widest
    /// authored row with one uniform V4 size, rather than shrinking all 604
    /// pages to the worst-case 23pt size. No word/row is squeezed separately.
    private func tajweedBodyFont(page: OriginalPageData, reference: UIFont,
                                 colored: UIFont, space: UIFont) -> UIFont? {
        let texts = page.rows.filter { $0.type == "ayah" }.map { row in
            (row.line, page.words.filter { $0.line == row.line }.map(\.code).joined(separator: " "))
        }
        func bounds(_ text: String, font: UIFont) -> CGRect {
            let direction = NSWritingDirection.rightToLeft.rawValue | NSWritingDirectionFormatType.override.rawValue
            let value = NSMutableAttributedString(string: text, attributes: [.font: font, .writingDirection: [direction]])
            for (offset, scalar) in text.utf16.enumerated() where scalar == 0x20 {
                value.addAttribute(.font, value: space, range: NSRange(location: offset, length: 1))
            }
            return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(value as CFAttributedString), .useGlyphPathBounds)
        }
        let target = texts.map { bounds($0.1, font: reference).width }.max() ?? 0
        guard target.isFinite, target > 0 else { return nil }
        var size: CGFloat = 64
        let top = page.number <= 2 ? Metrics.openingTop : Metrics.verticalMargin
        for (row, text) in texts {
            let half = bounds(text, font: colored.withSize(16))
            let full = bounds(text, font: colored.withSize(32))
            let slope = (full.width - half.width) / 16
            guard slope.isFinite, slope > 0 else { return nil }
            // Blank companion separators retain their original advances. Two
            // measurements account for that fixed width instead of scaling it.
            let fixed = full.width - slope * 32
            size = min(size, (target - 0.1 - fixed) / slope)
            let baseline = top + CGFloat(row - 1) * Metrics.baselineInterval + Metrics.baselineOffset
            if full.maxY > 0 { size = min(size, (baseline - 0.1) * 32 / full.maxY) }
            if full.minY < 0 { size = min(size, (Self.pageSize.height - baseline - 0.1) * 32 / -full.minY) }
        }
        guard size.isFinite, size > 0 else { return nil }
        let result = colored.withSize(size)
        for (row, text) in texts {
            let ink = bounds(text, font: result)
            let baseline = top + CGFloat(row - 1) * Metrics.baselineInterval + Metrics.baselineOffset
            guard !ink.isNull, !ink.isInfinite, ink.width <= target + 0.1,
                  baseline - ink.maxY >= -0.01,
                  baseline - ink.minY <= Self.pageSize.height + 0.01 else { return nil }
        }
        return result
    }
    func configure(page: OriginalPageData, corpus: [Surah]) {
        if let saved = shapedPages.first(where: { $0.page == page && $0.style == traitCollection.userInterfaceStyle && $0.tajweed == tajweedEnabled }) {
            lines = saved.lines; shapedTexts = saved.texts; lineWordRanges = saved.ranges
            regions = saved.regions; wordLines = saved.wordLines; decorationPaths = saved.decorations
            rowGeometry = saved.geometry; headerClearances = saved.clearances
            coloredInk = saved.coloredInk
            renderedSuccessfully = true; failureReason = nil
            configureAccessibility(page: page, corpus: corpus)
            return
        }
        shapingPasses += 1
        coloredInk = []
        lines = []; shapedTexts = []; lineWordRanges = []; regions = []; decorationPaths = []; rowGeometry = []; headerClearances = []; renderedSuccessfully = false; failureReason = nil
        wordLines = Dictionary(uniqueKeysWithValues: page.words.map { ($0.id, $0.line) })
        let tajweedPage: MushafTajweedFonts.Page?
        do { tajweedPage = tajweedEnabled ? try MushafTajweedFonts.load(page.number) : nil }
        catch { fail("Original Tajweed font integrity failed"); return }
        guard let original = UIFont(name: String(format: "QCF2%03d", page.number), size: Metrics.bodyPointSize),
              let companion = UIFont(name: OriginalMushafCompanion.name, size: Metrics.bodyPointSize) else { fail("Missing page or companion font"); return }
        // Content Sync contains ASCII separators both between logical words and
        // inside multi-glyph words. Some page fonts omit FB50 entirely. Keep
        // their codes intact and use the explicit companion blank (81 units),
        // converted from its 2048-unit em to the body's 2500-unit em.
        // No Qur'anic glyph is permitted to use this separator font.
        let space = companion.withSize(Metrics.bodyPointSize * 2048 / 2500)
        let body: UIFont
        if let tajweedPage {
            guard let colored = UIFont(name: tajweedPage.family, size: Metrics.bodyPointSize),
                  let fitted = tajweedBodyFont(page: page, reference: original, colored: colored, space: space) else {
                fail("Tajweed page cannot retain the original reading extent"); return
            }
            body = fitted
        } else { body = original }
        let rowHeight = Metrics.baselineInterval
        let top = page.number <= 2 ? Metrics.openingTop : Metrics.verticalMargin
        var referenceRows: [RowGeometry] = []
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
            // Core Text receives a resolved color. A detached drawing context
            // need not share this view's trait collection (for example a dark
            // renderer inside a light host or an exported native capture).
            let attributed = NSMutableAttributedString(string: text, attributes: [.font: font,
                .foregroundColor: UIColor.label.resolvedColor(with: traitCollection), .writingDirection: [direction]])
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
            // Every authored row uses the same page axis. Preserve the source's
            // centered/right-aligned distinction without a body-only offset.
            let origin = CGPoint(x: row.centered ? Self.pageSize.width / 2 - ink.midX
                : Self.pageSize.width - Metrics.horizontalMargin - ink.maxX, y: baseline)
            let pageInk = CGRect(x: origin.x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            guard pageInk.minX >= 0, pageInk.maxX <= Self.pageSize.width,
                  pageInk.minY >= 0, pageInk.maxY <= Self.pageSize.height else {
                fail("Authored row \(row.line) exceeds page canvas: \(pageInk)"); return
            }
            lines.append((line, origin))
            shapedTexts.append(attributed.copy() as! NSAttributedString)
            lineWordRanges.append(ranges.map { ($0.0, $0.1.id) })
            rowGeometry.append(.init(line: row.line, kind: row.type, ink: pageInk))
            // Heading anchors belong to the fixed V2 edition, not the currently
            // painted outline. V4 vowel bounds differ: using their live ink to
            // lay out a heading moved its title, ornament and basmala whenever
            // Tajweed was toggled. Measure the unchanged source line instead.
            var sourceInk = ink
            if !header, tajweedPage != nil {
                let source = NSMutableAttributedString(attributedString: attributed)
                source.addAttribute(.font, value: original, range: NSRange(location: 0, length: source.length))
                for (offset, scalar) in text.utf16.enumerated() where scalar == 0x20 {
                    source.addAttribute(.font, value: space, range: NSRange(location: offset, length: 1))
                }
                sourceInk = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(source as CFAttributedString), .useGlyphPathBounds)
            }
            let sourceOriginX = row.centered ? Self.pageSize.width / 2 - sourceInk.midX
                : Self.pageSize.width - Metrics.horizontalMargin - sourceInk.maxX
            referenceRows.append(.init(line: row.line, kind: row.type,
                ink: CGRect(x: sourceOriginX + sourceInk.minX, y: baseline - sourceInk.maxY,
                            width: sourceInk.width, height: sourceInk.height)))
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
                // A compound canonical word may contain ASCII separators.
                // Their companion-font glyph IDs are not page-font glyph IDs;
                // never look them up in the page's COLR table. Advances remain
                // in the whole shaped line, but blank separators have no ink.
                if !header && family == companion.fontName && substring.allSatisfy({ $0 == " " }) { continue }
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                guard !glyphs.contains(0) else { fail("Missing shaped glyph, row \(row.line)"); return }
                for i in 0..<count {
                    guard let entry = ranges.first(where: { NSLocationInRange(indices[i], $0.0) }) else { continue }
                    let parts: [(CGPath, UIColor)]
                    if let tajweedPage {
                        parts = tajweedPage.paths(glyph: glyphs[i], font: runFont, dark: traitCollection.userInterfaceStyle == .dark)
                    } else { parts = CTFontCreatePathForGlyph(runFont, glyphs[i], nil).map { [($0, UIColor.label)] } ?? [] }
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                        tx: origin.x + positions[i].x, ty: baseline - positions[i].y)
                    for (path, color) in parts where !path.boundingBoxOfPath.isEmpty {
                        guard let placed = path.copy(using: &transform) else { continue }
                        let rect = placed.boundingBoxOfPath
                        wordRects[entry.1.id] = wordRects[entry.1.id].map { $0.union(rect) } ?? rect
                        wordPaths[entry.1.id, default: []].append(placed)
                        if tajweedEnabled { coloredInk.append((entry.1.id, placed, color)) }
                    }
                }
            }
            for (_, word) in ranges {
                guard let rect = wordRects[word.id], rect.minX >= 0, rect.maxX <= Self.pageSize.width, rect.minY >= 0, rect.maxY <= Self.pageSize.height else { fail("Missing or clipped ink for word \(word.id), row \(row.line): \(String(describing: wordRects[word.id]))"); return }
                regions.append(Hit(word: word.id, verse: word.verse, rect: rect, paths: wordPaths[word.id] ?? []))
            }
        }
        guard arrangeHeadingGroups(top: top, referenceRows: referenceRows) else { return }
        // Authored FC20 ornament paths remain independent of title text.
        // Matching the target edition and distribution rights are review gates.
        renderedSuccessfully = true
        shapedPages.removeAll { $0.page.number == page.number && $0.tajweed == tajweedEnabled }
        shapedPages.append(ShapedPage(page: page, style: traitCollection.userInterfaceStyle,
            tajweed: tajweedEnabled, coloredInk: coloredInk,
            lines: lines, texts: shapedTexts, ranges: lineWordRanges, regions: regions,
            wordLines: wordLines, decorations: decorationPaths, geometry: rowGeometry, clearances: headerClearances))
        if shapedPages.count > 3 { shapedPages.removeFirst(shapedPages.count - 3) }
        configureAccessibility(page: page, corpus: corpus)
    }
    private func configureAccessibility(page: OriginalPageData, corpus: [Surah]) {
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
                ? hiddenTextAccessibilityHint : element.fullText)
            if regions.contains(where: { $0.verse == key && reviewWordIDs.contains($0.word) && !hiddenWordIDs.contains($0.word) }) {
                element.accessibilityLabel = (element.accessibilityLabel ?? "") + ". توجد ملاحظة صوتية غير محسومة للمراجعة، وليست خطأ مؤكدًا."
            }
        }
    }
    /// A title and its separate basmala share the space between actual body ink.
    /// Body baselines, line breaks and glyph advances are never moved or resized.
    /// The same rule covers every header, including page-edge/opening groups.
    private func arrangeHeadingGroups(top: CGFloat, referenceRows: [RowGeometry]) -> Bool {
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
            let lower = start == 0 ? top : referenceRows[start - 1].ink.maxY
            let upper = index == rowGeometry.count ? Self.pageSize.height - Metrics.verticalMargin : referenceRows[index].ink.minY
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
                ? UIColor(red: 1, green: 0.83, blue: 0.12, alpha: 0.45)
                : UIColor(red: 1, green: 0.85, blue: 0.10, alpha: 0.58)
        }
    }
    /// A continuous yellow band follows each visible run on its authored row.
    /// Hidden words and neighboring ayat split bands; glyphs never move.
    func selectionPath(for key: String?) -> CGPath? {
        guard let key else { return nil }
        let chosen = regions.filter { $0.verse == key && !hiddenWordIDs.contains($0.word) }
        guard !chosen.isEmpty else { return nil }
        let bands = CGMutablePath()
        for row in Dictionary(grouping: regions, by: { wordLines[$0.word] ?? $0.word }).values {
            var band = CGRect.null
            func flush() {
                guard !band.isNull else { return }
                bands.addRoundedRect(in: band.insetBy(dx: -2, dy: -2), cornerWidth: 3, cornerHeight: 3)
                band = .null
            }
            for region in row.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                if region.verse == key && !hiddenWordIDs.contains(region.word) { band = band.union(region.rect) }
                else { flush() }
            }
            flush()
        }
        let halo: CGPath = bands
        var neighbors: CGPath = CGMutablePath()
        for region in regions where region.verse != key && !hiddenWordIDs.contains(region.word)
            && region.rect.insetBy(dx: -2, dy: -2).intersects(halo.boundingBoxOfPath) {
            for path in region.paths {
                // Appending glyph contours and stroked contours can cancel
                // opposite windings and leave holes in the exclusion mask.
                // Boolean union preserves both filled areas before subtraction.
                let margin = path.copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
                neighbors = neighbors.union(path.union(margin))
            }
        }
        return neighbors.isEmpty ? halo : halo.subtracting(neighbors)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            highlight.fillColor = selectionColor.resolvedColor(with: traitCollection).cgColor
            ink.setNeedsDisplay()
        }
    }
    func reviewPath() -> CGPath? {
        let path = CGMutablePath()
        for region in regions where reviewWordIDs.contains(region.word) && !hiddenWordIDs.contains(region.word) {
            let y = min(Self.pageSize.height - 1, region.rect.maxY + 2)
            path.move(to: CGPoint(x: region.rect.minX, y: y))
            path.addLine(to: CGPoint(x: region.rect.maxX, y: y))
        }
        return path.isEmpty ? nil : path
    }
    private func updateHighlight(animateSelection: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.path = selectionPath(for: selected)
        activeWord.strokeColor = UIColor.systemOrange.resolvedColor(with: traitCollection).cgColor
        activeWord.path = activeWordPath()
        reviewUnderline.strokeColor = UIColor.secondaryLabel.resolvedColor(with: traitCollection).cgColor
        reviewUnderline.path = reviewPath()
        CATransaction.commit()
        if animateSelection && selected != nil && !reduceMotion && !UIAccessibility.isReduceMotionEnabled { let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.16; highlight.add(fade, forKey: "select") }
    }
    private func updateActiveWord() {
        // Moving between words must not rebuild or flash the ayah's yellow band.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        activeWord.strokeColor = UIColor.systemOrange.resolvedColor(with: traitCollection).cgColor
        activeWord.path = activeWordPath()
        CATransaction.commit()
    }
    func activeWordPath() -> CGPath? {
        guard let activeWordID, !hiddenWordIDs.contains(activeWordID),
              let region = regions.first(where: { $0.word == activeWordID }) else { return nil }
        let path = CGMutablePath()
        let y = min(Self.pageSize.height - 2, region.rect.maxY + 3)
        path.move(to: CGPoint(x: region.rect.minX, y: y))
        path.addLine(to: CGPoint(x: region.rect.maxX, y: y))
        return path
    }
    func drawInk() {
        guard renderedSuccessfully, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(UIColor.secondaryLabel.resolvedColor(with: traitCollection).withAlphaComponent(0.55).cgColor)
        for path in decorationPaths { context.addPath(path); context.fillPath() }
        for (word, path, color) in coloredInk where !hiddenWordIDs.contains(word) {
            context.setFillColor(color.resolvedColor(with: traitCollection).cgColor); context.addPath(path); context.fillPath()
        }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        for (index, entry) in lines.enumerated() {
            let (line, origin) = entry
            context.textPosition = CGPoint(x: origin.x, y: bounds.height - origin.y)
            let ranges = lineWordRanges[index]
            if tajweedEnabled && !ranges.isEmpty { continue }
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
    var pageNumber = 1
    var pageRange: ClosedRange<Int> = 1...604
    var allowsManualPageTurns = true {
        didSet {
            guard oldValue != allowsManualPageTurns, !allowsManualPageTurns else { return }
            // Playback can begin while a finger is dragging. Cancel that visual
            // offset as well as rejecting the gesture's eventual page commit.
            canvas.layer.removeAnimation(forKey: "pageDragReturn")
            CATransaction.begin(); CATransaction.setDisableActions(true)
            canvas.layer.sublayerTransform = CATransform3DIdentity
            CATransaction.commit()
        }
    }
    private(set) var turningPage = false
    private var turnSnapshot: UIView?
    private var turnGeneration = UUID()
    var readingMagnification: CGFloat = 1 {
        didSet {
            guard readingMagnification != oldValue, minimumZoomScale > 0 else { return }
            resetToFittedPage()
        }
    }
    var onTurn: ((Int) -> Void)?
    var onToggleTools: (() -> Void)?
    private var selectionGesture: UILongPressGestureRecognizer?
    var allowsVerseSelection = true {
        didSet { canvas.allowsVerseSelection = allowsVerseSelection; selectionGesture?.isEnabled = allowsVerseSelection }
    }
    private lazy var pagingDelegate = MushafPagingGestureDelegate(viewport: self)
    var canTurnPages: Bool {
        allowsManualPageTurns && !turningPage && onTurn != nil && canvas.renderedSuccessfully && minimumZoomScale > 0
            && zoomScale <= minimumZoomScale * max(1, readingMagnification) * 1.01
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
        let paging = UIPanGestureRecognizer(target: self, action: #selector(dragPage(_:)))
        paging.maximumNumberOfTouches = 1
        paging.delegate = pagingDelegate
        addGestureRecognizer(paging)
        tap.require(toFail: paging)
        paging.require(toFail: selection)
        panGestureRecognizer.require(toFail: paging)
        tap.require(toFail: panGestureRecognizer)
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    @objc private func dragPage(_ gesture: UIPanGestureRecognizer) {
        let distance = gesture.translation(in: self).x
        let motionAllowed = !canvas.reduceMotion && !UIAccessibility.isReduceMotionEnabled
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
        switch gesture.state {
        case .began, .changed:
            guard canTurnPages, motionAllowed else { return }
            canvas.layer.removeAnimation(forKey: "pageDragReturn")
            let edge = (distance > 0 && pageNumber == pageRange.upperBound) || (distance < 0 && pageNumber == pageRange.lowerBound)
            let travel = max(-bounds.width * 0.85, min(bounds.width * 0.85, distance)) * (edge ? 0.15 : 1)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            canvas.layer.sublayerTransform = CATransform3DMakeTranslation(travel / max(zoomScale, 0.001), 0, 0)
            CATransaction.commit()
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: self).x
            let target = pageNumber + (distance > 0 ? 1 : -1)
            let committed = gesture.state == .ended && canTurnPages && pageRange.contains(target)
                && (abs(distance) >= bounds.width * 0.18 || (abs(distance) >= max(12, bounds.width * 0.08) && abs(velocity) >= 550 && distance * velocity > 0))
            let previous = canvas.layer.sublayerTransform
            if committed {
                // Keep the finger's final offset until the next authored page
                // is ready. Resetting here causes a visible backwards jump.
                turningPage = true
                onTurn?(distance > 0 ? 1 : -1)
                let generation = turnGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, self.turnGeneration == generation, self.turnSnapshot == nil else { return }
                    self.turningPage = false; self.resetToFittedPage()
                }
            } else {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                canvas.layer.sublayerTransform = CATransform3DIdentity
                CATransaction.commit()
                guard motionAllowed else { return }
                let settle = CABasicAnimation(keyPath: "sublayerTransform")
                settle.fromValue = NSValue(caTransform3D: previous)
                settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                settle.duration = 0.2
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                canvas.layer.add(settle, forKey: "pageDragReturn")
            }
        default: break
        }
    }
    @objc private func tappedOnViewport(_ tap: UITapGestureRecognizer) {
        handleShortTap()
    }
    func handleShortTap() {
        guard !turningPage else { return }
        // A short tap has one meaning on both text and margins. Verse tools
        // belong to the long press or its equivalent accessibility action.
        onToggleTools?()
    }
    @objc private func selectedOnViewport(_ gesture: UILongPressGestureRecognizer) {
        guard !turningPage, gesture.state == .began,
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
            let relativeZoom = fitted > 0 ? zoomScale / fitted : max(1, readingMagnification)
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
        canvas.layer.removeAnimation(forKey: "pageDragReturn")
        canvas.layer.sublayerTransform = CATransform3DIdentity
        setZoomScale(minimumZoomScale * max(1, min(2, readingMagnification)), animated: false)
        setNeedsLayout(); layoutIfNeeded()
        setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
    }
    func replacePage(number: Int, animated: Bool, change: () -> Void) {
        let previousPage = pageNumber
        let drag = CGFloat(canvas.layer.sublayerTransform.m41) * zoomScale
        turnGeneration = UUID()
        let generation = turnGeneration
        let outgoing = animated ? snapshotView(afterScreenUpdates: false) : nil
        turnSnapshot?.removeFromSuperview(); turnSnapshot = nil
        canvas.layer.removeAnimation(forKey: "pageArrival")
        pageNumber = number
        UIView.performWithoutAnimation(change)
        guard let outgoing, animated, bounds.width > 0 else { turningPage = false; return }
        turningPage = true
        // Snapshot the already-dragged page. Place the new complete page one
        // screen behind it, so release continues from the finger's position.
        outgoing.frame = bounds
        outgoing.isUserInteractionEnabled = false
        outgoing.accessibilityElementsHidden = true
        addSubview(outgoing); turnSnapshot = outgoing
        let adjacent = abs(number - previousPage) == 1
        let direction: CGFloat = number > previousPage ? 1 : -1
        let remaining = direction * bounds.width - drag
        if adjacent {
            let arrival = CABasicAnimation(keyPath: "sublayerTransform")
            arrival.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(-remaining / max(zoomScale, 0.001), 0, 0))
            arrival.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            arrival.duration = 0.24
            arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
            canvas.layer.add(arrival, forKey: "pageArrival")
        }
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            if adjacent { outgoing.transform = CGAffineTransform(translationX: remaining, y: 0) }
            else { outgoing.alpha = 0 }
        } completion: { [weak self, weak outgoing] _ in
            outgoing?.removeFromSuperview()
            guard let self, self.turnGeneration == generation else { return }
            self.turnSnapshot = nil; self.turningPage = false
        }
    }
}
@MainActor private final class MushafPagingGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var viewport: OriginalMushafViewport?
    init(viewport: OriginalMushafViewport) { self.viewport = viewport }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let viewport, viewport.canTurnPages,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: viewport)
        return abs(velocity.x) > abs(velocity.y) * 1.2
    }
}
struct OriginalMushafDrawing: UIViewRepresentable {
    let page: OriginalPageData; let corpus: [Surah]; let selected: String?; let reduceMotion: Bool
    var hiddenWordIDs: Set<Int> = []
    var reviewWordIDs: Set<Int> = []
    var activeWordID: Int? = nil
    var tajweedEnabled = false
    var pageRange: ClosedRange<Int> = 1...604
    var allowsManualPageTurns = true
    var allowsVerseSelection = true
    var readingMagnification: CGFloat = 1
    var hiddenTextAccessibilityHint = "نص الآية مخفي للتدريب. استخدم كشف الآية لقراءتها بقارئ الشاشة؛ تُسجّل المساعدة."
    let onVerse: (String?) -> Void; let onFailure: () -> Void
    var onTurn: ((Int) -> Void)? = nil
    var onToggleTools: (() -> Void)? = nil
    func makeUIView(context: Context) -> OriginalMushafViewport { OriginalMushafViewport() }
    func updateUIView(_ view: OriginalMushafViewport, context: Context) {
        view.readingMagnification = readingMagnification
        view.pageRange = pageRange
        view.allowsManualPageTurns = allowsManualPageTurns
        view.allowsVerseSelection = allowsVerseSelection
        view.canvas.hiddenTextAccessibilityHint = hiddenTextAccessibilityHint
        view.canvas.onVerse = onVerse; view.canvas.onFailure = onFailure; view.canvas.reduceMotion = reduceMotion
        view.onTurn = onTurn
        view.onToggleTools = onToggleTools
        if context.coordinator.page != page.number || context.coordinator.tajweed != tajweedEnabled || context.coordinator.style != view.traitCollection.userInterfaceStyle || !view.canvas.renderedSuccessfully {
            let animate = context.coordinator.page != nil && context.coordinator.page != page.number
                && !reduceMotion && !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
            context.coordinator.page = page.number
            context.coordinator.tajweed = tajweedEnabled
            context.coordinator.style = view.traitCollection.userInterfaceStyle
            let change = {
                view.canvas.tajweedEnabled = self.tajweedEnabled
                view.canvas.configure(page: self.page, corpus: self.corpus)
                view.canvas.selected = self.selected
                view.canvas.hiddenWordIDs = self.hiddenWordIDs
                view.canvas.reviewWordIDs = self.reviewWordIDs
                view.canvas.activeWordID = self.activeWordID
                view.resetToFittedPage()
                view.canvas.setNeedsDisplay(); view.canvas.layoutIfNeeded()
            }
            view.replacePage(number: page.number, animated: animate, change: change)
        }
        view.accessibilityIdentifier = view.canvas.renderedSuccessfully ? "reader.page.ready" : "reader.page.failed"
        view.accessibilityValue = view.canvas.renderedSuccessfully
            ? (view.canvas.tajweedEnabled ? "ألوان التجويد مفعّلة" : "القراءة العادية") : nil
        view.canvas.selected = selected
        view.canvas.hiddenWordIDs = hiddenWordIDs
        view.canvas.reviewWordIDs = reviewWordIDs
        view.canvas.activeWordID = activeWordID
    }
    final class Coordinator { var page: Int?; var tajweed: Bool?; var style: UIUserInterfaceStyle? }
    func makeCoordinator() -> Coordinator { Coordinator() }
}
