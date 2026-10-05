import SwiftUI
import UIKit
import CoreText

@MainActor enum QuranTypography {
    static let postScriptName = "Amiri-Regular"
    static let available: Bool = {
        guard let url = Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf"),
              let bytes = try? Data(contentsOf: url),
              QuranResources.verified(bytes, resource: "AmiriQuran.ttf"),
              let font = UIFont(name: postScriptName, size: 28), let corpus = QuranResources.corpus else { return false }
        let characters = Array(Set(corpus.flatMap { $0.ayahs.flatMap { Array($0.text.utf16) } })).sorted()
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let coreFont = CTFontCreateWithName(font.fontName as CFString, 28, nil)
        return CTFontGetGlyphsForCharacters(coreFont, characters, &glyphs, characters.count) && !glyphs.contains(0)
    }()
}

/// Quran strings are never shaped with the UI font, clipped to a fixed line count, or animated as characters.
struct QuranVerseText: View {
    let text: String
@ScaledMetric(relativeTo: .title) private var size: CGFloat = 28
    init(_ text: String, size: CGFloat = 28) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }
    var body: some View {
        Group {
            if QuranTypography.available {
                Text(text).font(.custom(QuranTypography.postScriptName, fixedSize: size))
                    .foregroundStyle(.primary).lineSpacing(size * 0.22)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, size * 0.10)
                    .environment(\.layoutDirection, .rightToLeft)
                    .accessibilityLabel(text)
            } else {
                Text("تعذّر تحميل الخط القرآني الموثوق. أعد تثبيت نسخة موثوقة من التطبيق.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}
