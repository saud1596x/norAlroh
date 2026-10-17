import UIKit
import CoreText
import CryptoKit

/// Original glyph layers and original light/dark CPAL palettes, not rules
/// guessed from words. No changes to canonical IDs, Quran text or font bytes.
@MainActor enum MushafTajweedFonts {
    struct Entry: Decodable {
        let page: Int; let file: String; let postScriptName: String
        let bytes: Int; let sha256: String; let layersSha256: String
    }
    private struct Manifest: Decodable { let fonts: [Entry] }
    struct Page: Decodable {
        let schema: Int; let palettes: [[[Int]]]; let layers: [String: [[Int]]]
        var family = ""
        private enum CodingKeys: String, CodingKey { case schema, palettes, layers }
        func paths(glyph: CGGlyph, font: CTFont, dark: Bool) -> [(CGPath, UIColor)] {
            guard let parts = layers[String(glyph)] else {
                return CTFontCreatePathForGlyph(font, glyph, nil).map { [($0, UIColor.label)] } ?? []
            }
            return parts.compactMap { part in
                guard part.count == 2, let shape = CTFontCreatePathForGlyph(font, CGGlyph(part[0]), nil) else { return nil }
                let color: UIColor
                if part[1] == 65535 { color = .label }
                else {
                    let light = palettes[0][part[1]], dark = palettes[1][part[1]]
                    color = UIColor { traits in
                        let c = traits.userInterfaceStyle == .dark ? dark : light
                        return UIColor(red: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255,
                                       blue: CGFloat(c[2]) / 255, alpha: CGFloat(c[3]) / 255)
                    }
                }
                return (shape, color)
            }
        }
    }
    private static var entries: [Entry]?
    private static var registered = Set<Int>()
    private static var cached: [(Int, Page)] = []
    static func load(_ page: Int) throws -> Page {
        if let value = cached.first(where: { $0.0 == page }) { return value.1 }
        if entries == nil {
            guard let url = Bundle.main.url(forResource: "qcf-v4-manifest", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            guard manifest.fonts.map(\.page) == Array(1...604) else { throw CocoaError(.fileReadCorruptFile) }
            entries = manifest.fonts
        }
        guard (1...604).contains(page), let e = entries?.first(where: { $0.page == page }),
              let fontURL = Bundle.main.url(forResource: "t4-p\(page)", withExtension: "ttf"),
              let layerURL = Bundle.main.url(forResource: "t4-p\(page)", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let bytes = try Data(contentsOf: fontURL), data = try Data(contentsOf: layerURL)
        func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
        guard bytes.count == e.bytes, sha(bytes) == e.sha256, sha(data) == e.layersSha256,
              let provider = CGDataProvider(data: bytes as CFData), let font = CGFont(provider),
              let postScriptName = font.postScriptName, postScriptName as String == e.postScriptName else { throw CocoaError(.fileReadCorruptFile) }
        if registered.insert(page).inserted { CTFontManagerRegisterGraphicsFont(font, nil) }
        guard UIFont(name: e.postScriptName, size: 23) != nil else { throw CocoaError(.fileReadCorruptFile) }
        var value = try JSONDecoder().decode(Page.self, from: data); value.family = e.postScriptName
        guard value.schema == 1, value.palettes.count == 2,
              value.palettes.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.count == 4 && $0.allSatisfy({ (0...255).contains($0) }) }) }),
              value.layers.values.allSatisfy({ parts in
                  !parts.isEmpty && parts.allSatisfy { part in
                      part.count == 2 && (0...65535).contains(part[0]) &&
                        (part[1] == 65535 || value.palettes.allSatisfy { $0.indices.contains(part[1]) })
                  }
              })
        else { throw CocoaError(.fileReadCorruptFile) }
        cached.append((page, value)); if cached.count > 3 { cached.removeFirst() }
        return value
    }
}
