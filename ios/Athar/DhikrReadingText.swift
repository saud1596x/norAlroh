import SwiftUI

struct DhikrReadingText: View {
    let content: DhikrReadingContent
    @EnvironmentObject private var store: AtharStore
    @ScaledMetric(relativeTo: .title2) private var size = 26.0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(content.blocks) { block in
                switch block.kind {
                case .quran:
                    if let reference = block.quran,
                       let chapter = store.quran.first(where: { $0.number == reference.chapter }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(reference.title).font(.headline).foregroundStyle(Theme.gold)
                            ForEach(chapter.ayahs.filter { (reference.from...reference.to).contains($0.number) }) { ayah in
                                QuranVerseText(ayah.text, size: 28)
                                    .accessibilityIdentifier("dhikr.quran.\(reference.chapter).\(ayah.number)")
                            }
                            Text("\(chapter.name) · \(reference.from == reference.to ? "الآية \(reference.from)" : "الآيات \(reference.from)–\(reference.to)")")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.gold.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        sourceText(block.sourceText)
                    }
                case .basmala:
                    QuranVerseText(QuranText.basmala, size: 20)
                        .frame(maxWidth: .infinity).padding(.top, 6)
                case .instruction:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("ملاحظة", systemImage: "info.circle").font(.caption.bold()).foregroundStyle(Theme.gold)
                        Text(block.sourceText).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                case .invocation:
                    if block.sourceText.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
                        sourceText(block.sourceText)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func sourceText(_ text: String) -> some View {
        Text(verbatim: text).font(.custom("Amiri-Regular", fixedSize: size)).lineSpacing(7)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}
