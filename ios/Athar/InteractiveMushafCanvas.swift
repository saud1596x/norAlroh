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
    static let pageSize = CGSize(width: 540, height: 930)
    struct Hit { let word: Int; let verse: String; let rect: CGRect }
    private(set) var regions: [Hit] = []
    private(set) var renderedSuccessfully = false
    private(set) var failureReason: String?
    private var lines: [(CTLine, CGPoint)] = []
    private var decorationPaths: [CGPath] = []
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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        accessibilityIdentifier = "reader.page.canvas"
        shouldGroupAccessibilityChildren = true
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func configure(page: OriginalPageData, corpus: [Surah]) {
        lines = []; regions = []; decorationPaths = []; renderedSuccessfully = false; failureReason = nil
        guard let body = UIFont(name: String(format: "QCF2%03d", page.number), size: 32),
              let companion = UIFont(name: OriginalMushafCompanion.name, size: 32) else { fail("Missing page or companion font"); return }
        // Original companion's 81-unit space is converted to the page font's
        // 2500-unit grid. This bridges authored units; it does not stretch letters.
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
            if row.type == "surah_name" {
                let originalFont = CTFontCreateWithName(OriginalMushafCompanion.name as CFString, 32, nil)
                var scalar: UniChar = 0xFC20; var glyph: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(originalFont, &scalar, &glyph, 1), glyph != 0,
                      let framePath = CTFontCreatePathForGlyph(originalFont, glyph, nil) else { fail("Missing original FC20 vector ornament"); return }
                let frameBox = framePath.boundingBoxOfPath
                let scale = min(532 / frameBox.width, 57 / frameBox.height)
                var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                    tx: 270 - frameBox.midX * scale,
                    ty: top + CGFloat(row.line - 1) * rowHeight + 30.5 + frameBox.midY * scale)
                guard let placed = framePath.copy(using: &transform) else { fail("Unable to position original ornament"); return }
                decorationPaths.append(placed)
            }
            let origin = CGPoint(x: row.centered ? 270 - ink.midX : 535 - ink.maxX, y: baseline)
            let pageInk = CGRect(x: origin.x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            guard pageInk.minX >= 0, pageInk.maxX <= Self.pageSize.width,
                  pageInk.minY >= 0, pageInk.maxY <= Self.pageSize.height else {
                fail("Authored row \(row.line) exceeds page canvas: \(pageInk)"); return
            }
            lines.append((line, origin))
            var wordRects: [Int: CGRect] = [:]
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let runFontValue = attributes[kCTFontAttributeName] else { fail("Missing Core Text run font"); return }
                let runFont = runFontValue as! CTFont
                let family = CTFontCopyPostScriptName(runFont) as String
                let stringRange = CTRunGetStringRange(run)
                let substring = (text as NSString).substring(with: NSRange(location: stringRange.location, length: stringRange.length))
                guard family == font.fontName || (!header && family == companion.fontName && substring.allSatisfy({ $0 == " " })) else { fail("Unexpected font \(family), row \(row.line)"); return }
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
                }
            }
            for (_, word) in ranges {
                guard let rect = wordRects[word.id], rect.minX >= 0, rect.maxX <= 540, rect.minY >= 0, rect.maxY <= Self.pageSize.height else { fail("Missing or clipped ink for word \(word.id), row \(row.line): \(String(describing: wordRects[word.id]))"); return }
                regions.append(Hit(word: word.id, verse: word.verse, rect: rect))
            }
        }
        // Authored FC20 ornament paths remain independent of title text.
        // Matching the target edition and distribution rights are review gates.
        renderedSuccessfully = true
        accessibilityElements = orderedKeys(page).compactMap { key -> UIAccessibilityElement? in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1) else { return nil }
            let element = MushafVerseAccessibility(accessibilityContainer: self)
            element.accessibilityIdentifier = "reader.verse.\(key)"
            element.accessibilityLabel = "\(corpus[parts[0] - 1].name)، الآية \(parts[1]). \(corpus[parts[0] - 1].ayahs[parts[1] - 1].text)"
            element.accessibilityTraits = .button
            element.accessibilityLanguage = "ar"
            element.action = { [weak self] in self?.onVerse?(key) }
            element.accessibilityFrameInContainerSpace = regions.first { $0.verse == key }?.rect ?? .zero
            return element
        }
        updateHighlight(); ink.setNeedsDisplay()
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
    func verse(at point: CGPoint) -> String? { regions.first { $0.rect.contains(point) }?.verse }
    @objc private func tapped(_ tap: UITapGestureRecognizer) { onVerse?(verse(at: tap.location(in: self))) }
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
        for (line, origin) in lines { context.textPosition = CGPoint(x: origin.x, y: bounds.height - origin.y); CTLineDraw(line, context) }
        context.restoreGState()
    }
}
@MainActor private final class OriginalMushafInk: UIView {
    weak var owner: OriginalMushafCanvas?
    override func draw(_ rect: CGRect) { owner?.drawInk() }
}
@MainActor private final class MushafVerseAccessibility: UIAccessibilityElement {
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
        accessibilityIdentifier = "reader.page.ready"
        contentSize = OriginalMushafCanvas.pageSize
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { canvas.redrawInk(atZoom: scale) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / 540, bounds.height / OriginalMushafCanvas.pageSize.height)
        if abs(fitted - fit) > 0.001 {
            fitted = fit; minimumZoomScale = fit; maximumZoomScale = fit * 4; zoomScale = fit
        }
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - canvas.frame.height) / 2), left: max(0, (bounds.width - canvas.frame.width) / 2), bottom: 0, right: 0)
    }
}
struct OriginalMushafDrawing: UIViewRepresentable {
    let page: OriginalPageData; let corpus: [Surah]; let selected: String?; let reduceMotion: Bool
    let onVerse: (String?) -> Void; let onFailure: () -> Void
    func makeUIView(context: Context) -> OriginalMushafViewport { OriginalMushafViewport() }
    func updateUIView(_ view: OriginalMushafViewport, context: Context) {
        view.canvas.onVerse = onVerse; view.canvas.onFailure = onFailure; view.canvas.reduceMotion = reduceMotion
        if context.coordinator.page != page.number || !view.canvas.renderedSuccessfully {
            context.coordinator.page = page.number
            view.canvas.configure(page: page, corpus: corpus)
            view.setZoomScale(view.minimumZoomScale, animated: false)
        }
        view.canvas.selected = selected
    }
    final class Coordinator { var page: Int? }
    func makeCoordinator() -> Coordinator { Coordinator() }
}
