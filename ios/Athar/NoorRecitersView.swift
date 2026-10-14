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
        return NoorReciterCatalog.reciters.filter {
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
                if NoorReciterCatalog.reciters.isEmpty {
                    ContentUnavailableView("تعذّر تحميل مكتبة القراء", systemImage: "exclamationmark.triangle",
                        description: Text("بيانات المكتبة غير متاحة في هذه النسخة. أعد فتح التطبيق أو حدّثه إلى آخر نسخة."))
                } else {
                    ContentUnavailableView(favoritesOnly ? "لا يوجد قارئ مفضل مطابق" : "لا يوجد قارئ مطابق", systemImage: "magnifyingglass",
                        description: Text("غيّر البحث أو أظهر جميع القراء."))
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle("أئمة الحرمين")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث باسم القارئ")
    }
}

private struct NoorReciterSurahsView: View {
    @EnvironmentObject private var store: AtharStore
    let reciter: NoorReciter
    @StateObject private var audio: MushafVerseAudio
    @ObservedObject private var downloads = NoorAudioDownloads.shared
    @State private var downloadSurah: Int?
    @State private var downloadAll = false
    @State private var search = ""
    init(reciter: NoorReciter) {
        self.reciter = reciter
        _audio = StateObject(wrappedValue: MushafVerseAudio(source: { key in
            guard let number = Int(key), key == String(number) else { return nil }
            return reciter.audioURL(surah: number)
        }, cacheKey: { key in
            guard let number = Int(key) else { return nil }
            return NoorAudioIntegrity.reciterKey(reciter, surah: number)
        }, recordingIdentity: "mp3quran:\(reciter.recordingID):\(reciter.server)", displayName: reciter.name, keepAlive: true))
    }
    private var surahs: [Surah] {
        let query = ArabicSearch.normalize(search)
        return store.quran.filter {
            reciter.surahs.contains($0.number) && (query.isEmpty ||
                ArabicSearch.normalize($0.name).contains(query) || ArabicSearch.integer(search) == $0.number)
        }
    }
    private var activeSurah: Surah? {
        guard let key = audio.playing ?? audio.loadingKey ?? audio.waitingKey,
              let number = Int(key) else { return nil }
        return store.quran.first { $0.number == number }
    }
    var body: some View {
        List {
            Section {
                NavigationLink("التنزيلات المحفوظة وإدارة المساحة") { NoorAudioDownloadsView() }
                Button("تنزيل المصحف كاملًا لهذا القارئ", systemImage: "arrow.down.circle") { downloadAll = true }
                    .disabled(downloads.active != nil).frame(minHeight: 44)
                if let message = downloads.message { Text(message).font(.caption) }
                if downloads.active != nil { ProgressView("تنزيل التلاوة…") }
                Text("حفص عن عاصم · تلاوة السورة كاملة")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    audio.play((1...114).map(String.init))
                } label: {
                    Label("تشغيل المصحف من الفاتحة", systemImage: "play.circle.fill")
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("reciter.playCompleteQuran")
                Button("استأنف موضع الاستماع المحفوظ") {
                    if !audio.restoreBookmark() {
                        let position = UserDefaults.standard.integer(forKey: "noor.reciters.canonicalSurah")
                        audio.play([String((1...114).contains(position) ? position : 1)])
                    }
                }
                    .frame(minHeight: 44)
                if audio.playing != nil || audio.loadingKey != nil || audio.waitingKey != nil {
                    if audio.playing != nil {
                        HStack {
                            Button(audio.isPaused ? "استئناف" : "إيقاف مؤقت") {
                                if audio.isPaused { audio.resumePlayback() } else { audio.pausePlayback() }
                            }.frame(minHeight: 44)
                            Button("احفظ موضع الاستماع") { audio.saveBookmark() }.frame(minHeight: 44)
                        }
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            if audio.durationSeconds > 0 {
                                Slider(value: Binding(get: { audio.currentSeconds }, set: { audio.seek(to: $0) }), in: 0...audio.durationSeconds)
                                    .accessibilityLabel("موضع الاستماع داخل السورة")
                            }
                        }
                        Picker("سرعة التلاوة", selection: Binding(get: { audio.playbackRate }, set: { _ = audio.setPlaybackRate($0) })) {
                            Text("٠٫٧٥").tag(Float(0.75)); Text("عادية").tag(Float(1)); Text("١٫٢٥").tag(Float(1.25))
                        }.pickerStyle(.segmented)
                        Menu("مؤقت النوم") {
                            Button("٥ دقائق · عند نهاية المقطع") { _ = audio.setSleepTimer(minutes: 5) }
                            Button("١٥ دقيقة · عند نهاية المقطع") { _ = audio.setSleepTimer(minutes: 15) }
                            Button("٣٠ دقيقة · عند نهاية المقطع") { _ = audio.setSleepTimer(minutes: 30) }
                        }.frame(minHeight: 44)
                        if let status = audio.sleepStatus { Text(status).font(.caption) }
                    }
                    if let current = activeSurah {
                        Label("\(audio.playing != nil ? "تُتلى الآن" : "جارٍ تحميل") · \(current.name)",
                              systemImage: audio.playing != nil ? "speaker.wave.2.fill" : "arrow.down.circle")
                            .font(.subheadline).foregroundStyle(Theme.gold)
                            .accessibilityIdentifier("reciter.currentSurah")
                    }
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
                    .contextMenu {
                        Button("تنزيل السورة دون إنترنت", systemImage: "arrow.down.circle") { downloadSurah = surah.number }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("تنزيل", systemImage: "arrow.down.circle") { downloadSurah = surah.number }.tint(Theme.gold)
                    }
                    .accessibilityAction(named: "تنزيل السورة دون إنترنت") { downloadSurah = surah.number }
                    .accessibilityIdentifier("reciter.surah.\(surah.number)")
                    .accessibilityLabel("\(surah.name)، \(reciter.name)، \(audio.playing == key || audio.loadingKey == key ? "إيقاف" : "تشغيل")")
            }
            if surahs.isEmpty {
                ContentUnavailableView("لا توجد سورة مطابقة", systemImage: "magnifyingglass")
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .noorScreenChrome().navigationTitle(reciter.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث في السور المتاحة")
        .confirmationDialog(downloadAll ? "تنزيل ١١٤ سورة لهذا القارئ؟" : "تنزيل السورة لهذا القارئ؟ قد يستخدم بيانات الجوال.", isPresented: Binding(get: { downloadSurah != nil || downloadAll }, set: { if !$0 { downloadSurah = nil; downloadAll = false } }), titleVisibility: .visible) {
            if downloadAll {
                Button("تنزيل المصحف") {
                    downloads.download(reciter.surahs.sorted().compactMap { NoorAudioIntegrity.reciterKey(reciter, surah: $0) })
                    downloadAll = false
                }
                Button("إلغاء", role: .cancel) { downloadAll = false }
            } else if let number = downloadSurah, let key = NoorAudioIntegrity.reciterKey(reciter, surah: number) {
                Button("تنزيل") { downloads.download([key]); downloadSurah = nil }
                Button("إلغاء", role: .cancel) { downloadSurah = nil }
            }
        }
        .onAppear {
            UserDefaults.standard.set(reciter.id, forKey: "noor.reciters.recent")
            audio.onVerse = { key in
                if let number = Int(key), (1...114).contains(number) { UserDefaults.standard.set(number, forKey: "noor.reciters.canonicalSurah") }
            }
        }
    }
}
