import SwiftUI
import UIKit

/// Activated only for a complete, approved artwork package. Navigation and
/// selection use this package's verse keys, never another edition's line data.
struct MushafArtworkReader: View {
    @EnvironmentObject var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    let library: MushafArtworkLibrary
    let startingChapter: Int
    let startingAyah: Int
    let startingPage: Int?
    @State private var number = 1
    @State private var artwork: MushafArtworkLibrary.Artwork?
    @State private var failed = false
    @State private var toolsVisible = true
    @State private var selected: String?
    @State private var selectionPresented = false
    @State private var picker = false
    @State private var input = "1"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.panel
                if let artwork {
                    MushafArtworkView(artwork: artwork, corpus: store.quran, selected: selected,
                        onSelect: { selected = $0; selectionPresented = true },
                        onToggleTools: { toolsVisible.toggle() })
                        // These reserved margins never change when tools hide.
                        .padding(.horizontal, 12).padding(.vertical, 60)
                        .accessibilityIdentifier("reader.artwork.page.ready")
                } else if failed {
                    ContentUnavailableView("تعذّر عرض الصفحة الأصلية", systemImage: "doc",
                        description: Text("لم تُستبدل الصفحة بخط أو رسم بديل."))
                } else { ProgressView("فتح صفحة المصحف…") }
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("العودة")
                        Spacer()
                        Text("المصحف").font(.headline)
                        Spacer()
                        Button { input = String(number); picker = true } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                            .accessibilityLabel("الانتقال إلى صفحة")
                    }
                    Spacer()
                    HStack {
                        Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(number == 604).accessibilityLabel("الصفحة التالية")
                        Spacer()
                        Button("\(number) / 604") { input = String(number); picker = true }.frame(minHeight: 44)
                        Spacer()
                        Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .disabled(number == 1).accessibilityLabel("الصفحة السابقة")
                    }
                }.padding(.horizontal, 12).padding(.vertical, 6)
                    .opacity(toolsVisible ? 1 : 0)
                    .allowsHitTesting(toolsVisible).accessibilityHidden(!toolsVisible)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .task {
            let key = "\(startingChapter):\(startingAyah)"
            number = startingPage.flatMap { (1...604).contains($0) ? $0 : nil }
                ?? library.manifest.pages.first(where: { $0.regions.contains(where: { $0.verseKey == key }) })?.number ?? 1
            load()
        }
        .onChange(of: number) { _, _ in load() }
        .sheet(isPresented: $picker) {
            NavigationStack {
                Form {
                    TextField("١ إلى ٦٠٤", text: $input).keyboardType(.numberPad)
                    Button("انتقل") {
                        if let page = ArabicSearch.integer(input), (1...604).contains(page) { number = page; picker = false }
                    }.disabled(!(ArabicSearch.integer(input).map { (1...604).contains($0) } ?? false))
                }.navigationTitle("الانتقال في المصحف")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { picker = false } } }
            }
        }
        .confirmationDialog("خيارات الآية", isPresented: $selectionPresented) {
            if let selected, let pair = verse(selected) {
                Button(store.data.bookmarks.contains(selected) ? "إزالة العلامة" : "حفظ علامة") {
                    store.toggleBookmark(surah: pair.0, ayah: pair.1)
                }
                Button("نسخ الآية") {
                    UIPasteboard.general.string = QuranText.verse(chapter: pair.0, ayah: store.quran[pair.0 - 1].ayahs[pair.1 - 1])
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
    private func load() {
        selected = nil; failed = false
        do { artwork = try library.artwork(number: number); lastPage = number }
        catch { artwork = nil; failed = true }
    }
    private func turn(_ delta: Int) {
        let next = number + delta
        if (1...604).contains(next) { number = next }
    }
    private func verse(_ key: String) -> (Int, Int)? {
        let values = key.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2, store.quran.indices.contains(values[0] - 1), store.quran[values[0] - 1].ayahs.indices.contains(values[1] - 1) else { return nil }
        return (values[0], values[1])
    }
}
