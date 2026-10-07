import SwiftUI
import UIKit
import AVFoundation

@MainActor final class MushafVerseAudio: ObservableObject {
    @Published var playing: String?
    @Published var error: String?
    @Published var loadingKey: String?
    private var playbackObservation: NSKeyValueObservation?
    private var player: AVPlayer?
    private var observation: NSKeyValueObservation?
    private var end: NSObjectProtocol?
    private var failure: NSObjectProtocol?
    private var queue: [String] = []
    var onVerse: ((String) -> Void)?
    func play(_ keys: [String]) {
        stop(); queue = keys; advance()
    }
    private func advance() {
        guard !queue.isEmpty else { stop(); return }
        let key = queue.removeFirst(); let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let corpus = QuranResources.corpus,
              corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1),
              let url = URL(string: String(format: "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/%03d%03d.mp3", parts[0], parts[1])) else { stop(); return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback); try AVAudioSession.sharedInstance().setActive(true) }
        catch { self.error = "تعذّر تشغيل الصوت على الجهاز."; stop(); return }
        let item = AVPlayerItem(url: NoorAudioDownloads.shared.localURL(key) ?? url); let playback = AVPlayer(playerItem: item); player = playback
        playing = nil; loadingKey = key
        playbackObservation = playback.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let started = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self, self.player === player else { return }
                if started { self.playing = key; self.loadingKey = nil; self.onVerse?(key) }
            }
        }
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.error = "تعذّر تشغيل الآية. أعد تنزيلها من التنزيلات، أو تحقق من اتصال الإنترنت."; self?.stop() }
        }
        if let end { NotificationCenter.default.removeObserver(end) }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in self?.advance() } }
        if let failure { NotificationCenter.default.removeObserver(failure) }
        failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.error = "انقطع تحميل التلاوة. تحقق من الاتصال وأعد المحاولة."; self?.stop() }
        }
        error = nil; player?.play()
    }
    func stop() { player?.pause(); player = nil; observation = nil; playbackObservation = nil; playing = nil; loadingKey = nil; queue = [] }
    deinit { if let end { NotificationCenter.default.removeObserver(end) }; if let failure { NotificationCenter.default.removeObserver(failure) } }
}

@MainActor final class MushafTafsir: ObservableObject {
    struct Envelope: Decodable { let result: Result }
    struct Result: Codable { let sura: String; let aya: String; let translation: String }
    struct Cached: Codable { let date: Date; let value: Result }
    @Published var text: String?
    @Published var error: String?
    private var request: UUID?
    func load(chapter: Int, ayah: Int) async {
        let token = UUID(); request = token; text = nil; error = nil
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("mushaf-tafsir", isDirectory: true)
        let file = directory.appendingPathComponent("\(chapter)-\(ayah).json")
        func valid(_ value: Result) -> Bool { Int(value.sura) == chapter && Int(value.aya) == ayah && !value.translation.isEmpty && value.translation.utf8.count < 100_000 }
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        if let saved, valid(saved.value), Date().timeIntervalSince(saved.date) < 604800 { text = saved.value.translation; return }
        do {
            let url = URL(string: "https://quranenc.com/api/v1/translation/aya/arabic_moyassar/\(chapter)/\(ayah)")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 25))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 200_000 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(Envelope.self, from: data).result
            guard valid(value) else { throw URLError(.cannotParseResponse) }
            guard request == token else { return }
            text = value.translation
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Cached(date: Date(), value: value)).write(to: file, options: .atomic)
        } catch {
            guard request == token else { return }
            if let saved, valid(saved.value) { text = saved.value.translation }
            else { self.error = "تعذّر تنزيل التفسير. اتصل بالإنترنت وحاول مرة أخرى؛ يُحفظ التفسير بعد فتحه للقراءة دون اتصال." }
        }
    }
}

struct InteractiveMushafReader: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @StateObject private var fonts = MushafFonts()
    @StateObject private var audio = MushafVerseAudio()
    let chapter: Int; let ayah: Int; let initialPage: Int?
    @State private var snapshot: QCFV2Snapshot?
    @State private var rows: OriginalMushafRows?
    @State private var number = 1
    @State private var selected: String?
    @State private var sheetVerse: VerseSelection?
    @State private var tools = true
    @State private var controlHeights: [String: CGFloat] = [:]
    @State private var khatmah = false
    @State private var picker = false
    @State private var input = ""
    @State private var error: String?
    @State private var renderingFailed = false
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    private var keys: [String] { store.quran.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } } }
    private var page: OriginalPageData? {
        guard let snapshot, let rows else { return nil }
        return OriginalPageData.page(number, snapshot: snapshot, rows: rows, keys: keys)
    }
    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            GeometryReader { geometry in
                if let page, fonts.names[String(format: "QCF2%03d", number)] != nil, !renderingFailed {
                    OriginalMushafDrawing(page: page, corpus: store.quran, selected: selected, reduceMotion: reduced || store.data.lowMotion,
                        onVerse: { key in
                            if let key { selected = key; sheetVerse = VerseSelection(key: key) }
                            else { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { tools.toggle() } }
                        }, onFailure: { DispatchQueue.main.async { renderingFailed = true } }, onTurn: { turn($0) },
                        onToggleTools: { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.2)) { tools.toggle() } })
                        // Retain the measured toolbar lanes even when chrome is hidden.
                        // GeometryReader already excludes the system safe area.
                        .padding(.horizontal, 10)
                        .padding(.top, (controlHeights["header"] ?? 44) + 8)
                        .padding(.bottom, (controlHeights["footer"] ?? 44) + 8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let message = error ?? fonts.error {
                    VStack(spacing: 18) { Text(message); Button("إعادة المحاولة") { Task { await load() } } }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if renderingFailed {
                    ContentUnavailableView("تعذّر فتح الصفحة", systemImage: "book.closed", description: Text("حاول الانتقال إلى صفحة أخرى ثم العودة. إذا استمرت المشكلة، تواصل مع الدعم مع ذكر رقم الصفحة."))
                } else { ProgressView("تنزيل بيانات المصحف والتحقق من الخط…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if tools { VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("إغلاق المصحف")
                    Spacer(); Text(title).font(.headline).lineLimit(1); Spacer()
                    if audio.playing != nil { Button { audio.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }.accessibilityLabel("إيقاف التلاوة") }
                    else if audio.loadingKey != nil {
                        Button { audio.stop() } label: { ProgressView().frame(width: 44, height: 44) }.accessibilityLabel("إلغاء تحميل التلاوة")
                    } else { Button { khatmah = true } label: { Image(systemName: "book.closed").frame(width: 44, height: 44) }.accessibilityLabel("رحلة الختمة وتأكيد القراءة").accessibilityIdentifier("reader.khatmah") }
                }.background { measureControl("header") }
                Spacer()
                HStack {
                    Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(number == 604).accessibilityLabel("الصفحة التالية").accessibilityIdentifier("reader.next")
                    Spacer()
                    Button("الصفحة \(ArabicSearch.digits(number)) من ٦٠٤") { input = ""; picker = true }.frame(minHeight: 44).accessibilityIdentifier("reader.jump")
                    Spacer()
                    Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(number == 1).accessibilityLabel("الصفحة السابقة").accessibilityIdentifier("reader.previous")
                }.background { measureControl("footer") }
            }.padding(.horizontal, 10).transition(.opacity) }
        }
        .onPreferenceChange(MushafControlHeight.self) { heights in
            for (key, height) in heights where height.isFinite && height > 0 {
                if abs((controlHeights[key] ?? 0) - height) > 0.5 { controlHeights[key] = height }
            }
        }
        .transaction { transaction in
            if reduced || store.data.lowMotion { transaction.disablesAnimations = true }
        }
        .task { await load() }
        .task(id: number) { renderingFailed = false; await fonts.load(String(format: "QCF2%03d", number)) }
        .onDisappear { audio.stop(); audio.onVerse = nil }
        .onChange(of: number) { _, value in lastPage = value }
        .sheet(item: $sheetVerse) { selection in
            VerseTools(selection: selection, audio: audio, selected: $selected)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $khatmah) { NavigationStack { KhatmahJourneyView(currentPage: number) } }
        .sheet(isPresented: $picker) {
            NavigationStack { Form {
                TextField("١ إلى ٦٠٤", text: $input).keyboardType(.numberPad).accessibilityIdentifier("reader.pageNumber")
                Button("انتقل") { if let value = ArabicSearch.integer(input), (1...604).contains(value) { turn(value - number); picker = false } }
            }.navigationTitle("الانتقال في المصحف").toolbar { Button("إغلاق") { picker = false } } }
        }
        .alert("التلاوة", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button("حسنًا") { audio.error = nil } } message: { Text(audio.error ?? "") }
    }
    private func measureControl(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: MushafControlHeight.self, value: [key: geometry.size.height])
        }
    }
    private var title: String {
        guard let key = selected ?? page?.words.first?.verse, let n = Int(key.split(separator: ":")[0]), store.quran.indices.contains(n - 1) else { return "المصحف" }
        return store.quran[n - 1].name
    }
    private func turn(_ amount: Int) {
        guard (1...604).contains(number + amount) else { return }
        lastPage = number + amount
        number += amount; selected = nil
    }
    private func load() async {
        error = nil
        do {
            try OriginalMushafCompanion.register()
            let metadata = try OriginalMushafRows.load()
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let cache = QCFV2ContentCache(file: directory.appendingPathComponent("qcf-v2-cache.json"), endpoint: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
            let entry: QCFV2ContentCache.Entry
            if let offline = await cache.cached() {
                entry = offline
                Task { _ = try? await cache.refresh() }
            } else { entry = try await cache.refresh() }
            let data = try JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot).validated()
            try metadata.validate(data)
            // Materialize the stable corpus IDs once, not for every snapshot record.
            let corpusKeys = keys
            var pagesByVerse: [String: Int] = [:]
            for record in data.records where record.record_type == "mushaf_word" {
                if let verseID = record.verse_id, let sourcePage = record.page_number {
                    let key = corpusKeys[verseID - 1]
                    pagesByVerse[key] = min(pagesByVerse[key] ?? sourcePage, sourcePage)
                }
            }
            let versePages = pagesByVerse
            try Task.checkCancellation()
            let first = snapshot == nil; snapshot = data; rows = metadata
            if first {
                number = initialPage.flatMap { (1...604).contains($0) ? $0 : nil }
                    ?? versePages["\(chapter):\(ayah)"] ?? 1
                lastPage = number
            }
            audio.onVerse = { key in
                selected = key
                if page?.words.contains(where: { $0.verse == key }) != true,
                   let target = versePages[key] { number = target }
            }
            await fonts.load(String(format: "QCF2%03d", number))
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "تعذّر التحقق من بيانات المصحف أو خطوطه. اتصل بالإنترنت للتنزيل الأول؛ تبقى النسخة المحفوظة متاحة دون اتصال بعد اكتماله." }
    }
}
private struct MushafControlHeight: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
struct VerseSelection: Identifiable { let key: String; var id: String { key }; var chapter: Int { Int(key.split(separator: ":")[0])! }; var ayah: Int { Int(key.split(separator: ":")[1])! } }

private struct VerseTools: View {
    let selection: VerseSelection
    @ObservedObject var audio: MushafVerseAudio
    @Binding var selected: String?
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tafsir = MushafTafsir()
    @State private var showTafsir = false
    @State private var showHifz = false
    @State private var repeatCount = 3
    @State private var repeatEnd = 1
    @State private var notice: String?
    init(selection: VerseSelection, audio: MushafVerseAudio, selected: Binding<String?>) {
        self.selection = selection; self.audio = audio; self._selected = selected
        self._repeatEnd = State(initialValue: selection.ayah)
    }
    private var surah: Surah { store.quran[selection.chapter - 1] }
    private var verse: Ayah { surah.ayahs[selection.ayah - 1] }
    private var copyText: String { "\(QuranText.verse(chapter: selection.chapter, ayah: verse))\n[\(surah.name): \(selection.ayah)]" }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("الاستماع من هذه الآية", systemImage: "play.fill") {
                        audio.play((selection.ayah...surah.ayahs.count).map { "\(selection.chapter):\($0)" }); dismiss()
                    }.accessibilityIdentifier("verse.play")
                    Button("التفسير", systemImage: "book") { showTafsir = true }.accessibilityIdentifier("verse.tafsir")
                    Button(store.data.bookmarks.contains(selection.key) ? "إزالة العلامة المرجعية" : "إضافة علامة مرجعية", systemImage: "bookmark") { store.toggleBookmark(surah: selection.chapter, ayah: selection.ayah) }.accessibilityIdentifier("verse.bookmark")
                }
                Section("التكرار") {
                    Stepper("عدد التكرارات: \(repeatCount)", value: $repeatCount, in: 1...20)
                    Stepper("إلى الآية: \(repeatEnd)", value: $repeatEnd, in: selection.ayah...surah.ayahs.count)
                    Button("تشغيل التكرار") { audio.play((0..<repeatCount).flatMap { _ in (selection.ayah...repeatEnd).map { "\(selection.chapter):\($0)" } }); dismiss() }
                }
                Section("الحفظ والمشاركة") {
                    Button("بدء الحفظ أو المراجعة من هنا", systemImage: "sparkles") { showHifz = true }
                    Button("نسخ نص الآية", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText; notice = "نُسخ نص الآية مع اسم السورة ورقمها." }.accessibilityIdentifier("verse.copy")
                    ShareLink(item: copyText) { Label("مشاركة الآية", systemImage: "square.and.arrow.up") }
                    if let notice { Text(notice).accessibilityIdentifier("verse.notice") }
                }
            }
            .navigationTitle("\(surah.name) · الآية \(selection.ayah)")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("verse.tools.\(selection.key)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(surah.name) · الآية \(selection.ayah)").font(.headline)
                        .accessibilityIdentifier("verse.tools.title")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }.accessibilityIdentifier("verse.tools.close")
                }
            }
            .onAppear { repeatEnd = selection.ayah }
            .sheet(isPresented: $showTafsir) {
                NavigationStack {
                    ScrollView { VStack(alignment: .leading, spacing: 18) {
                        if let text = tafsir.text { Text(text).font(.title3).accessibilityIdentifier("verse.tafsir.text") }
                        else if let error = tafsir.error { Text(error); Button("إعادة المحاولة") { Task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) } } }
                        else { ProgressView("تحميل التفسير الميسر…") }
                    }.padding() }
                    .navigationTitle("التفسير · \(surah.name) \(selection.ayah)")
                    .toolbar { Button("إغلاق") { showTafsir = false }.accessibilityIdentifier("verse.tafsir.close") }
                    .task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) }
                }
            }
            .sheet(isPresented: $showHifz) {
                NavigationStack {
                    Form {
                        Text("ابدأ بالآية \(selection.ayah) من \(surah.name). تُحفظ نتائج المراجعة السابقة؛ البدء يستبدل خطة الحفظ والجلسة الحالية.")
                        Button("بدء جلسة هذه الآية") {
                            let plan = MemorizationPlan(chapter: selection.chapter, from: selection.ayah, to: selection.ayah, daily: 1)
                            if memorization.configure(plan, corpus: store.quran), memorization.saveSession(MemorizationSession(chapter: selection.chapter, keys: [selection.ayah])) { notice = "أُضيفت الآية إلى جلسة الحفظ. افتح قسم الحفظ للمتابعة."; showHifz = false }
                        }
                    }.navigationTitle("الحفظ والمراجعة").toolbar { Button("إغلاق") { showHifz = false } }
                }
            }
        }
    }
}
