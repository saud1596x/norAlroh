import SwiftUI

struct NoorRecitersView: View {
    @State private var search = ""
    @State private var favoritesOnly = false
    @AppStorage("noor.reciters.favorites") private var favorites = ""
    @AppStorage("noor.reciters.recent") private var recentReciter = 0
    private var favoriteIDs: Set<Int> {
        Set(favorites.split(separator: ",").compactMap { Int($0) })
    }
    private var filtered: [NoorReciter] {
        let query = ArabicSearch.normalize(search)
        return NoorReciterCatalog.reciters.filter(NoorSurahWordTimings.supports).filter {
            (!favoritesOnly || favoriteIDs.contains($0.id)) &&
            (query.isEmpty || ArabicSearch.normalize($0.name).contains(query))
        }.sorted { left, right in
            if left.id == recentReciter { return right.id != recentReciter }
            if right.id == recentReciter { return false }
            return left.id < right.id
        }
    }
    var body: some View {
        List {
            Section {
                Text("اختر القارئ ثم افتح السورة داخل المصحف مع تتبّع التلاوة.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("المفضلة فقط", isOn: $favoritesOnly)
            }.listRowBackground(Theme.panel)
            ForEach(filtered) { reciter in
                HStack {
                    NavigationLink {
                        NoorReciterSurahsView(reciter: reciter)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reciter.name).font(.headline)
                            Text("١١٤ سورة · توقيت كلمات بتغطية جزئية")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("reciter.\(reciter.id)")
                    Button {
                        var ids = favoriteIDs
                        if ids.contains(reciter.id) { ids.remove(reciter.id) }
                        else { ids.insert(reciter.id) }
                        favorites = ids.sorted().map(String.init).joined(separator: ",")
                    } label: {
                        Image(systemName: favoriteIDs.contains(reciter.id) ? "star.fill" : "star")
                            .frame(minWidth: 44, minHeight: 44).foregroundStyle(Theme.gold)
                    }.buttonStyle(.borderless)
                        .accessibilityLabel(favoriteIDs.contains(reciter.id) ? "إزالة \(reciter.name) من المفضلة" : "إضافة \(reciter.name) إلى المفضلة")
                }.listRowBackground(Theme.panel)
            }
            if filtered.isEmpty {
                if NoorReciterCatalog.reciters.filter(NoorSurahWordTimings.supports).isEmpty {
                    ContentUnavailableView("تعذّر تحميل مكتبة القراء", systemImage: "exclamationmark.triangle",
                        description: Text("بيانات المكتبة غير متاحة في هذه النسخة. أعد فتح التطبيق أو حدّثه إلى آخر نسخة."))
                } else {
                    ContentUnavailableView(favoritesOnly ? "لا يوجد قارئ مفضل مطابق" : "لا يوجد قارئ مطابق", systemImage: "magnifyingglass",
                        description: Text("غيّر البحث أو أظهر جميع القراء."))
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle("القرّاء مع التتبّع")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث باسم القارئ")
    }
}

private struct NoorReciterSurahsView: View {
    @EnvironmentObject private var store: AtharStore
    @AppStorage("noor.mushaf.reciter") private var preferredReciter = "Abdul_Basit_Murattal_64kbps"
    let reciter: NoorReciter
    @State private var search = ""
    @State private var readerSurah: Surah?
    private var surahs: [Surah] {
        let query = ArabicSearch.normalize(search)
        return store.quran.filter {
            reciter.surahs.contains($0.number) && (query.isEmpty ||
                ArabicSearch.normalize($0.name).contains(query) || ArabicSearch.integer(search) == $0.number)
        }
    }
    private func open(_ surah: Surah) {
        let identity = "surah:\(reciter.id):\(reciter.recordingID)"
        guard NoorMushafReciter.selected(identity) != nil else { return }
        preferredReciter = identity
        readerSurah = surah
    }
    var body: some View {
        List {
            Section {
                Text("يُفتح المصحف بالقارئ المختار. ابدأ الاستماع من أدوات الآية.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("توقيت الكلمات غير مكتمل لبعض الآيات.")
                    .font(.caption).foregroundStyle(.secondary)
                if let first = store.quran.first(where: { $0.number == 1 }) {
                    Button { open(first) } label: {
                        Label("افتح المصحف من الفاتحة", systemImage: "book")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("reciter.openMushaf")
                }
            }.listRowBackground(Theme.panel)
            ForEach(surahs) { surah in
                Button { open(surah) } label: {
                    HStack(spacing: 14) {
                        Text("\(surah.number)").monospacedDigit().foregroundStyle(Theme.gold)
                            .frame(minWidth: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(surah.name).font(.headline)
                            Text("\(surah.ayahs.count) آية").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "book")
                    }.padding(.vertical, 8).frame(minHeight: 48)
                }.buttonStyle(.plain).listRowBackground(Theme.panel)
                    .accessibilityIdentifier("reciter.surah.\(surah.number)")
                    .accessibilityLabel("\(surah.name)، \(reciter.name)، افتح داخل المصحف")
            }
            if surahs.isEmpty {
                ContentUnavailableView("لا توجد سورة مطابقة", systemImage: "magnifyingglass")
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle(reciter.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث في السور")
        .fullScreenCover(item: $readerSurah) { surah in
            InteractiveMushafReader(chapter: surah.number, ayah: 1, initialPage: nil)
        }
        .onAppear { UserDefaults.standard.set(reciter.id, forKey: "noor.reciters.recent") }
    }
}
