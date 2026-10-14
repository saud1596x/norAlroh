import SwiftUI

struct NoorRecitersView: View {
    @State private var search = ""
    @State private var favoritesOnly = false
    @AppStorage("noor.reciters.favorites") private var favorites = ""
    private var favoriteIDs: Set<Int> {
        Set(favorites.split(separator: ",").compactMap { Int($0) })
    }
    private var filtered: [NoorReciter] {
        let query = ArabicSearch.normalize(search)
        return NoorReciterCatalog.reciters.filter {
            (!favoritesOnly || favoriteIDs.contains($0.id)) &&
            (query.isEmpty || ArabicSearch.normalize($0.name).contains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Text("مصاحف كاملة لأئمة الحرمين الحاليين والسابقين برواية حفص. تضم كل قائمة السور الـ١١٤.")
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
                            Text("المصحف كامل · ١١٤ سورة")
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
                ContentUnavailableView("لا يوجد قارئ مطابق", systemImage: "magnifyingglass",
                    description: Text("غيّر البحث أو أظهر جميع القراء."))
            }
            Section {
                Link("مصدر التلاوات: MP3Quran", destination: NoorReciterCatalog.source)
            }.listRowBackground(Theme.panel)
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle("أئمة الحرمين")
        .searchable(text: $search, prompt: "ابحث باسم القارئ")
    }
}

private struct NoorReciterSurahsView: View {
    @EnvironmentObject private var store: AtharStore
    let reciter: NoorReciter
    @StateObject private var audio: MushafVerseAudio
    @State private var search = ""
    init(reciter: NoorReciter) {
        self.reciter = reciter
        _audio = StateObject(wrappedValue: MushafVerseAudio(source: { key in
            guard let number = Int(key), key == String(number) else { return nil }
            return reciter.audioURL(surah: number)
        }))
    }
    private var surahs: [Surah] {
        let query = ArabicSearch.normalize(search)
        return store.quran.filter {
            reciter.surahs.contains($0.number) && (query.isEmpty ||
                ArabicSearch.normalize($0.name).contains(query) || ArabicSearch.integer(search) == $0.number)
        }
    }
    var body: some View {
        List {
            Section {
                Text("حفص عن عاصم · تلاوة السورة كاملة")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    audio.play((1...114).map(String.init))
                } label: {
                    Label("تشغيل المصحف من الفاتحة", systemImage: "play.circle.fill")
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("reciter.playCompleteQuran")
                if audio.playing != nil || audio.loadingKey != nil || audio.waitingKey != nil {
                    Button { audio.stop() } label: {
                        Label("إيقاف التلاوة", systemImage: "stop.circle")
                            .frame(minHeight: 44)
                    }
                }
                if let error = audio.error {
                    Text(error).foregroundStyle(.red).accessibilityLabel("خطأ التشغيل: \(error)")
                }
            }.listRowBackground(Theme.panel)
            ForEach(surahs) { surah in
                let key = String(surah.number)
                Button {
                    if audio.playing == key || audio.loadingKey == key { audio.stop() }
                    else { audio.play([key]) }
                } label: {
                    HStack(spacing: 14) {
                        Text("\(surah.number)").monospacedDigit().foregroundStyle(Theme.gold)
                            .frame(minWidth: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(surah.name).font(.headline)
                            Text(audio.loadingKey == key ? "جارٍ تحميل التلاوة…" : "\(surah.ayahs.count) آية")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if audio.loadingKey == key { ProgressView() }
                        else { Image(systemName: audio.playing == key ? "stop.fill" : "play.fill") }
                    }.padding(.vertical, 8).frame(minHeight: 48)
                }.buttonStyle(.plain).listRowBackground(Theme.panel)
                    .accessibilityIdentifier("reciter.surah.\(surah.number)")
                    .accessibilityLabel("\(surah.name)، \(reciter.name)، \(audio.playing == key ? "إيقاف" : "تشغيل")")
            }
            if surahs.isEmpty {
                ContentUnavailableView("لا توجد سورة مطابقة", systemImage: "magnifyingglass")
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle(reciter.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "ابحث في السور المتاحة")
        .onDisappear { audio.stop() }
    }
}
