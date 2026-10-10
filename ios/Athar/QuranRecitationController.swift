import Foundation
import AVFoundation
import Combine
import os

@MainActor final class QuranRecitationController: ObservableObject {
    // Instruments intervals contain no audio, transcript, verse or account data.
    private static let performanceLog = OSLog(subsystem: "com.saud1596x.nooralruh", category: "RecitationPerformance")
    enum State: Equatable { case idle, permission, preparing, listening, paused, processing, stopped }
    @Published private(set) var state = State.idle
    @Published private(set) var record: QuranRecitationRecord?
    @Published private(set) var revealed = Set<Int>()
    @Published private(set) var currentVerse: String?
    @Published private(set) var uncertain = false
    @Published private(set) var recognitionAvailable = true
    @Published private(set) var permissionDenied = false
    @Published var message: String?
    private let worker = QuranRecognitionWorker.shared
    private let drainTimeout: Double
    private let recognitionTimeout: Double
    private let recognizeWindow: (QuranAudioWindow) async throws -> QuranRecognitionWorker.Result
    private let requestPermission: () async -> Bool
    private let archiveRoot: URL?
    private let makeCapture: (QuranPCMWriter, @escaping (Error) -> Void) throws -> any QuranAudioCapture
    private let setSessionActive: (Bool) throws -> Void
    init(requestPermission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() },
         archiveRoot: URL? = nil, drainTimeout: Double = 8, recognitionTimeout: Double = 20,
         recognizeWindow: @escaping (QuranAudioWindow) async throws -> QuranRecognitionWorker.Result = {
             try await QuranRecognitionWorker.shared.recognize($0)
         },
         makeCapture: @escaping (QuranPCMWriter, @escaping (Error) -> Void) throws -> any QuranAudioCapture = {
             try QuranMicrophoneCapture(writer: $0, onFailure: $1)
         }, setSessionActive: @escaping (Bool) throws -> Void = { active in
             try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
         }) {
        self.requestPermission = requestPermission; self.drainTimeout = drainTimeout
        self.recognitionTimeout = recognitionTimeout; self.recognizeWindow = recognizeWindow
        self.archiveRoot = archiveRoot; self.makeCapture = makeCapture; self.setSessionActive = setSessionActive
    }
    private var capture: (any QuranAudioCapture)?
    private var mailbox: QuranWindowMailbox?
    private var pump: Task<Void, Never>?
    private var capturing = false
    private var tracker: QuranRecitationTracker?
    private var expectedIDs = Set<Int>()
    private var words: [QuranAlignedWord] = []
    private var revision = UUID()
    private var finishRequest = false
    private var closing = false
    private var journal: QuranRecitationJournal? {
        if let archiveRoot { return QuranRecitationJournal(root: archiveRoot) }
        return (try? MushafRecordingArchive.root()).map(QuranRecitationJournal.init(root:))
    }
    private func save(_ value: QuranRecitationRecord) throws {
        let span = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "Recitation journal save", signpostID: span)
        defer { os_signpost(.end, log: Self.performanceLog, name: "Recitation journal save", signpostID: span) }
        guard let journal else { throw QuranJournalFailure.invalidRecord }
        try journal.save(value)
    }
    var hasSession: Bool { record != nil && state != .stopped && state != .idle }
    var hiddenIDs: Set<Int> {
        // Starting a microphone session is not proof that recognition works.
        // Keep the reader usable until actual saved word evidence establishes
        // a position, and expose the text again if the engine becomes unavailable.
        guard hasSession, !revealed.isEmpty, recognitionAvailable else { return [] }
        return expectedIDs.subtracting(revealed)
    }
    var status: String {
        switch state {
        case .idle: return "ابدأ التسميع"
        case .permission: return "إذن الميكروفون"
        case .preparing: return "تجهيز الميكروفون…"
        case .listening:
            if !recognitionAvailable { return "التسجيل مستمر · التتبع متعذر" }
            if revealed.isEmpty { return uncertain ? "أستمع · لم أتعرف على الموضع بعد" : "أستمع · أنتظر بداية التلاوة" }
            return uncertain ? "أستمع · أنتظر وضوح الموضع" : "أستمع إليك"
        case .paused: return "متوقف مؤقتًا"
        case .processing: return "حفظ الجلسة ومعالجة التلاوة"
        case .stopped: return "انتهت الجلسة"
        }
    }
    func start(keys: [String], page: Int, snapshot: QCFV2Snapshot, corpus: [Surah]) async {
        guard state == .idle || state == .stopped else { return }
        let token = UUID(); revision = token; message = nil; permissionDenied = false
        record = nil; tracker = nil; expectedIDs = []; revealed = []; currentVerse = nil; recognitionAvailable = true
        state = .permission
        guard await requestPermission() else {
            guard revision == token else { return }
            permissionDenied = true; state = .idle
            message = "اسمح بالميكروفون من إعدادات الجهاز لبدء التسميع. يمكنك متابعة قراءة المصحف دون إذن."; return
        }
        guard revision == token else { return }
        state = .preparing
        do {
            guard MushafStudySession(keys: keys, scope: .range, page: page).valid(corpus: corpus), let journal else {
                throw QuranJournalFailure.invalidRecord
            }
            try await bind(snapshot: snapshot, corpus: corpus)
            guard revision == token, state == .preparing else { return }
            try await NoorOperationDeadline.run(seconds: 45) { try await self.worker.prepare() }
            guard revision == token, state == .preparing else { return }
            let scope = Set(keys)
            tracker = QuranRecitationTracker(expected: words.filter { scope.contains($0.verse) })
            expectedIDs = Set(tracker?.expected.map(\.id) ?? [])
            revealed = []; currentVerse = keys.first; uncertain = false; finishRequest = false
            let next = QuranRecitationRecord(keys: keys, originPage: page)
            try journal.create(next); record = next
            try await beginTake(token: token)
        } catch {
            guard revision == token else { return }
            state = record == nil ? .idle : .paused
            message = "تعذّر تجهيز التسميع الآن. النموذج مضمّن ولا يحتاج تنزيلًا جديدًا. أعد المحاولة أو تابع القراءة."
        }
    }
    private func bind(snapshot: QCFV2Snapshot, corpus: [Surah]) async throws {
        let verseKeys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        words = try await worker.bind(snapshot: snapshot, verseKeys: verseKeys)
    }
    func restore(id: UUID, snapshot: QCFV2Snapshot, corpus: [Surah]) async {
        guard state == .idle || state == .stopped else { return }
        let token = UUID(); revision = token
        do {
            guard let journal else { throw QuranJournalFailure.invalidRecord }
            var restored = try journal.load(id)
            guard MushafStudySession(keys: restored.keys, scope: .range, page: restored.originPage).valid(corpus: corpus) else {
                throw QuranJournalFailure.invalidRecord
            }
            if restored.phase == .finished {
                record = restored; state = .stopped; return
            }
            state = .preparing
            try await bind(snapshot: snapshot, corpus: corpus)
            guard revision == token, state == .preparing else { return }
            for index in restored.takes.indices {
                let take = restored.takes[index]
                let live = journal.audio(session: restored.id, take: take.id)
                let removed = journal.root.appendingPathComponent("DeletedAudio", isDirectory: true)
                    .appendingPathComponent(restored.id.uuidString, isDirectory: true)
                    .appendingPathComponent(take.id.uuidString + ".caf")
                // Moving a take to recoverable removal does not erase the
                // session's durable progress or make it impossible to resume.
                let url = FileManager.default.fileExists(atPath: live.path) ? live : removed
                if FileManager.default.fileExists(atPath: url.path) {
                    let file = try AVAudioFile(forReading: url)
                    guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
                          file.length >= take.frames else { throw QuranJournalFailure.invalidRecord }
                    restored.takes[index].frames = file.length
                } else if take.frames > 0 { throw QuranJournalFailure.invalidRecord }
                restored.takes[index].closed = true
            }
            if restored.phase == .recording { restored.phase = .interrupted; restored.recognitionUnavailable = true }
            let scope = Set(restored.keys)
            let restoredTracker = try QuranRecitationTracker(expected: words.filter { scope.contains($0.verse) }, restoring: restored.evidence)
            try journal.save(restored)
            record = restored; tracker = restoredTracker; revealed = restoredTracker.revealedIDs
            expectedIDs = Set(restoredTracker.expected.map(\.id))
            currentVerse = restored.evidence.last?.verse ?? restored.keys.first
            finishRequest = false; revision = UUID(); uncertain = restored.recognitionUnavailable; state = .paused
        } catch {
            guard revision == token else { return }
            state = .idle; message = "تعذّر استعادة الجلسة. لم تُحذف ملفات الصوت أو بياناتها؛ يمكنك فتح التسجيلات لفحص المتاح."
        }
    }
    func resume() async {
        guard state == .paused, !closing, record != nil else { return }
        permissionDenied = false; state = .permission
        let token = revision
        guard await requestPermission() else {
            guard revision == token else { return }
            state = .paused; permissionDenied = true; message = "الميكروفون غير مسموح. تقدمك وتسجيلاتك محفوظة."; return
        }
        guard revision == token, state == .permission else { return }
        do {
            state = .preparing
            try await NoorOperationDeadline.run(seconds: 45) { try await self.worker.prepare() }
            guard revision == token, state == .preparing else { return }
            try await beginTake(token: token)
        }
        catch {
            guard revision == token else { return }
            state = .paused; message = "تعذّر استئناف الميكروفون. احتُفظ بالتسجيل السابق."
        }
    }
    private func beginTake(token: UUID) async throws {
        guard var next = record, let journal else { throw QuranJournalFailure.invalidRecord }
        finishRequest = false; next.finishedAt = nil
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try setSessionActive(true)
        var started = false
        defer { if !started { try? setSessionActive(false) } }
        let take = QuranRecitationTake()
        let mailbox = QuranWindowMailbox()
        let writer = try QuranPCMWriter(url: journal.audio(session: next.id, take: take.id),
            onWindow: { mailbox.put($0) }, onFailure: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.revision == token else { return }
                    self.message = "تعذّر حفظ بقية الصوت. احتُفظ بالجزء المسجل؛ توقفت الجلسة لحماية تسجيلك."
                    await self.pause()
                }
            })
        next.takes.append(take); next.phase = .recording
        do {
            try journal.save(next); record = next
            let microphone = try makeCapture(writer, { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.revision == token else { return }
                    self.message = "انقطع إدخال الصوت. احتُفظ بالتسجيل؛ استأنف عندما يصبح الميكروفون متاحًا."
                    await self.pause()
                }
            })
            capture = microphone; self.mailbox = mailbox; capturing = true
            try microphone.start(); started = true; recognitionAvailable = true; state = .listening
            pump = Task { [weak self] in await self?.processWindows(mailbox, take: take.id, token: token) }
        } catch {
            capturing = false
            if let capture { _ = await capture.stop() }
            else { _ = await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } } }
            capture = nil; self.mailbox = nil
            next.takes[next.takes.count - 1].closed = true; next.phase = .paused
            if let saved = try? AVAudioFile(forReading: journal.audio(session: next.id, take: take.id)) {
                next.takes[next.takes.count - 1].frames = saved.length
            }
            record = next
            do { try journal.save(next) }
            catch { message = "الصوت محفوظ، لكن تعذّر حفظ حالة الجلسة. أعد محاولة الإنهاء." }
            throw error
        }
    }
    private func processWindows(_ mailbox: QuranWindowMailbox, take: UUID, token: UUID) async {
        while revision == token, !Task.isCancelled {
            guard let window = mailbox.take() else {
                if !capturing { return }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                continue
            }
            guard var next = record, let takeIndex = next.takes.firstIndex(where: { $0.id == take }) else { return }
            let span = OSSignpostID(log: Self.performanceLog)
            os_signpost(.begin, log: Self.performanceLog, name: "Recitation window processing", signpostID: span)
            defer { os_signpost(.end, log: Self.performanceLog, name: "Recitation window processing", signpostID: span) }
            next.takes[takeIndex].frames = max(next.takes[takeIndex].frames, window.endFrame)
            record = next
            let recognized: QuranRecognitionWorker.Result
            do {
                recognized = try await NoorOperationDeadline.run(seconds: recognitionTimeout) {
                    try await self.recognizeWindow(window)
                }
            }
            catch is CancellationError { return }
            catch {
                guard revision == token, var current = record else { return }
                current.recognitionUnavailable = true; record = current; uncertain = true; recognitionAvailable = false
                do { try save(current) }
                catch { stopForJournalFailure(); return }
                if (error as? URLError)?.code == .timedOut {
                    message = "تعذّر التتبع الآن. التسجيل مستمر ومحفوظ؛ يمكنك إنهاء الجلسة ومراجعة الصوت."
                    // A Core ML call can ignore cancellation. Do not queue more
                    // recognition behind it or accept its eventual late result.
                    return
                }
                continue // Recording remains independent of model failure.
            }
            guard revision == token, !Task.isCancelled, var current = record, var updatedTracker = tracker else { return }
            do {
                var additions: [QuranWordEvidence] = []
                for run in recognized.runs {
                    additions += try updatedTracker.consume(run, takeID: take, offset: window.offset)
                }
                current.evidence += additions; recognitionAvailable = true
                // Preserve in memory for a final save retry, but do not reveal
                // anything until its durable evidence has actually been saved.
                record = current; tracker = updatedTracker
                try save(current)
                revealed = Set(current.evidence.map(\.nativeID))
                if let last = additions.last { currentVerse = last.verse }
                uncertain = additions.isEmpty || recognized.hasUnresolvedSpeech
            } catch { stopForJournalFailure(); return }

        }
    }
    private func stopForJournalFailure() {
        message = "تعذّر حفظ نتيجة التتبع. توقف الميكروفون لحماية الجلسة؛ احتُفظ بملف الصوت."
        // Do not await this from the inference task: pause drains that task.
        Task { [weak self] in await self?.pause() }
    }
    func pause() async {
        guard !closing else { return }
        if state == .permission || state == .preparing {
            revision = UUID(); state = record == nil ? .idle : .paused; return
        }
        guard state == .listening else { return }
        closing = true; state = .processing
        if let capture {
            let result = await capture.stop()
            if var current = record, !current.takes.isEmpty {
                let index = current.takes.count - 1
                switch result {
                case .success(let frames): current.takes[index].frames = frames
                case .failure:
                    if let url = journal?.audio(session: current.id, take: current.takes[index].id),
                       let file = try? AVAudioFile(forReading: url) { current.takes[index].frames = file.length }
                    message = "توقفت الجلسة بسبب تعذّر حفظ الصوت كاملًا. الجزء المتاح محفوظ في التسجيلات."
                }
                current.takes[index].closed = true; record = current
            }
        }
        capture = nil; capturing = false
        // Recognition is cancellable at encoder/decoder boundaries. A long
        // final decode can be cancelled without touching the closed audio.
        let pending = pump
        do {
            try await NoorOperationDeadline.run(seconds: drainTimeout) { await pending?.value }
        } catch {
            // A Core ML decode may ignore cancellation. Invalidate its token
            // before saving so it cannot change a paused or resumed session.
            revision = UUID(); pending?.cancel()
            if var current = record { current.recognitionUnavailable = true; record = current }
        }
        pump = nil; mailbox = nil
        if var current = record {
            current.phase = finishRequest ? .finished : .paused
            current.finishedAt = finishRequest ? Date() : nil
            do { try save(current); record = current; state = finishRequest ? .stopped : .paused }
            catch { record = current; state = .paused; message = "الصوت محفوظ، لكن تعذّر حفظ ملخص الجلسة. أعد محاولة الإنهاء." }
        }
        closing = false
        try? setSessionActive(false)
    }
    func finish() async {
        finishRequest = true
        if state == .listening { await pause(); return }
        guard state == .paused, !closing, var current = record else { return }
        current.phase = .finished; current.finishedAt = Date()
        do { try save(current); record = current; state = .stopped }
        catch { message = "تعذّر حفظ الملخص. التسجيلات محفوظة؛ أعد المحاولة." }
    }
    deinit { pump?.cancel() }
}
