import SwiftUI
import UIKit
import AVFoundation
import Combine

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
    @StateObject private var studyRecorder = MushafSessionRecorder()
    @StateObject private var recitation = QuranRecitationController()
    @AppStorage("noor.recitation.pending") private var pendingRecitation = ""
    @EnvironmentObject private var legacyRecorder: LocalRecitationRecorder
    @State private var recordingsOpen = false
    @State private var recordingsAfterResult = false
    @State private var recordingSession: UUID?
    let chapter: Int; let ayah: Int; let initialPage: Int?
    let startsStudy: Bool
    init(chapter: Int, ayah: Int, initialPage: Int?, startsStudy: Bool = false) {
        self.chapter = chapter; self.ayah = ayah; self.initialPage = initialPage; self.startsStudy = startsStudy
    }
    @State private var snapshot: QCFV2Snapshot?
    @State private var rows: OriginalMushafRows?
    @State private var number = 1
    @State private var selected: String?
    @State private var manualSelection: VerseSelection?
    @State private var sheetVerse: VerseSelection?
    @State private var sheetAction = VerseToolAction.details
    @State private var tools = true
    @State private var controlHeights: [String: CGFloat] = ["header": 44, "footer": 44]
    @State private var khatmah = false
    @State private var picker = false
    @State private var input = ""
    @State private var error: String?
    @State private var renderingFailed = false
    @State private var studyStartKey: String?
    @State private var studyRequestFromSheet = false
    @State private var studyIndex: MushafStudyWordIndex?
    @State private var studySummary = false
    @Environment(\.scenePhase) private var scenePhase
    private var studyOpen: Bool { recitation.hasSession || recitation.state == .permission || recitation.state == .preparing }
    private var hiddenStudyWords: Set<Int> { recitation.hiddenIDs }
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    private var keys: [String] { store.quran.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } } }
    private var page: OriginalPageData? {
        guard let snapshot, let rows else { return nil }
        return OriginalPageData.page(number, snapshot: snapshot, rows: rows, keys: keys)
    }
    // The visible selection owns both the toolbar and canvas. A playback
    // callback must never silently replace the verse whose tools are open.
    private var visibleSelection: String? {
        let key = manualSelection?.key ?? selected
        return page?.words.contains(where: { $0.verse == key }) == true ? key : nil
    }
    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            GeometryReader { geometry in
                if recitation.state == .preparing, UUID(uuidString: pendingRecitation) != nil, recitation.record == nil {
                    ProgressView("استعادة موضع التسميع…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let page, fonts.names[String(format: "QCF2%03d", number)] != nil, !renderingFailed {
                    OriginalMushafDrawing(page: page, corpus: store.quran, selected: visibleSelection, reduceMotion: reduced || store.data.lowMotion,
                        hiddenWordIDs: hiddenStudyWords, allowsVerseSelection: !studyOpen,
                        onVerse: { key in
                            guard !studyOpen else { return }
                            if let key {
                                audio.stop()
                                selected = key; manualSelection = VerseSelection(key: key)
                                withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.18)) { tools = true }
                            }
                        }, onFailure: { DispatchQueue.main.async { renderingFailed = true } }, onTurn: { turn($0) },
                        onToggleTools: {
                            if studyOpen { return }
                            if manualSelection != nil { clearManualSelection() }
                            else { withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.18)) { tools.toggle() } }
                        })
                        .padding(.horizontal, 12)
                        .padding(.top, (controlHeights["header"] ?? 44) + 8)
                        .padding(.bottom, (controlHeights["footer"] ?? 44) + 8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let message = error ?? fonts.error {
                    VStack(spacing: 18) { Text(message).accessibilityIdentifier("reader.load.error"); Button("إعادة المحاولة") { Task { await load() } } }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if renderingFailed {
                    ContentUnavailableView("تعذّر فتح الصفحة", systemImage: "book.closed", description: Text("حاول الانتقال إلى صفحة أخرى ثم العودة. إذا استمرت المشكلة، تواصل مع الدعم مع ذكر رقم الصفحة."))
                } else { ProgressView("تنزيل بيانات المصحف والتحقق من الخط…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if studyOpen { recitationControls }
            else if tools { VStack {
                HStack {
                    if manualSelection != nil {
                        Button { clearManualSelection() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("إلغاء تحديد الآية").accessibilityIdentifier("verse.tools.close")
                    } else {
                        Button { dismiss() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("إغلاق المصحف")
                    }
                    Spacer()
                    Text(manualSelection.map { "\(title) · الآية \(ArabicSearch.digits($0.ayah))" } ?? (audio.waitingKey == nil ? title : "مهلة التكرار · \(title)"))
                        .font(.headline).lineLimit(1).accessibilityIdentifier(manualSelection == nil ? "reader.title" : "verse.tools.title")
                        .accessibilityValue(manualSelection?.key ?? "")
                    Spacer()
                    if let selection = manualSelection {
                        Button { openTools(selection, action: .details) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("المزيد من أدوات الآية").accessibilityIdentifier("verse.more")
                    } else if audio.playing != nil || audio.waitingKey != nil { Button { audio.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }.accessibilityLabel(audio.waitingKey == nil ? "إيقاف التلاوة" : "إيقاف التكرار أثناء المهلة").accessibilityIdentifier("reader.audio.stop") }
                    else if audio.loadingKey != nil {
                        Button { audio.stop() } label: { ProgressView().frame(width: 44, height: 44) }.accessibilityLabel("إلغاء تحميل التلاوة")
                    } else {
                        Button { showStudySetup() } label: { Image(systemName: "mic").frame(width: 44, height: 44) }
                            .accessibilityLabel("الحفظ والتسميع").accessibilityIdentifier("reader.study")
                        Button { khatmah = true } label: { Image(systemName: "book.closed").frame(width: 44, height: 44) }
                            .accessibilityLabel("رحلة الختمة وتأكيد القراءة").accessibilityIdentifier("reader.khatmah")
                    }
                }.background { readerControlMeasurement("header") }
                Spacer()
                Group {
                    if let selection = manualSelection { verseActions(selection) }
                    else { HStack {
                    Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(number == 604).accessibilityLabel("الصفحة التالية").accessibilityIdentifier("reader.next")
                    Spacer()
                    Button("الصفحة \(ArabicSearch.digits(number)) من ٦٠٤") { input = ""; picker = true }
                        .frame(minHeight: 44).accessibilityIdentifier("reader.jump")
                    Spacer()
                    Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(number == 1).accessibilityLabel("الصفحة السابقة").accessibilityIdentifier("reader.previous")
                    } }
                }.background { readerControlMeasurement("footer") }
            }.padding(.horizontal, 10).transition(.opacity) }
        }
        .onPreferenceChange(ReaderControlHeight.self) { heights in
            for (key, height) in heights where height.isFinite && height > 0 {
                if abs((controlHeights[key] ?? 0) - height) > 0.5 { controlHeights[key] = height }
            }
        }
        .transaction { transaction in
            if reduced || store.data.lowMotion { transaction.disablesAnimations = true }
        }
        .task {
            await load()
            if startsStudy, snapshot != nil, fonts.error == nil { showStudySetup() }
        }
        .task(id: number) { renderingFailed = false; await fonts.load(String(format: "QCF2%03d", number)) }
        .onDisappear { Task { await recitation.pause() }; audio.stop(); audio.onVerse = nil; studyRecorder.stop() }
        .onChange(of: scenePhase) { _, value in
            if value == .background || (value == .inactive && recitation.state != .permission) { Task { await recitation.pause() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { event in
            if (event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { Task { await recitation.pause() } }
        }
        .onChange(of: number) { _, value in lastPage = value }
        .sheet(item: $sheetVerse, onDismiss: { clearManualSelection(); if studyRequestFromSheet { studyRequestFromSheet = false; showStudySetup(studyStartKey) } }) { selection in
            VerseTools(selection: selection, audio: audio, selected: $selected, initialAction: sheetAction, onStudy: { key in
                studyStartKey = key; studyRequestFromSheet = true
            })
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $khatmah) { NavigationStack { KhatmahJourneyView(currentPage: number) } }
        .sheet(isPresented: $recordingsOpen) {
            if let recordingSession { MushafRecordingList(session: recordingSession, recorder: studyRecorder) }
        }
        .sheet(isPresented: $studySummary, onDismiss: {
            if recordingsAfterResult { recordingsAfterResult = false; recordingsOpen = true }
        }) {
            if let record = recitation.record {
                QuranSessionResult(record: record, onRecordings: {
                    recordingSession = record.id; recordingsAfterResult = true; studySummary = false
                }, onReview: { key in
                    studySummary = false; selected = key; manualSelection = VerseSelection(key: key)
                    if let destination = studyIndex?.pages[key]?.first { number = destination; lastPage = destination }
                })
            }
        }
        .sheet(isPresented: $picker) {
            NavigationStack { Form {
                TextField("١ إلى ٦٠٤", text: $input).keyboardType(.numberPad).accessibilityIdentifier("reader.pageNumber")
                Button("انتقل") { if let value = ArabicSearch.integer(input), (1...604).contains(value) { turn(value - number); picker = false } }
            }.navigationTitle("الانتقال في المصحف").toolbar { Button("إغلاق") { picker = false } } }
        }
        .alert("التلاوة", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button("حسنًا") { audio.error = nil } } message: { Text(audio.error ?? "") }
        .onChange(of: recitation.record?.id) { _, value in
            if let value { pendingRecitation = value.uuidString }
        }
        .onChange(of: recitation.currentVerse) { _, key in
            guard recitation.hasSession, let key else { return }
            selected = key; manualSelection = nil
            if page?.words.contains(where: { $0.verse == key }) != true,
               let destination = studyIndex?.pages[key]?.first { number = destination; lastPage = destination }
        }
        .onChange(of: recitation.state) { _, state in
            if state == .stopped { pendingRecitation = ""; selected = nil; studySummary = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { event in
            if (event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { await recitation.pause() }
            }
        }
        .alert("التسميع", isPresented: Binding(get: { recitation.message != nil }, set: { if !$0 { recitation.message = nil } })) {
            if recitation.permissionDenied {
                Button("إعدادات الميكروفون") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Button("حسنًا", role: .cancel) { recitation.message = nil }
        } message: { Text(recitation.message ?? "") }
    }
    private func showStudySetup(_ key: String? = nil) {
        guard let snapshot, !recitation.hasSession else { return }
        audio.stop(); studyRecorder.stop(); legacyRecorder.stop(); clearManualSelection()
        let scope: [String]
        if let key { scope = [key] }
        else {
            let visible = Set(page?.words.map(\.verse) ?? [])
            scope = keys.filter { visible.contains($0) }
        }
        tools = true
        Task { await recitation.start(keys: scope, page: number, snapshot: snapshot, corpus: store.quran) }
    }
    private var recitationControls: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    Button("العودة للقراءة") { Task { await recitation.pause(); dismiss() } }
                    Button("تسجيلات الجلسة") {
                        Task {
                            await recitation.pause()
                            if let id = recitation.record?.id { recordingSession = id; recordingsOpen = true }
                        }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("خيارات التسميع").accessibilityIdentifier("study.options")
                Spacer(minLength: 8)
                Text(recitation.status).font(.subheadline).lineLimit(1)
                    .accessibilityIdentifier("study.status").accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 8)
                Button("إنهاء") { Task { await recitation.finish() } }
                    .frame(minWidth: 44, minHeight: 44).disabled(recitation.state == .processing)
                    .accessibilityIdentifier("study.finish")
            }.background { readerControlMeasurement("header") }
            Spacer(minLength: 0)
            HStack {
                Text("الصفحة \(number)").font(.caption).monospacedDigit()
                Spacer()
                Button {
                    Task {
                        if recitation.state == .paused { await recitation.resume() }
                        else { await recitation.pause() }
                    }
                } label: {
                    Group {
                        if recitation.state == .processing || recitation.state == .preparing { ProgressView() }
                        else { Image(systemName: recitation.state == .paused ? "mic.fill" : "pause.fill") }
                    }.frame(width: 44, height: 44).background(Theme.gold.opacity(0.12), in: Circle())
                }.disabled(recitation.state == .processing || recitation.state == .preparing || recitation.state == .permission)
                    .accessibilityLabel(recitation.state == .paused ? "استئناف التسميع" : "إيقاف التسميع مؤقتًا")
                    .accessibilityIdentifier("study.pause")
                Spacer()
                Image(systemName: recitation.state == .listening ? "waveform" : "mic.slash")
                    .foregroundStyle(Theme.gold).frame(width: 44, height: 44).accessibilityHidden(true)
            }.background { readerControlMeasurement("footer") }
        }.padding(.horizontal, 10)
    }
    private func readerControlMeasurement(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ReaderControlHeight.self, value: [key: geometry.size.height])
        }
    }
    private func clearManualSelection() {
        manualSelection = nil
        selected = audio.playing.flatMap { key in
            page?.words.contains(where: { $0.verse == key }) == true ? key : nil
        }
    }
    private func openTools(_ selection: VerseSelection, action: VerseToolAction) {
        sheetAction = action; sheetVerse = selection
    }
    private func verseActions(_ selection: VerseSelection) -> some View {
        HStack(spacing: 0) {
            verseAction("تفسير", symbol: "book", identifier: "verse.tafsir") { openTools(selection, action: .tafsir) }
            verseAction("استماع", symbol: "play.fill", identifier: "verse.play") {
                let count = store.quran[selection.chapter - 1].ayahs.count
                manualSelection = nil
                audio.play((selection.ayah...count).map { "\(selection.chapter):\($0)" })
            }
            verseAction("تكرار", symbol: "repeat", identifier: "verse.repeat") { openTools(selection, action: .repeatRange) }
            let bookmarked = store.data.bookmarks.contains(selection.key)
            verseAction(bookmarked ? "محفوظة" : "علامة", symbol: bookmarked ? "bookmark.fill" : "bookmark", identifier: "verse.bookmark") {
                store.toggleBookmark(surah: selection.chapter, ayah: selection.ayah)
            }.accessibilityLabel(bookmarked ? "إزالة العلامة المرجعية" : "إضافة علامة مرجعية")
            verseAction("حفظ", symbol: "mic", identifier: "verse.hifz") { showStudySetup(selection.key) }
        }
    }
    private func verseAction(_ label: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) { Image(systemName: symbol).font(.system(size: 16)); Text(label).font(.caption2).lineLimit(1) }
                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
        }.accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
    private var title: String {
        guard let key = visibleSelection ?? page?.words.first?.verse, let n = Int(key.split(separator: ":")[0]), store.quran.indices.contains(n - 1) else { return "المصحف" }
        return store.quran[n - 1].name
    }
    private func turn(_ amount: Int) {
        guard (1...604).contains(number + amount) else { return }
        if recitation.hasSession {
            let scope = Set(recitation.record?.keys ?? [])
            guard let snapshot, let rows,
                  OriginalPageData.page(number + amount, snapshot: snapshot, rows: rows, keys: keys).words.contains(where: { scope.contains($0.verse) }) == true else { return }
        }
        let destination = number + amount
        // Persist before publishing the new page, including a quick close/background.
        lastPage = destination
        number = destination; selected = recitation.hasSession ? recitation.currentVerse : nil; manualSelection = nil
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
            studyIndex = MushafStudyWordIndex(snapshot: data, keys: corpusKeys)
            if first {
                number = initialPage.flatMap { (1...604).contains($0) ? $0 : nil }
                    ?? versePages["\(chapter):\(ayah)"] ?? 1
                lastPage = number
            }
            audio.onVerse = { key in
                guard !recitation.hasSession else { return }
                guard manualSelection == nil, sheetVerse == nil else { return }
                selected = key
                if page?.words.contains(where: { $0.verse == key }) != true,
                   let target = versePages[key] { lastPage = target; number = target }
            }
            if first, let pending = UUID(uuidString: pendingRecitation) {
                await recitation.restore(id: pending, snapshot: data, corpus: store.quran)
                if recitation.hasSession {
                    selected = recitation.currentVerse
                    if let key = recitation.currentVerse, let destination = versePages[key] { number = destination; lastPage = destination }
                }
            }
            await fonts.load(String(format: "QCF2%03d", number))
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "تعذّر التحقق من بيانات المصحف أو خطوطه. اتصل بالإنترنت للتنزيل الأول؛ تبقى النسخة المحفوظة متاحة دون اتصال بعد اكتماله." }
    }
}
private struct ReaderControlHeight: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct VerseSelection: Identifiable { let key: String; var id: String { key }; var chapter: Int { Int(key.split(separator: ":")[0])! }; var ayah: Int { Int(key.split(separator: ":")[1])! } }

private enum VerseToolAction: Equatable { case details, tafsir, repeatRange }
private struct VerseTools: View {
    let selection: VerseSelection
    @ObservedObject var audio: MushafVerseAudio
    @Binding var selected: String?
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tafsir = MushafTafsir()
    @State private var showTafsir = false
    @State private var repeatCount = 3
    @State private var repeatEnd = 1
    @State private var repeatDelay = 0
    @State private var notice: String?
    @State private var tafsirHeight: CGFloat = 220
    let initialAction: VerseToolAction
    let onStudy: (String) -> Void
    init(selection: VerseSelection, audio: MushafVerseAudio, selected: Binding<String?>, initialAction: VerseToolAction = .details, onStudy: @escaping (String) -> Void) {
        self.selection = selection; self.audio = audio; self._selected = selected
        self.initialAction = initialAction; self.onStudy = onStudy
        self._repeatEnd = State(initialValue: selection.ayah)
    }
    private var surah: Surah { store.quran[selection.chapter - 1] }
    private var verse: Ayah { surah.ayahs[selection.ayah - 1] }
    private var copyText: String { "\(QuranText.verse(chapter: selection.chapter, ayah: verse))\n[\(surah.name): \(selection.ayah)]" }
    var body: some View {
        NavigationStack {
            Group {
                if initialAction == .tafsir { tafsirContent }
                else { List {
                if initialAction == .details {
                Section {
                    Button("الاستماع من هذه الآية", systemImage: "play.fill") {
                        audio.play((selection.ayah...surah.ayahs.count).map { "\(selection.chapter):\($0)" }); dismiss()
                    }.accessibilityIdentifier("verse.sheet.play")
                    Button("التفسير", systemImage: "book") { showTafsir = true }.accessibilityIdentifier("verse.sheet.tafsir")
                    Button(store.data.bookmarks.contains(selection.key) ? "إزالة العلامة المرجعية" : "إضافة علامة مرجعية", systemImage: "bookmark") { store.toggleBookmark(surah: selection.chapter, ayah: selection.ayah) }.accessibilityIdentifier("verse.sheet.bookmark")
                }
                }
                Section("التكرار") {
                    Stepper("عدد التكرارات: \(repeatCount)", value: $repeatCount, in: 1...20).accessibilityIdentifier("verse.repeat.count")
                    Stepper("إلى الآية: \(repeatEnd)", value: $repeatEnd, in: selection.ayah...surah.ayahs.count)
                    Stepper("مهلة بين التلاوات: \(repeatDelay) ثانية", value: $repeatDelay, in: 0...30).accessibilityIdentifier("verse.repeat.delay")
                    Text("يتكرر نطاق الآيات كاملًا بالترتيب. تبدأ المهلة بعد انتهاء كل تلاوة، ويمكن إيقافها من شريط المصحف.").font(.footnote)
                    Button("تشغيل التكرار") {
                        var next = memorization.mushafStudy
                        next.repetition = MushafRepeatPreferences(count: repeatCount, delaySeconds: repeatDelay)
                        guard memorization.saveMushafStudy(next) else { notice = "تعذّر حفظ خيارات التكرار. بياناتك السابقة محفوظة؛ صدّرها من الإعدادات."; return }
                        audio.play((selection.ayah...repeatEnd).map { "\(selection.chapter):\($0)" }, repetitions: repeatCount, delaySeconds: repeatDelay)
                        dismiss()
                    }.accessibilityIdentifier("verse.repeat.start")
                }
                if initialAction == .details {
                Section("الحفظ والمشاركة") {
                    Button("بدء الحفظ أو المراجعة من هنا", systemImage: "sparkles") { onStudy(selection.key); dismiss() }
                    Button("نسخ نص الآية", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText; notice = "نُسخ نص الآية مع اسم السورة ورقمها." }.accessibilityIdentifier("verse.copy")
                    ShareLink(item: copyText) { Label("مشاركة الآية", systemImage: "square.and.arrow.up") }
                }
                }
                } }
            }
            .navigationTitle("\(surah.name) · الآية \(selection.ayah)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // List rows below the viewport are created lazily. A result
                // placed after ShareLink can remain invisible on smaller phones
                // even after Copy has succeeded. Keep action feedback outside
                // the scrolling list so it is visible and accessible immediately.
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.regularMaterial)
                        .accessibilityIdentifier(initialAction == .repeatRange ? "verse.repeat.error" : "verse.notice")
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(surah.name) · الآية \(selection.ayah)").font(.headline)
                        .accessibilityIdentifier("verse.sheet.title")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }.accessibilityIdentifier(initialAction == .tafsir ? "verse.tafsir.close" : "verse.sheet.close")
                }
            }
            .onAppear {
                repeatEnd = selection.ayah
                let saved = memorization.mushafStudy.repetition ?? MushafRepeatPreferences()
                repeatCount = saved.count; repeatDelay = saved.delaySeconds
            }
            .sheet(isPresented: $showTafsir) {
                NavigationStack {
                    tafsirContent
                    .navigationTitle("التفسير · \(surah.name) \(selection.ayah)")
                    .toolbar { Button("إغلاق") { showTafsir = false }.accessibilityIdentifier("verse.tafsir.close") }
                }
                .presentationDetents([.height(tafsirHeight), .large])
                .presentationDragIndicator(.visible)
            }

        }
        .presentationDetents(initialAction == .tafsir ? [.height(tafsirHeight), .large] : [.medium, .large])
    }
    private var tafsirContent: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text(QuranText.verse(chapter: selection.chapter, ayah: verse))
                .font(.body).foregroundStyle(.secondary)
                .accessibilityIdentifier("verse.tafsir.ayah")
            Divider()
            if let text = tafsir.text { Text(text).font(.body).lineSpacing(6).accessibilityIdentifier("verse.tafsir.text") }
            else if let error = tafsir.error { Text(error); Button("إعادة المحاولة") { Task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) } } }
            else { ProgressView("تحميل التفسير الميسر…") }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: TafsirContentHeight.self, value: proxy.size.height)
            } }
        }
            .onPreferenceChange(TafsirContentHeight.self) { height in
                guard height.isFinite, height > 0 else { return }
                // Includes the actual text and a navigation/drag-handle lane.
                // Long explanations scroll; the reader can expand to full height.
                tafsirHeight = min(480, max(220, height + 80))
            }
            .task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) }
    }
}
private struct TafsirContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
