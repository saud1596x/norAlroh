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
    @Published private(set) var microphonePeak: Float?
    @Published private(set) var inputGuidance: String?
    private var weakInputWindows = 0
    private var clippedInputWindows = 0
    @Published var message: String?
    enum GuidedPhase: Equatable { case inactive, reference, clearance, ready, attempt, feedback }
    @Published private(set) var guidedPhase: GuidedPhase = .inactive
    private var guidedRevision = UUID()
    private var guidedDelay: Task<Void, Never>?
    private var guidedFailure: AnyCancellable?
    private weak var referenceAudio: MushafVerseAudio?
    private var referenceExposure: String?
    func listenFirst(_ keys: [String], audio: MushafVerseAudio, repetitions: Int, responsePause: Int) {
        guard state == .idle || state == .stopped || state == .paused else { return }
        cancelGuided(); message = nil
        let token = UUID(); guidedRevision = token
        referenceAudio = audio; guidedPhase = .reference
        // Conservatively retain listening assistance for this entire session,
        // including interrupted reference playback and later microphone takes.
        referenceExposure = audio.reciterDirectory
        if var current = record, current.phase != .finished {
            current.referenceExposure = referenceExposure
            do { try save(current); record = current }
            catch { cancelGuided(); message = "تعذّر حفظ حالة المساعدة. أعد المحاولة."; return }
        }
        // Loading/decoding can fail after play() returns. Release the guided
        // gate on that actual error so a failed reference cannot permanently
        // block an otherwise usable microphone. Replaced players are ignored.
        guidedFailure = audio.$error.dropFirst().compactMap { $0 }.sink { [weak self] failure in
            guard let self, self.guidedRevision == token,
                  self.guidedPhase == .reference || self.guidedPhase == .clearance || self.guidedPhase == .ready else { return }
            self.cancelGuided(); self.message = failure
        }
        let onFinished: () -> Void = { [weak self, weak audio] in
            guard let self, let audio, self.guidedRevision == token else { return }
            self.referenceExposure = audio.reciterDirectory
            self.guidedPhase = .clearance
            self.guidedDelay = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(max(1, min(30, responsePause))) * 1_000_000_000) }
                catch { return }
                guard let self, self.guidedRevision == token, !Task.isCancelled else { return }
                self.guidedPhase = .ready
            }
        }
        audio.play(keys, repetitions: repetitions, onFinished: onFinished, onInterrupted: { [weak self] in
            guard let self, self.guidedRevision == token else { return }
            self.cancelGuided()
        })
        if audio.error != nil { cancelGuided() }
    }
    func cancelGuided() {
        guidedRevision = UUID(); guidedDelay?.cancel(); guidedDelay = nil
        guidedFailure?.cancel(); guidedFailure = nil
        let previous = referenceAudio; referenceAudio = nil
        previous?.stop()
        referenceExposure = record?.referenceExposure ?? referenceExposure; guidedPhase = .inactive
    }
    private let worker: any QuranSpeechRecognitionProvider
    private let referenceBinder = QuranRecognitionWorker.shared
    private let drainTimeout: Double
    private let recognitionTimeout: Double
    private let analysisPersistence: ((QuranRecitationRecord) async throws -> Void)?
    private let recognizeWindow: (QuranAudioWindow) async throws -> QuranRecognitionWorker.Result
    private let requestPermission: () async -> Bool
    private let archiveRoot: URL?
    private let makeCapture: (QuranPCMWriter, @escaping @Sendable (Error) -> Void) throws -> any QuranAudioCapture
    private let setSessionActive: (Bool) throws -> Void
    init(requestPermission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() },
         archiveRoot: URL? = nil, drainTimeout: Double = 8, recognitionTimeout: Double = 20,
         recognizeWindow: ((QuranAudioWindow) async throws -> QuranRecognitionWorker.Result)? = nil,
         analysisPersistence: ((QuranRecitationRecord) async throws -> Void)? = nil,
         recognitionProvider: any QuranSpeechRecognitionProvider = QuranRecognitionWorker.shared,
         makeCapture: @escaping (QuranPCMWriter, @escaping @Sendable (Error) -> Void) throws -> any QuranAudioCapture = {
             try QuranMicrophoneCapture(writer: $0, onFailure: $1)
         }, setSessionActive: @escaping (Bool) throws -> Void = { active in
             try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
         }) {
        self.requestPermission = requestPermission; self.drainTimeout = drainTimeout
        self.worker = recognitionProvider
        self.analysisPersistence = analysisPersistence
        self.recognitionTimeout = recognitionTimeout
        self.recognizeWindow = recognizeWindow ?? { window in try await recognitionProvider.recognize(window) }
        self.archiveRoot = archiveRoot; self.makeCapture = makeCapture; self.setSessionActive = setSessionActive
    }
    private var capture: (any QuranAudioCapture)?
    private var mailbox: QuranWindowMailbox?
    private var pump: Task<Void, Never>?
    private var capturing = false
    private var audioFocusLease: UUID?
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
    private func saveAnalysis(_ value: QuranRecitationRecord) async throws {
        if let analysisPersistence { try await analysisPersistence(value); return }
        guard let journal else { throw QuranJournalFailure.invalidRecord }
        // Large source histories must not freeze page turns while JSON is
        // validated/encoded. The journal serializes this with pause/recovery.
        try await Task.detached(priority: .utility) { try journal.save(value) }.value
    }
    private func mergeAnalysis(_ value: QuranRecitationRecord) {
        guard var latest = record, latest.id == value.id else { return }
        // pause() may already have closed the audio take while the save ran.
        // Preserve its current frames, closed flag, and phase.
        latest.observedSpeech = value.observedSpeech; latest.wordingEvents = value.wordingEvents
        latest.evidence = value.evidence; latest.recognitionUnavailable = value.recognitionUnavailable
        record = latest
    }
    var hasSession: Bool { record != nil && state != .stopped && state != .idle }
    var microphoneMeter: Double {
        guard state == .listening, let peak = microphonePeak, peak > 0 else { return 0 }
        let decibels = 20 * log10(Double(peak))
        return min(1, max(0, (decibels + 60) / 60))
    }
    var hiddenIDs: Set<Int> {
        // Starting a microphone session is not proof that recognition works.
        // Keep the reader usable until actual saved word evidence establishes
        // a position, and expose the text again if the engine becomes unavailable.
        guard hasSession, recognitionAvailable,
              record?.closedTextRequested == true || !revealed.isEmpty else { return [] }
        return expectedIDs.subtracting(revealed).subtracting(Set(record?.textHintIDs ?? []))
    }
    private func noteExposedPracticeText(_ value: inout QuranRecitationRecord) {
        if value.closedTextRequested == true {
            value.textExposureOccurred = true
            if value.phase == .recording, let index = value.takes.indices.last, !value.takes[index].closed {
                value.takes[index].textExposureOccurred = true
            }
        }
    }
    func revealNextWord(in verse: String, entireVerse: Bool = false) async {
        guard state == .listening || state == .paused else { return }
        await pause()
        guard state == .paused, var current = record else { return }
        guard current.keys.contains(verse) else { message = "هذه الآية خارج مقطع التسميع الحالي."; return }
        let shown = revealed.union(Set(current.textHintIDs ?? []))
        let candidates = words.filter { $0.verse == verse && expectedIDs.contains($0.id) && !shown.contains($0.id) }
        let added = entireVerse ? candidates.map(\.id) : Array(candidates.prefix(1).map(\.id))
        guard !added.isEmpty else { return }
        current.textHintIDs = (current.textHintIDs ?? []) + added
        do { try save(current); record = current }
        catch { message = "تعذّر حفظ التلميح. لم تُحسب الكلمات كتلاوة." }
    }
    var status: String {
        if guidedPhase == .reference { return "استمع · الميكروفون مغلق" }
        if guidedPhase == .clearance { return "استعد · الميكروفون مغلق" }
        if guidedPhase == .ready { return "جاهز · ابدأ عندما تكون مستعدًا" }
        switch state {
        case .idle: return "ابدأ التسميع"
        case .permission: return "إذن الميكروفون"
        case .preparing: return "تجهيز الميكروفون…"
        case .listening:
            if !recognitionAvailable { return "التسجيل مستمر · التتبع متعذر" }
            if microphonePeak == 0 { return "الميكروفون مفتوح · لا يصل صوت" }
            // The model receives an amplified copy; raw microphone amplitude
            // alone cannot classify an actively recognized voice as unusable.
            if revealed.isEmpty, let microphonePeak,
               microphonePeak * Float(QuranRecognitionAudio.maximumInferenceGain) < Float(AudioEvidenceGate.minimumRMS) {
                return "الصوت ضعيف جدًا · قرّب الميكروفون"
            }
            if revealed.isEmpty { return uncertain ? "أستمع · لم أتعرف على الموضع بعد" : "أستمع · أنتظر بداية التلاوة" }
            return uncertain ? "أستمع · أنتظر وضوح الموضع" : "أستمع إليك"
        case .paused: return "متوقف مؤقتًا"
        case .processing: return "حفظ الجلسة ومعالجة التلاوة"
        case .stopped: return "انتهت الجلسة"
        }
    }
    func start(keys: [String], page: Int, snapshot: QCFV2Snapshot, corpus: [Surah], closedText: Bool = false,
               automaticScope: Bool = false) async {
        guard guidedPhase != .reference && guidedPhase != .clearance else {
            message = "انتظر انتهاء التلاوة والاستعداد، ثم ابدأ التسميع."; return
        }
        guard state == .idle || state == .stopped else { return }
        if state == .stopped, guidedPhase == .inactive, record?.phase == .finished {
            referenceExposure = nil
        }
        let token = UUID(); revision = token; message = nil; permissionDenied = false; microphonePeak = nil
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
            // Capture first: model loading belongs to recognize(), not the
            // microphone permission/start path. PCM is durably recorded while
            // the bundled model warms up, even if recognition later fails.
            let scope = Set(keys)
            tracker = QuranRecitationTracker(expected: words.filter { scope.contains($0.verse) })
            expectedIDs = Set(tracker?.expected.map(\.id) ?? [])
            revealed = []; currentVerse = automaticScope ? nil : keys.first; uncertain = false; finishRequest = false
            let next = QuranRecitationRecord(keys: keys, originPage: page)
            var prepared = next
            prepared.closedTextRequested = closedText
            prepared.textExposureOccurred = !closedText
            prepared.automaticScope = automaticScope
            prepared.referenceExposure = referenceExposure
            try journal.create(prepared); record = prepared
            if referenceExposure != nil { guidedPhase = .attempt }
            try await beginTake(token: token)
        } catch {
            guard revision == token else { return }
            if var failed = record, failed.closedTextRequested == true {
                failed.recognitionUnavailable = true; noteExposedPracticeText(&failed)
                record = failed; recognitionAvailable = false
                try? save(failed)
            }
            state = record == nil ? .idle : .paused
            message = "تعذّر تجهيز التسميع الآن. النموذج مضمّن ولا يحتاج تنزيلًا جديدًا. أعد المحاولة أو تابع القراءة."
        }
    }
    private func bind(snapshot: QCFV2Snapshot, corpus: [Surah]) async throws {
        let verseKeys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        words = try await referenceBinder.bind(snapshot: snapshot, verseKeys: verseKeys)
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
            expectedIDs = Set(words.filter { scope.contains($0.verse) }.map(\.id))
            if restored.recognitionUnavailable { noteExposedPracticeText(&restored) }
            let restoredTracker = try QuranRecitationTracker(expected: words.filter { scope.contains($0.verse) }, restoring: restored.evidence)
            try journal.save(restored)
            record = restored; tracker = restoredTracker; revealed = restoredTracker.revealedIDs
            recognitionAvailable = !restored.recognitionUnavailable
            expectedIDs = Set(restoredTracker.expected.map(\.id))
            currentVerse = restored.evidence.last?.verse ?? (restored.automaticScope == true ? nil : restored.keys.first)
            finishRequest = false; revision = UUID(); uncertain = restored.recognitionUnavailable; state = .paused
        } catch {
            guard revision == token else { return }
            state = .idle; message = "تعذّر استعادة الجلسة. لم تُحذف ملفات الصوت أو بياناتها؛ يمكنك فتح التسجيلات لفحص المتاح."
        }
    }
    func resume() async {
        guard guidedPhase != .reference && guidedPhase != .clearance else { return }
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
        let lease = UUID()
        guard NoorAudioFocus.shared.acquireRecording(lease) else {
            throw NSError(domain: "NoorAudioFocus", code: 1)
        }
        audioFocusLease = lease
        var started = false
        defer {
            if !started {
                try? setSessionActive(false)
                NoorAudioFocus.shared.releaseRecording(lease)
                audioFocusLease = nil
            }
        }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try setSessionActive(true)
        // Use the highest hardware input gain only when this route supports it.
        // A route rejecting gain adjustment must not prevent microphone capture.
        if audio.isInputGainSettable { try? audio.setInputGain(1.0) }
        var take = QuranRecitationTake()
        take.referenceExposure = referenceExposure ?? next.referenceExposure
        take.textHintIDs = next.textHintIDs
        take.textExposureOccurred = next.textExposureOccurred
        if referenceExposure != nil { guidedPhase = .attempt; referenceExposure = nil }
        let mailbox = QuranWindowMailbox()
        let writer = try QuranPCMWriter(url: journal.audio(session: next.id, take: take.id), lowLatency: true,
            onWindow: { mailbox.put($0) }, onFailure: { @Sendable [weak self] _ in
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
            microphonePeak = nil
            inputGuidance = nil; weakInputWindows = 0; clippedInputWindows = 0
            microphone.observeQuality { [weak self] reading in
                Task { @MainActor in
                    guard let self, self.revision == token, self.capturing else { return }
                    self.weakInputWindows = reading == .weak || reading == .noSignal ? self.weakInputWindows + 1 : 0
                    self.clippedInputWindows = reading == .clipping ? self.clippedInputWindows + 1 : 0
                    if self.clippedInputWindows >= 2 { self.inputGuidance = "الصوت مرتفع ومشوّش؛ أبعد الميكروفون قليلًا." }
                    else if self.weakInputWindows >= 6 { self.inputGuidance = "الصوت منخفض أو أنك متوقف؛ قرّب الميكروفون عند القراءة." }
                    else if reading == .present { self.inputGuidance = nil }
                }
            }
            microphone.observeLevel { [weak self] peak in
                Task { @MainActor in
                    guard let self, self.revision == token, self.capturing, peak.isFinite else { return }
                    self.microphonePeak = peak
                }
            }
            capture = microphone; self.mailbox = mailbox; capturing = true
            try microphone.start(); started = true
            // A new audio take does not prove that previously failed inference
            // has recovered. Keep text visible until a successful decode.
            recognitionAvailable = !next.recognitionUnavailable; state = .listening
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
        var prepared = false
        while revision == token, !Task.isCancelled {
            let pendingWindow: QuranAudioWindow?
            do { pendingWindow = try mailbox.take() }
            catch {
                guard var current = record else { return }
                current.recognitionUnavailable = true; noteExposedPracticeText(&current)
                record = current; uncertain = true; recognitionAvailable = false
                do { try save(current) }
                catch { stopForJournalFailure(); return }
                message = "تأخر التتبع عن التسجيل؛ احتُفظ بالصوت. أوقف التسميع ثم استأنفه لإعادة المحاولة."
                return
            }
            guard let window = pendingWindow else {
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
                if !prepared {
                    // Cold model loading has its own bounded deadline, after
                    // capture is already writing PCM. Do not charge model
                    // startup against the shorter per-window decode deadline.
                    try await NoorOperationDeadline.run(seconds: 45) { try await self.worker.prepare() }
                    guard revision == token, !Task.isCancelled else { return }
                    prepared = true
                }
                recognized = try await NoorOperationDeadline.run(seconds: recognitionTimeout) {
                    try await self.recognizeWindow(window)
                }
            }
            catch is CancellationError { return }
            catch {
                guard revision == token, var current = record else { return }
                current.recognitionUnavailable = true; noteExposedPracticeText(&current)
                record = current; uncertain = true; recognitionAvailable = false
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
                try updatedTracker.reconsiderAudio(takeID: take, start: window.offset,
                    end: Double(window.endFrame) / 16_000)
                var additions: [QuranWordEvidence] = []
                for run in recognized.runs {
                    additions += try updatedTracker.consume(run, takeID: take, offset: window.offset)
                }
                let available = recognitionAvailable || !additions.isEmpty
                // Persist only actually decoded, quality-accepted words. Missing
                // speech remains unresolved; the Quran reference never fills it.
                var observed = QuranObservedSpeech(takeID: take, start: window.offset,
                    end: Double(window.endFrame) / 16_000,
                    words: recognized.runs.flatMap { $0.map(\.text) },
                    unresolved: recognized.hasUnresolvedSpeech,
                    backendID: worker.capabilities.backendID,
                    modelID: worker.capabilities.modelID, modelRevision: worker.capabilities.modelRevision)
                if let observations = recognized.observations {
                    observed.evidenceVersion = 1
                    observed.recognitionWindowID = recognized.windowID
                    observed.recognitionRevision = 0
                    observed.wordObservations = observations
                    observed.processingConfiguration = QuranRecognitionModelDescriptor.bundled?.configuration
                }
                var spans = current.observedSpeech ?? []
                // Keep recognizer revisions as source evidence. Assessment can
                // supersede an interpretation without erasing what it decoded.
                if spans.last != observed { spans.append(observed) }
                let assessmentInput = Array(spans.suffix(16))
                let referenceWords = updatedTracker.expected
                let priorEvents = current.wordingEvents ?? []
                let sessionTakes = current.takes
                let events = await Task.detached(priority: .userInitiated) {
                    let fresh = QuranWordingAssessment.evaluate(assessmentInput, expected: referenceWords)
                    let older = priorEvents.filter { prior in
                        prior.state == "provisional" && !assessmentInput.contains(where: { $0.takeID == prior.takeID })
                    }
                    return QuranWordingAssessment.linkLaterAttempts(fresh + older, spans: assessmentInput,
                        takes: sessionTakes, expected: referenceWords)
                }.value
                guard revision == token, !Task.isCancelled, let latest = record else { return }
                current = latest
                current.observedSpeech = spans
                current.wordingEvents = QuranWordingAssessment.reconcile(previous: current.wordingEvents ?? [],
                    incoming: events, reconsidered: assessmentInput)
                current.evidence = updatedTracker.evidence; current.recognitionUnavailable = !available
                // Preserve in memory for a final save retry, but do not reveal
                // anything until its durable evidence has actually been saved.
                do { try await saveAnalysis(current) }
                catch {
                    guard revision == token else { return }
                    mergeAnalysis(current); tracker = updatedTracker
                    throw error
                }
                guard revision == token, !Task.isCancelled else { return }
                mergeAnalysis(current); tracker = updatedTracker
                recognitionAvailable = available
                revealed = Set(current.evidence.map(\.nativeID))
                currentVerse = current.evidence.last?.verse ?? (current.automaticScope == true ? nil : current.keys.first)
                uncertain = additions.isEmpty || recognized.hasUnresolvedSpeech
            } catch { guard revision == token else { return }; stopForJournalFailure(); return }

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
            if var current = record { current.recognitionUnavailable = true; noteExposedPracticeText(&current); record = current }
            recognitionAvailable = false; uncertain = true
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
        if let lease = audioFocusLease { NoorAudioFocus.shared.releaseRecording(lease) }
        audioFocusLease = nil
    }
    func finish() async {
        cancelGuided()
        finishRequest = true
        if state == .listening { await pause(); return }
        guard state == .paused, !closing, var current = record else { return }
        current.phase = .finished; current.finishedAt = Date()
        do { try save(current); record = current; state = .stopped }
        catch { message = "تعذّر حفظ الملخص. التسجيلات محفوظة؛ أعد المحاولة." }
    }
    @discardableResult func reviewFinding(_ id: UUID, disputed: Bool) -> Bool {
        guard !closing, state == .paused || state == .stopped, var current = record,
              let index = current.wordingEvents?.firstIndex(where: { $0.eventID == id && $0.state == "provisional" }) else { return false }
        current.wordingEvents?[index].userReview = disputed ? "disputed" : nil
        do { try save(current); record = current; return true }
        catch { message = "تعذّر حفظ مراجعتك. بقي التسجيل والملاحظة محفوظين."; return false }
    }
    deinit {
        pump?.cancel()
        if let lease = audioFocusLease {
            Task { @MainActor in NoorAudioFocus.shared.releaseRecording(lease) }
        }
    }
}

