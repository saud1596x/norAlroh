import SwiftUI

/// Training reuses the reading renderer and its stable Content Sync word IDs.
/// Hidden glyphs retain all shaped positions; no Unicode text is reflowed.
struct MushafTrainingPage: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @StateObject private var fonts = MushafFonts()
    let chapter: Int
    let ayah: Int
    let revealedWords: Int
    let revealAll: Bool
    var onHint: () -> Void = {}
    var onWordCount: (Int) -> Void = { _ in }
    @State private var snapshot: QCFV2Snapshot?
    @State private var rows: OriginalMushafRows?
    @State private var number = 1
    @State private var error: String?
    @State private var failed = false
    private var key: String { "\(chapter):\(ayah)" }
    private var keys: [String] { store.quran.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } } }
    private var verseID: Int? { keys.firstIndex(of: key).map { $0 + 1 } }
    private var verseWords: [QCFV2Snapshot.Record] {
        guard let snapshot, let verseID else { return [] }
        return snapshot.records.filter { $0.record_type == "mushaf_word" && $0.verse_id == verseID }
            .sorted { a, b in
                a.page_number == b.page_number ? a.position_in_page! < b.position_in_page! : a.page_number! < b.page_number!
            }
    }
    private var pages: [Int] { Array(Set(verseWords.compactMap(\.page_number))).sorted() }
    private var hidden: Set<Int> { revealAll ? [] : Set(verseWords.dropFirst(max(0, revealedWords)).map(\.id)) }
    private var page: OriginalPageData? {
        guard let snapshot, let rows else { return nil }
        return .page(number, snapshot: snapshot, rows: rows, keys: keys)
    }
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let page, fonts.names[String(format: "QCF2%03d", number)] != nil, !failed {
                    OriginalMushafDrawing(page: page, corpus: store.quran, selected: key,
                        reduceMotion: reduced || store.data.lowMotion, hiddenWordIDs: hidden,
                        onVerse: { tapped in if tapped == key && !hidden.isEmpty { onHint() } },
                        onFailure: { DispatchQueue.main.async { failed = true } })
                } else if let message = error ?? fonts.error {
                    VStack(spacing: 12) { Text(message); Button("إعادة المحاولة") { Task { await load() } } }.padding()
                } else if failed {
                    ContentUnavailableView("تعذّر فتح صفحة التدريب", systemImage: "book.closed", description: Text("أعد فتح التدريب أو تواصل مع الدعم مع رقم الصفحة."))
                } else { ProgressView("تجهيز صفحة المصحف…") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button { if let next = pages.first(where: { $0 > number }) { number = next } } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.disabled(pages.last == number || pages.isEmpty).accessibilityLabel("تكملة الآية في الصفحة التالية")
                Spacer()
                Text("الصفحة \(ArabicSearch.digits(number)) من ٦٠٤").font(.caption).accessibilityIdentifier("hifz.mushafPage")
                Spacer()
                Button { if let previous = pages.last(where: { $0 < number }) { number = previous } } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.disabled(pages.first == number || pages.isEmpty).accessibilityLabel("بداية الآية في الصفحة السابقة")
            }
        }.padding(.horizontal, 5)
            .task(id: key) { await load() }
            .task(id: number) { failed = false; await fonts.load(String(format: "QCF2%03d", number)) }
    }
    private func load() async {
        error = nil; failed = false
        do {
            try OriginalMushafCompanion.register()
            if snapshot == nil {
                let metadata = try OriginalMushafRows.load()
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let cache = QCFV2ContentCache(file: directory.appendingPathComponent("qcf-v2-cache.json"), endpoint: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
                let entry: QCFV2ContentCache.Entry
                if let saved = await cache.cached() { entry = saved } else { entry = try await cache.refresh() }
                let value = try JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot).validated()
                try metadata.validate(value)
                try Task.checkCancellation()
                snapshot = value; rows = metadata
            }
            try Task.checkCancellation()
            guard let first = pages.first else { throw QCFV2Snapshot.Invalid.page }
            onWordCount(verseWords.count)
            number = first
            await fonts.load(String(format: "QCF2%03d", first))
        } catch is CancellationError { }
        catch { self.error = "تعذّر تجهيز المصحف. اتصل بالإنترنت عند أول فتح، ثم تتاح الصفحات دون اتصال." }
    }
}
