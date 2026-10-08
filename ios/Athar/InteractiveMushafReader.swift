import SwiftUI
import UIKit
import AVFoundation
import Combine

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
            Task { @MainActor in
                guard let self, self.player?.currentItem === item else { return }
                self.error = "تعذّر تشغيل الآية. أعد تنزيلها من التنزيلات، أو تحقق من اتصال الإنترنت."; self.stop()
            }
        }
        if let end { NotificationCenter.default.removeObserver(end) }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self, self.player?.currentItem === item else { return }; self.advance()
        } }
        if let failure { NotificationCenter.default.removeObserver(failure) }
        failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player?.currentItem === item else { return }
                self.error = "انقطع تحميل التلاوة. تحقق من الاتصال وأعد المحاولة."; self.stop()
            }
        }
        error = nil; player?.play()
    }
    func stop() {
        player?.pause(); player = nil; observation = nil; playbackObservation = nil; playing = nil; loadingKey = nil; queue = []
        if let end { NotificationCenter.default.removeObserver(end) }; end = nil
        if let failure { NotificationCenter.default.removeObserver(failure) }; failure = nil
    }
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
    @StateObject private var studyRecorder = MushafSessionRecorder()
    @EnvironmentObject private var legacyRecorder: LocalRecitationRecorder
    @EnvironmentObject private var legacySpeech: LocalSpeechRecitation
    @State private var recordingsOpen = false
    @State private var recordingSession: UUID?
    private let meterTick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    let chapter: Int; let ayah: Int; let initialPage: Int?
    @State private var snapshot: QCFV2Snapshot?
    @State private var rows: OriginalMushafRows?
    @State private var number = 1
    @State private var selected: String?
    @State private var manualSelection: VerseSelection?
    @State private var sheetVerse: VerseSelection?
    @State private var sheetAction = VerseToolAction.details
    @State private var tools = true
    @State private var controlHeights: [String: CGFloat] = ["header": 44, "footer": 44]
    @State private var picker = false
    @State private var input = ""
    @State private var error: String?
    @State private var renderingFailed = false
    @State private var studyOpen = false
    @State private var studySetup = false
    @State private var studyStartKey: String?
    @State private var studyRequestFromSheet = false
    @State private var studyIndex: MushafStudyWordIndex?
    @State private var audioHelpRequest: String?
    @State private var studySummary = false
    @State private var finishAfterSetupDismiss = false
    @State private var studyError: String?
    @Environment(\.scenePhase) private var scenePhase
    private var study: MushafStudySession? { studyOpen ? memorization.mushafStudy.pending : nil }
    private var hiddenStudyWords: Set<Int> {
        guard let study, let studyIndex else { return [] }
        return studyIndex.hiddenIDs(session: study)
    }
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
                        hiddenWordIDs: hiddenStudyWords, allowsVerseSelection: !studyOpen,
                        onVerse: { key in
                            guard !studyOpen else { return }
                            if let key {
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
                        .padding(.top, (studyOpen ? 88 : (controlHeights["header"] ?? 44)) + 8)
                        .padding(.bottom, (studyOpen ? 176 : (controlHeights["footer"] ?? 44)) + 8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let message = error ?? fonts.error {
                    VStack(spacing: 18) { Text(message).accessibilityIdentifier("reader.load.error"); Button("إعادة المحاولة") { Task { await load() } } }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if renderingFailed {
                    ContentUnavailableView("تعذّر فتح الصفحة", systemImage: "book.closed", description: Text("حاول الانتقال إلى صفحة أخرى ثم العودة. إذا استمرت المشكلة، تواصل مع الدعم مع ذكر رقم الصفحة."))
                } else { ProgressView("تنزيل بيانات المصحف والتحقق من الخط…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if studyOpen, let study { studyControls(study) }
            else if tools { VStack {
                HStack {
                    if manualSelection != nil {
                        Button { clearManualSelection() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("إلغاء تحديد الآية").accessibilityIdentifier("verse.tools.close")
                    } else {
                        Button { dismiss() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("إغلاق المصحف")
                    }
                    Spacer()
                    Text(manualSelection.map { "\(title) · الآية \(ArabicSearch.digits($0.ayah))" } ?? title)
                        .font(.headline).lineLimit(1).accessibilityIdentifier(manualSelection == nil ? "reader.title" : "verse.tools.title")
                    Spacer()
                    if let selection = manualSelection {
                        Button { openTools(selection, action: .details) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("المزيد من أدوات الآية").accessibilityIdentifier("verse.more")
                    } else if audio.playing != nil { Button { audio.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }.accessibilityLabel("إيقاف التلاوة") }
                    else if audio.loadingKey != nil {
                        Button { audio.stop() } label: { ProgressView().frame(width: 44, height: 44) }.accessibilityLabel("إلغاء تحميل التلاوة")
                    } else {
                        Button { showStudySetup() } label: { Image(systemName: "mic").frame(width: 44, height: 44) }
                            .accessibilityLabel("الحفظ والتسميع").accessibilityIdentifier("reader.study")
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
        .task { await load() }
        .task(id: number) { renderingFailed = false; await fonts.load(String(format: "QCF2%03d", number)) }
        .onDisappear { pauseStudy(); audio.stop(); audio.onVerse = nil }
        .onChange(of: scenePhase) { _, value in
            if value == .background || (value == .inactive && !studyRecorder.requestingPermission) { pauseStudy() }
        }
        .onReceive(meterTick) { _ in studyRecorder.meters() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { event in
            if (event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { pauseStudy() }
        }
        .onChange(of: number) { _, value in lastPage = value }
        .sheet(item: $sheetVerse, onDismiss: { clearManualSelection(); if studyRequestFromSheet { studyRequestFromSheet = false; studySetup = true } }) { selection in
            VerseTools(selection: selection, audio: audio, selected: $selected, initialAction: sheetAction, onStudy: { key in
                studyStartKey = key; studyRequestFromSheet = true
            })
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $studySetup, onDismiss: {
            if finishAfterSetupDismiss { finishAfterSetupDismiss = false; finishStudy() }
        }) {
            MushafStudySetup(page: number, pageKeys: Array(Set(page?.words.map(\.verse) ?? [])).sorted { keys.firstIndex(of: $0)! < keys.firstIndex(of: $1)! },
                initialKey: studyStartKey ?? page?.words.first?.verse ?? "1:1", onOpen: openStudy)
        }
        .sheet(isPresented: $recordingsOpen) {
            if let recordingSession { MushafRecordingList(session: recordingSession, recorder: studyRecorder) }
        }
        .sheet(isPresented: $studySummary) {
            MushafStudyResultView().environmentObject(memorization)
        }
        .sheet(isPresented: $picker) {
            NavigationStack { Form {
                TextField("١ إلى ٦٠٤", text: $input).keyboardType(.numberPad).accessibilityIdentifier("reader.pageNumber")
                Button("انتقل") { if let value = ArabicSearch.integer(input), (1...604).contains(value) { turn(value - number); picker = false } }
            }.navigationTitle("الانتقال في المصحف").toolbar { Button("إغلاق") { picker = false } } }
        }
        .alert("التلاوة", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button("حسنًا") { audio.error = nil } } message: { Text(audio.error ?? "") }
        .alert("التسجيل المحلي", isPresented: Binding(get: { studyRecorder.message != nil && !recordingsOpen }, set: { if !$0 { studyRecorder.message = nil } })) {
            if studyRecorder.permissionDenied {
                Button("إعدادات الميكروفون") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Button("متابعة التسميع", role: .cancel) {
                studyRecorder.message = nil
                if studyOpen, study?.phase == .paused {
                    if !memorization.updateMushafStudy({ $0.phase = .active; return true }) { showStudySaveError() }
                }
            }
        } message: { Text(studyRecorder.message ?? "") }
        .alert("حفظ الجلسة", isPresented: Binding(get: { studyError != nil }, set: { if !$0 { studyError = nil } })) {
            Button("حسنًا") { studyError = nil }
        } message: { Text(studyError ?? "") }
    }
    private func toggleStudyMicrophone(_ session: MushafStudySession) {
        if studyRecorder.recording || studyRecorder.requestingPermission { studyRecorder.stop() }
        else {
            audio.stop(); audioHelpRequest = nil; legacyRecorder.stop(); legacySpeech.stop()
            Task { await studyRecorder.start(session: session) }
        }
    }
    private func openStudyRecordings(_ session: MushafStudySession) {
        pauseStudy(); recordingSession = session.id; recordingsOpen = true
    }
    private func showStudySetup(_ key: String? = nil) {
        audio.stop(); audioHelpRequest = nil; clearManualSelection()
        studyStartKey = key; studySetup = true
    }
    private func openStudy() {
        guard let session = memorization.mushafStudy.pending, studyIndex != nil else { return }
        if session.phase == .finishing || session.currentKey == nil {
            finishAfterSetupDismiss = true; studySetup = false; return
        }
        studyOpen = true; tools = true; studySetup = false; followStudy(session)
    }
    private func followStudy(_ session: MushafStudySession) {
        audio.stop(); audioHelpRequest = nil; manualSelection = nil
        selected = session.currentKey
        if let key = session.currentKey, let target = studyIndex?.pages[key]?.first {
            number = target; lastPage = target
        }
    }
    private func pauseStudy() {
        guard studyOpen else { return }
        studyRecorder.stop(); audio.stop(); audioHelpRequest = nil
        guard study?.phase == .active else { return }
        if !memorization.updateMushafStudy({ $0.phase = .paused; return true }) { showStudySaveError() }
    }
    private func finishStudy() {
        studyRecorder.stop(); audio.stop(); audioHelpRequest = nil
        if memorization.finishMushafStudy() { studyOpen = false; selected = nil; studySummary = true }
        else { showStudySaveError() }
    }
    private func answerStudy(_ assessment: String) {
        audio.stop(); audioHelpRequest = nil
        if memorization.updateMushafStudy({ $0.answer(assessment) }), let updated = memorization.mushafStudy.pending {
            if updated.currentKey == nil { finishStudy() } else { followStudy(updated) }
        } else { showStudySaveError() }
    }
    private func showStudySaveError() {
        studyError = memorization.error ?? "تعذّر حفظ التغيير. احتُفظ بالجولة السابقة؛ أعد المحاولة أو صدّر بياناتك من الإعدادات."
    }
    private func studyControls(_ session: MushafStudySession) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button { pauseStudy(); studyOpen = false; selected = nil } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("العودة للقراءة وحفظ الجلسة").accessibilityIdentifier("study.leave")
                    Spacer()
                    Text("تسميع ذاتي · \(session.answers.count + 1) / \(session.keys.count)").font(.headline).lineLimit(1)
                    Spacer()
                    Button { finishStudy() } label: {
                        Text("إنهاء").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("study.finish")
                }
                HStack {
                    Button { toggleStudyMicrophone(session) } label: {
                        Group {
                            if studyRecorder.requestingPermission { ProgressView() }
                            else { Image(systemName: studyRecorder.recording ? "mic.fill" : "mic") }
                        }.frame(width: 44, height: 44).contentShape(Rectangle())
                    }.disabled(session.phase != .active)
                        .accessibilityLabel(studyRecorder.recording ? "إيقاف التسجيل وحفظ المقطع" : studyRecorder.requestingPermission ? "إلغاء بدء التسجيل" : "تسجيل صوتي محلي اختياري")
                        .accessibilityIdentifier("study.mic")
                    Text("\(title) · الآية \(session.currentKey?.split(separator: ":").last.map(String.init) ?? "—")").lineLimit(1)
                    Spacer()
                    Button {
                        if session.phase == .active { pauseStudy() }
                        else if session.phase == .paused {
                            if !memorization.updateMushafStudy({ $0.phase = .active; return true }) { showStudySaveError() }
                        }
                    } label: {
                        Text(session.phase == .paused ? "استئناف" : "إيقاف مؤقت")
                            .frame(minWidth: 80, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("study.pause")
                }.font(.caption)
            }.frame(height: 88)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                HStack {
                    Text(session.phase == .paused ? "الجلسة متوقفة · تقدمك محفوظ" : studyRecorder.recording ? "تسجيل محلي · \(MushafAudioTime.text(studyRecorder.elapsed)) · تقييم ذاتي" : "تقييم ذاتي؛ التحليل الصوتي غير متاح")
                        .font(.caption).lineLimit(1).accessibilityIdentifier("study.status")
                    Spacer(minLength: 4)
                    Button { openStudyRecordings(session) } label: {
                        Text("التسجيلات").font(.caption).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("study.recordings")
                }.frame(height: 44)
                HStack(spacing: 4) {
                    Button("كشف كلمة") { revealStudy(all: false) }.accessibilityIdentifier("study.revealWord").disabled(session.assistance.revealAll || session.assistance.visibleWords >= (session.currentKey.flatMap { studyIndex?.words[$0]?.count } ?? 0))
                    Button("كشف الآية") { revealStudy(all: true) }.accessibilityIdentifier("study.revealAll").disabled(session.assistance.revealAll || session.assistance.visibleWords >= (session.currentKey.flatMap { studyIndex?.words[$0]?.count } ?? 0))
                    Button(audio.loadingKey != nil || audio.playing != nil ? "إيقاف الصوت" : "استماع") {
                        if audio.loadingKey != nil || audio.playing != nil { audio.stop(); audioHelpRequest = nil }
                        else if let key = session.currentKey { studyRecorder.stop(); audioHelpRequest = key; audio.play([key]) }
                    }.accessibilityIdentifier("study.listen")
                }.buttonStyle(MushafStudyButtonStyle()).disabled(session.phase != .active)
                HStack(spacing: 4) {
                    Button("تذكّرتها") { answerStudy("remembered") }.accessibilityIdentifier("study.remembered")
                    Button("أحتاج مراجعة") { answerStudy("review") }.accessibilityIdentifier("study.review")
                    Button("تجاوز") { answerStudy("skip") }.accessibilityIdentifier("study.skip")
                }.buttonStyle(MushafStudyButtonStyle()).disabled(session.phase != .active)
                HStack {
                    let pages = session.currentKey.flatMap { studyIndex?.pages[$0] } ?? []
                    Button { turn(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(!pages.contains(number - 1)).accessibilityLabel("الجزء السابق من الآية")
                    Spacer(); Text("الصفحة \(number) · المساعدة تُحفظ مع النتيجة").font(.caption).lineLimit(1); Spacer()
                    Button { turn(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(!pages.contains(number + 1)).accessibilityLabel("تكملة الآية")
                }
            }.frame(height: 176)
        }.padding(.horizontal, 10)
    }
    private func revealStudy(all: Bool) {
        guard let session = study, let key = session.currentKey, let count = studyIndex?.words[key]?.count else { return }
        guard session.phase == .active, !session.assistance.revealAll, session.assistance.visibleWords < count else { return }
        if !memorization.updateMushafStudy({ $0.reveal(wordCount: count, all: all) }) { showStudySaveError() }
    }
    private func readerControlMeasurement(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ReaderControlHeight.self, value: [key: geometry.size.height])
        }
    }
    private func clearManualSelection() {
        manualSelection = nil
        selected = audio.playing
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
        guard let key = selected ?? page?.words.first?.verse, let n = Int(key.split(separator: ":")[0]), store.quran.indices.contains(n - 1) else { return "المصحف" }
        return store.quran[n - 1].name
    }
    private func turn(_ amount: Int) {
        guard (1...604).contains(number + amount) else { return }
        if let study, let current = study.currentKey,
           studyIndex?.pages[current]?.contains(number + amount) != true { return }
        let destination = number + amount
        // Persist before publishing the new page, including a quick close/background.
        lastPage = destination
        number = destination; selected = study?.currentKey; manualSelection = nil
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
                if studyOpen {
                    guard audioHelpRequest == key else { return }
                    audioHelpRequest = nil
                    if !memorization.updateMushafStudy({ $0.recordAudioHelp(for: key) }) {
                        audio.stop(); pauseStudy(); showStudySaveError()
                    }
                    return
                }
                manualSelection = nil
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
    @State private var notice: String?
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
                    Stepper("عدد التكرارات: \(repeatCount)", value: $repeatCount, in: 1...20)
                    Stepper("إلى الآية: \(repeatEnd)", value: $repeatEnd, in: selection.ayah...surah.ayahs.count)
                    Button("تشغيل التكرار") { audio.play((0..<repeatCount).flatMap { _ in (selection.ayah...repeatEnd).map { "\(selection.chapter):\($0)" } }); dismiss() }.accessibilityIdentifier("verse.repeat.start")
                }
                if initialAction == .details {
                Section("الحفظ والمشاركة") {
                    Button("بدء الحفظ أو المراجعة من هنا", systemImage: "sparkles") { onStudy(selection.key); dismiss() }
                    Button("نسخ نص الآية", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText; notice = "نُسخ نص الآية مع اسم السورة ورقمها." }.accessibilityIdentifier("verse.copy")
                    ShareLink(item: copyText) { Label("مشاركة الآية", systemImage: "square.and.arrow.up") }
                    if let notice { Text(notice).accessibilityIdentifier("verse.notice") }
                }
                }
                } }
            }
            .navigationTitle("\(surah.name) · الآية \(selection.ayah)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(surah.name) · الآية \(selection.ayah)").font(.headline)
                        .accessibilityIdentifier("verse.sheet.title")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }.accessibilityIdentifier(initialAction == .tafsir ? "verse.tafsir.close" : "verse.sheet.close")
                }
            }
            .onAppear { repeatEnd = selection.ayah }
            .sheet(isPresented: $showTafsir) {
                NavigationStack {
                    tafsirContent
                    .navigationTitle("التفسير · \(surah.name) \(selection.ayah)")
                    .toolbar { Button("إغلاق") { showTafsir = false }.accessibilityIdentifier("verse.tafsir.close") }
                }
            }

        }
    }
    private var tafsirContent: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            if let text = tafsir.text { Text(text).font(.title3).accessibilityIdentifier("verse.tafsir.text") }
            else if let error = tafsir.error { Text(error); Button("إعادة المحاولة") { Task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) } } }
            else { ProgressView("تحميل التفسير الميسر…") }
        }.padding().frame(maxWidth: .infinity, alignment: .leading) }
            .task { await tafsir.load(chapter: selection.chapter, ayah: selection.ayah) }
    }
}
