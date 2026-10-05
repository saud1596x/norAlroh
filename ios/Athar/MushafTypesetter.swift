import UIKit
import CoreText

enum MushafTypesetter {
    // Short lines stay compact instead of spreading a few words across the screen.
    static func justificationWidth(advance: CGFloat, available: CGFloat) -> CGFloat {
        min(available, advance * 1.14)
    }
    struct Result {
        let line: CTLine
        let origin: CGPoint
        let inkBounds: CGRect
    }
    // Use the actual paths, including vowel/stop marks outside font ascent/descent.
    // A page's words and line breaks never change to make it fit the screen.
    static func make(text: String, fontName: String, size: CGFloat, bounds: CGRect, justify: Bool) -> Result? {
        guard !text.isEmpty, bounds.width > 12, bounds.height > 8 else { return nil }
        let available = bounds.insetBy(dx: 5, dy: 3)
        let direction = NSWritingDirection.rightToLeft.rawValue | NSWritingDirectionFormatType.override.rawValue
        var pointSize = size
        for _ in 0..<5 {
            guard let font = UIFont(name: fontName, size: pointSize) else { return nil }
            let string = NSMutableAttributedString(string: text, attributes: [.font: font,
                .foregroundColor: UIColor.label, .writingDirection: [direction]])
            // QCF V2 maps ayah glyphs but has no space glyph. Explicitly style
            // only U+0020 with licensed Amiri; never allow Quran glyph fallback.
            if fontName.hasPrefix("QCF2"), let spacing = UIFont(name: QuranTypography.postScriptName, size: pointSize) {
                for (index, unit) in text.utf16.enumerated() where unit == 0x20 {
                    string.addAttribute(.font, value: spacing, range: NSRange(location: index, length: 1))
                }
            }
            var line = CTLineCreateWithAttributedString(string as CFAttributedString)
            guard usesExpectedFont(line, postScriptName: font.fontName, text: text) else { return nil }
            var ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            guard ink.width > 0, ink.height > 0, ink.width.isFinite, ink.height.isFinite else { return nil }
            let scale = min(1, available.width / max(advance, ink.width), available.height / ink.height)
            if scale < 0.999 { pointSize *= scale * 0.995; continue }
            let overhang = max(0, ink.maxX - advance) + max(0, -ink.minX)
            let target = justificationWidth(advance: advance, available: max(0, available.width - overhang - 2))
            if justify, target > advance + 0.5, let justified = CTLineCreateJustifiedLine(line, 1, Double(target)) {
                let justifiedInk = CTLineGetBoundsWithOptions(justified, .useGlyphPathBounds)
                // Zero-advance Quran marks can extend beyond the justified advance.
                // Keep the already fitted line when expansion would clip its ink.
                if usesExpectedFont(justified, postScriptName: font.fontName, text: text),
                   justifiedInk.width <= available.width, justifiedInk.height <= available.height {
                    line = justified
                    ink = justifiedInk
                }
            }
            let finalScale = min(1, available.width / ink.width, available.height / ink.height)
            if finalScale < 0.999 { pointSize *= finalScale * 0.995; continue }
            let origin = CGPoint(x: justify ? available.maxX - ink.maxX : bounds.midX - ink.midX,
                                 y: bounds.midY - ink.midY)
            return Result(line: line, origin: origin, inkBounds: ink.offsetBy(dx: origin.x, dy: origin.y))
        }
        return nil
    }

    // PUA symbols drawn with a fallback font can silently become the wrong Quran glyph.
    static func usesExpectedFont(_ line: CTLine, postScriptName: String, text: String? = nil) -> Bool {
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName] else { return false }
            let font = value as! CTFont
            if CTFontCopyPostScriptName(font) as String != postScriptName {
                let range = CTRunGetStringRange(run)
                guard postScriptName.hasPrefix("QCF2"), CTFontCopyPostScriptName(font) as String == QuranTypography.postScriptName,
                      let text, range.location >= 0, range.length > 0,
                      range.location + range.length <= text.utf16.count,
                      (text as NSString).substring(with: NSRange(location: range.location, length: range.length)).unicodeScalars.allSatisfy({ $0.value == 0x20 }) else { return false }
            }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            if glyphs.contains(0) { return false }
        }
        return true
    }
}
