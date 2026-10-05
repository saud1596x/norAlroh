import SwiftUI

enum NoorDailyVerse {
    struct Reference { let chapter: Surah; let ayah: Ayah }
    static func select(corpus: [Surah], date: Date) -> Reference? {
        let count = corpus.reduce(0) { $0 + $1.ayahs.count }
        guard count > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let civilDay = utc.date(from: components) else { return nil }
        // Convert the Saudi civil date explicitly; day-in-era may ignore timezone boundaries.
        let day = Int(floor(civilDay.timeIntervalSince1970 / 86400)) + 719163
        var index = (day % count + count) % count
        for chapter in corpus {
            if index < chapter.ayahs.count { return Reference(chapter: chapter, ayah: chapter.ayahs[index]) }
            index -= chapter.ayahs.count
        }
        return nil
    }
}

struct NoorReflectionView: View {
    @EnvironmentObject private var store: AtharStore
    let reference: NoorDailyVerse.Reference
    @State private var note = ""
    @State private var saved = false
    private var key: String { "\(reference.chapter.number):\(reference.ayah.number)" }
    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("اقرأ على مهل", systemImage: "book.pages").font(.subheadline).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 12) {
                    Text(reference.chapter.name).font(.title2.bold())
                    Text("الآية \(reference.ayah.number)").font(.caption).foregroundStyle(.secondary)
                    QuranVerseText(reference.ayah.text, size: store.data.largeQuran ? 34 : 28)
                    HStack {
                        NavigationLink { MushafReader(chapter: reference.chapter.number, ayah: reference.ayah.number) } label: {
                            Label("افتح في المصحف", systemImage: "book").frame(minHeight: 44)
                        }
                        Spacer()
                        Button { store.toggleBookmark(surah: reference.chapter.number, ayah: reference.ayah.number) } label: {
                            Image(systemName: store.data.bookmarks.contains(key) ? "bookmark.fill" : "bookmark")
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel(store.data.bookmarks.contains(key) ? "إزالة العلامة" : "حفظ علامة")
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
                Card {
                    Text("ما الذي تريد تذكّره؟").font(.headline)
                    Text("اكتب تأمّلك الشخصي. يُحفظ في دفتر التأمل على جهازك.").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $note).frame(minHeight: 140).scrollContentBackground(.hidden)
                        .accessibilityLabel("تأمل شخصي").accessibilityIdentifier("reflection.note")
                        .onChange(of: note) { _, value in if value.count > 5000 { note = String(value.prefix(5000)) } }
                    PrimaryButton(title: "احفظ تأملي", icon: "square.and.pencil") {
                        let text = "تأمل شخصي — \(reference.chapter.name)، الآية \(reference.ayah.number)\n\(trimmed)"
                        if !trimmed.isEmpty && store.update({ $0.notes.insert(JournalNote(text: text), at: 0) }) { note = ""; saved = true }
                    }.disabled(trimmed.isEmpty).accessibilityIdentifier("reflection.save")
                    NavigationLink("دفتر تأملاتي") { LibraryView() }.frame(minHeight: 44)
                }
                Text("المصدر: Tanzil، النص العثماني 1.1. اختيار الآية يتغيّر يوميًا بالتوقيت السعودي. التأملات كتابات شخصية وليست تفسيرًا.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Theme.background).navigationTitle("وقفة مع آية")
            .accessibilityIdentifier("reflection.screen")
            .sensoryFeedback(.success, trigger: saved)
            .alert("حُفظ تأملك على جهازك", isPresented: $saved) { Button("تم", role: .cancel) {} }
    }
}
