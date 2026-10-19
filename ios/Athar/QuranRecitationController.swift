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
    @Published private(set) var activeWordID: Int?
    private var listeningLocation = QuranListeningLocation()
    @Published private(set) var uncertain = false
    @Published private(set) var recognitionAvailable = true
    @Published private(set) var permissionDenied = false
    @Published private(set) var microphonePeak: Float?
    @Published private(set) var inputGuidance: String?
    @Published private(set) var trackingFeedback: QuranTrackingFeedback?
    @Published private(set) var trackingUncertainty = QuranTrackingUncertainty.none
    private var trackingFeedbackID: UUID?
    private var microphoneGuidance = QuranInputGuidance()
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
        referenceExposure = audio.currentRecordingIdentity
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
            self.referenceExposure = audio.currentRecordingIdentity
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
         recognitionProvider: any QuranSpeechRecognitionProvider = QuranRecognitionRouter(),
         makeCapture: @escaping (QuranPCMWriter, @escaping @Sendable (Error) -> Void) throws -> any QuranAudioCapture = {
             QuranMicrophoneCapture(writer: $0, onFailure: $1)
         }, setSessionActive: @escaping (Bool) throws -> Void = { active in
             try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
         }) {
        self.requestPermission = requestPermission; self.drainTimeout = drainTimeout
        self.worker = recognitionProvider
        self.analysisPersistence = analysisPersistence
        self.recognitionTimeout = recognitionTimeout
        self.recognizeWindow = recognizeWindow ?? { window in try await recognitionProvider.recognize(window) }
        self.archiveRoot = archiveRoot ?? (try? QuranLiveRecitationStorage.root())
        self.makeCapture = makeCapture; self.setSessionActive = setSessionActive
    }
    private var capture: (any QuranAudioCapture)?
    private var captureStart: Task<Void, Error>?
    private var mailbox: QuranWindowMailbox?
    private var pump: Task<Void, Never>?
    private var capturing = false
    private var audioFocusLease: UUID?
    private var tracker: QuranRecitationTracker?
    private var expectedIDs = Set<Int>()
    private var practiceVisibility = QuranPracticeVisibility(expected: [])
    private var words: [QuranAlignedWord] = []
    private var revision = UUID()
    private var finishRequest = false
    private var closing = false
    private var journal: QuranRecitationJournal? {
        archiveRoot.map(QuranRecitationJournal.init(root:))
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
        try await Task.detached(priority: .utility) { try journal.saveAnalysis(value) }.value
    }
    private func mergeAnalysis(_ value: QuranRecitationRecord) {
        guard var latest = record, latest.id == value.id else { return }
        // pause() may already have closed the audio take while the save ran.
        // Preserve its current frames, closed flag, and phase.
        latest.observedSpeech = value.observedSpeech; latest.wordingEvents = value.wordingEvents
        latest.evidence = value.evidence; latest.recognitionUnavailable = value.recognitionUnavailable
        let visible = Set(latest.retainedVisibleVerses ?? []).union(value.retainedVisibleVerses ?? [])
        if !visible.isEmpty { latest.retainedVisibleVerses = latest.keys.filter { visible.contains($0) } }
        if value.textExposureOccurred == true { latest.textExposureOccurred = true }
        let exposedTakes = Set(value.takes.filter { $0.textExposureOccurred == true }.map(\.id))
        let analyzedTakes = Dictionary(uniqueKeysWithValues: value.takes.map { ($0.id,$0) })
        for index in latest.takes.indices {
            let hints = Set(latest.takes[index].textHintIDs ?? []).union(analyzedTakes[latest.takes[index].id]?.textHintIDs ?? [])
            if !hints.isEmpty { latest.takes[index].textHintIDs = hints.sorted() }
        }
        for index in latest.takes.indices where exposedTakes.contains(latest.takes[index].id) {
            latest.takes[index].textExposureOccurred = true
        }
        record = latest
    }
    private func retainShownText(_ value: inout QuranRecitationRecord, completed: Set<String>, recognizedIDs: Set<Int>) {
        let visible = Set(value.retainedVisibleVerses ?? []).union(completed)
        if !visible.isEmpty { value.retainedVisibleVerses = value.keys.filter { visible.contains($0) } }
        let retained = practiceVisibility.visibleIDs(verses: value.retainedVisibleVerses ?? [])
        let assistance = retained.subtracting(recognizedIDs)
        if !assistance.isEmpty, let index = value.takes.indices.last {
            value.textExposureOccurred = true; value.takes[index].textExposureOccurred = true
            value.takes[index].textHintIDs = Set(value.takes[index].textHintIDs ?? []).union(assistance).sorted()
        }
    }
    var hasSession: Bool { record != nil && state != .stopped && state != .idle }
    var microphoneMeter: Double {
        guard state == .listening, let peak = microphonePeak, peak > 0 else { return 0 }
        let decibels = 20 * log10(Double(peak))
        return min(1, max(0, (decibels + 60) / 60))
    }
    var practiceTextHidden: Bool { record?.practiceTextHidden ?? record?.closedTextRequested ?? false }
    var hiddenIDs: Set<Int> {
        // Expose the text again if recognition becomes unavailable. Only saved
        // word evidence, previously shown complete ayahs, or an explicit hint
        // can reveal text. Display history is never assessment evidence.
        guard hasSession, recognitionAvailable,
              practiceTextHidden else { return [] }
        return expectedIDs.subtracting(revealed)
            .subtracting(practiceVisibility.visibleIDs(verses: record?.retainedVisibleVerses ?? []))
            .subtracting(Set(record?.textHintIDs ?? []))
    }
    @discardableResult func setPracticeTextHidden(_ hidden: Bool) -> Bool {
        guard hasSession, state == .listening || state == .paused, var current = record else { return false }
        if !hidden { noteExposedPracticeText(&current) }
        current.practiceTextHidden = hidden
        do {
            guard let journal else { throw QuranJournalFailure.invalidRecord }
            record = try journal.savePracticeTextVisibility(current)
            return true
        }
        catch { message = "تعذّر حفظ وضع عرض الآيات. أعد المحاولة."; return false }
    }
    private func noteExposedPracticeText(_ value: inout QuranRecitationRecord) {
        if value.closedTextRequested == true || value.practiceTextHidden == true {
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
            .union(practiceVisibility.visibleIDs(verses: current.retainedVisibleVerses ?? []))
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
            if let activity = trackingFeedback?.message(now: ProcessInfo.processInfo.systemUptime) { return activity }
            if let explanation = trackingUncertainty.message { return explanation }
            if revealed.isEmpty { return uncertain ? "أستمع · لم أتعرف على الموضع بعد" : "أستمع · أنتظر بداية التلاوة" }
            return uncertain ? "أستمع · أنتظر وضوح الموضع" : "أستمع إليك"
        case .paused: return "متوقف مؤقتًا"
        case .processing: return "إيقاف الميكروفون…"
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
        listeningLocation = QuranListeningLocation(); activeWordID = nil
        practiceVisibility = QuranPracticeVisibility(expected: [])
        state = .permission
        guard await requestPermission() else {
            guard revision == token else { return }
            permissionDenied = true; state = .idle
            message = "اسمح بالميكروفون من إعدادات الجهاز لبدء التسميع. يمكنك متابعة قراءة المصحف دون إذن."; return
        }
        guard revision == token else { return }
        state = .preparing
        do {
            try await Task.detached(priority: .utility) {
                try QuranLiveRecitationStorage.removePreviousRecordings()
            }.value
            guard revision == token, state == .preparing else { return }
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
            practiceVisibility = QuranPracticeVisibility(expected: tracker?.expected ?? [])
            revealed = []; currentVerse = automaticScope ? nil : keys.first; uncertain = false; finishRequest = false
            let next = QuranRecitationRecord(keys: keys, originPage: page)
            var prepared = next
            prepared.closedTextRequested = closedText
            prepared.practiceTextHidden = closedText
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
            practiceVisibility = QuranPracticeVisibility(expected: restoredTracker.expected)
            try journal.save(restored)
            record = restored; tracker = restoredTracker; revealed = restoredTracker.revealedIDs
            recognitionAvailable = !restored.recognitionUnavailable
            expectedIDs = Set(restoredTracker.expected.map(\.id))
            listeningLocation = QuranListeningLocation()
            if let take = restored.takes.last {
                listeningLocation.begin(takeID: take.id); listeningLocation.update(restored.evidence)
            }
            currentVerse = listeningLocation.verse ?? (restored.automaticScope == true ? nil : restored.keys.first)
            activeWordID = listeningLocation.activeNativeID
            finishRequest = false; revision = UUID(); uncertain = restored.recognitionUnavailable; state = .paused
        } catch {
            guard revision == token else { return }
            state = .idle; message = "تعذّر استئناف التسميع. اضغط الميكروفون لبدء محاولة جديدة داخل المصحف."
        }
    }
    func resume() async {
        guard guidedPhase != .reference && guidedPhase != .clearance else { return }
        guard state == .paused, !closing, record != nil else { return }
        permissionDenied = false; state = .permission
        // A successful pause previously reused the token. A queued route or
        // meter callback from that closed capture could then stop/overwrite a
        // newly resumed take. Every explicit resume owns a fresh callback epoch.
        let token = UUID(); revision = token
        guard await requestPermission() else {
            guard revision == token else { return }
            state = .paused; permissionDenied = true; message = "الميكروفون غير مسموح. يمكنك متابعة القراءة دون الميكروفون."; return
        }
        guard revision == token, state == .permission else { return }
        do {
            state = .preparing
            try await beginTake(token: token)
        }
        catch {
            guard revision == token else { return }
            state = .paused; message = "تعذّر استئناف الميكروفون. أعد المحاولة داخل المصحف."
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
            if !started, audioFocusLease == lease {
                try? setSessionActive(false)
                NoorAudioFocus.shared.releaseRecording(lease)
                audioFocusLease = nil
            }
        }
        let audio = AVAudioSession.sharedInstance()
        // Live recitation consumes microphone input only. Speaker/reference
        // playback is excluded by audio focus; opening a duplex speaker route
        // here is unnecessary and can contend with RemoteIO initialization.
        try audio.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try setSessionActive(true)
        // Use the highest hardware input gain only when this route supports it.
        // A route rejecting gain adjustment must not prevent microphone capture.
        if audio.isInputGainSettable { try? audio.setInputGain(1.0) }
        var take = QuranRecitationTake()
        take.referenceExposure = referenceExposure ?? next.referenceExposure
        let retainedText = practiceVisibility.visibleIDs(verses: next.retainedVisibleVerses ?? [])
        let shownHints = Set(next.textHintIDs ?? []).union(retainedText)
        take.textHintIDs = shownHints.isEmpty ? nil : shownHints.sorted()
        take.textExposureOccurred = next.textExposureOccurred
        if referenceExposure != nil { guidedPhase = .attempt; referenceExposure = nil }
        let mailbox = QuranWindowMailbox()
        let takeID = take.id, sessionID = next.id
        let writer = try QuranPCMWriter(url: journal.audio(session: next.id, take: take.id), lowLatency: true,
            onWindow: { [weak self] window in
                mailbox.put(window)
                let frames = window.endFrame // Already written original PCM, not a wall-clock estimate.
                Task { @MainActor in
                    self?.noteCapturedFrames(frames, session: sessionID, take: takeID, token: token)
                }
            }, onFailure: { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.revision == token else { return }
                    self.message = "تعذّرت معالجة بقية الصوت؛ توقف الميكروفون. أعد المحاولة داخل المصحف."
                    await self.pause()
                }
            })
        next.takes.append(take); next.phase = .recording
        do {
            try journal.save(next); record = next
            let microphone = try makeCapture(writer, { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.revision == token else { return }
                    self.message = "انقطع إدخال الصوت؛ استأنف عندما يصبح الميكروفون متاحًا."
                    await self.pause()
                }
            })
            microphonePeak = nil
            inputGuidance = nil; microphoneGuidance = QuranInputGuidance()
            trackingFeedback = nil; trackingFeedbackID = nil; trackingUncertainty = .none
            microphone.observeQuality { [weak self] reading in
                Task { @MainActor in
                    guard let self, self.revision == token, self.capturing else { return }
                    self.microphoneGuidance.consume(reading)
                    self.inputGuidance = self.microphoneGuidance.message
                }
            }
            microphone.observeLevel { [weak self] peak in
                Task { @MainActor in
                    guard let self, self.revision == token, self.capturing, peak.isFinite else { return }
                    self.microphonePeak = peak
                }
            }
            capture = microphone; self.mailbox = mailbox; capturing = true
            let opening = Task { try await microphone.start() }
            captureStart = opening
            defer { captureStart = nil }
            try await opening.value
            // Closing/pausing while the audio service opens cannot publish a
            // late listening state or recreate a deleted working session.
            guard revision == token, state == .preparing else { throw CancellationError() }
            started = true
            listeningLocation.begin(takeID: take.id); activeWordID = nil
            // A new audio take does not prove that previously failed inference
            // has recovered. Keep text visible until a successful decode.
            recognitionAvailable = !next.recognitionUnavailable; state = .listening
            pump = Task { [weak self] in await self?.processWindows(mailbox, take: take.id, token: token) }
        } catch {
            capturing = false
            if let capture { _ = await capture.stop() }
            else { _ = await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } } }
            capture = nil; self.mailbox = nil
            guard revision == token else { throw CancellationError() }
            next.takes[next.takes.count - 1].closed = true; next.phase = .paused
            if let saved = try? AVAudioFile(forReading: journal.audio(session: next.id, take: take.id)) {
                next.takes[next.takes.count - 1].frames = saved.length
            }
            record = next
            do { try journal.save(next) }
            catch { message = "تعذّر تحديث حالة التسميع. أعد محاولة الإنهاء." }
            throw error
        }
    }
    private func noteCapturedFrames(_ frames: Int64, session: UUID, take: UUID, token: UUID) {
        guard revision == token, capturing, var current = record, current.id == session,
              let index = current.takes.firstIndex(where: { $0.id == take }),
              !current.takes[index].closed, frames > current.takes[index].frames else { return }
        // Cold ASR preparation/backlog cannot freeze the visible capture time.
        // Disk closure still takes its authoritative final length from capture.
        current.takes[index].frames = frames
        record = current
    }
    private func processWindows(_ mailbox: QuranWindowMailbox, take: UUID, token: UUID) async {
        var prepared = false
        while revision == token, !Task.isCancelled {
            let pendingWindow: QuranAudioWindow?
            do { pendingWindow = try mailbox.take() }
            catch {
                guard var current = record else { return }
                current.recognitionUnavailable = true; noteExposedPracticeText(&current)
                record = current; uncertain = true; withdrawUnavailableTracking()
                do { try save(current) }
                catch { stopForJournalFailure(); return }
                message = "تأخر التتبع عن صوتك. أوقف التسميع ثم استأنفه لإعادة المحاولة."
                return
            }
            guard let window = pendingWindow else {
                if !capturing { return }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                continue
            }
            guard var next = record, let takeIndex = next.takes.firstIndex(where: { $0.id == take }) else { return }
            let span = OSSignpostID(log: Self.performanceLog)
            let feedbackID = UUID()
            trackingFeedbackID = feedbackID
            defer {
                if trackingFeedbackID == feedbackID { trackingFeedback = nil; trackingFeedbackID = nil }
            }
            os_signpost(.begin, log: Self.performanceLog, name: "Recitation window processing", signpostID: span)
            defer { os_signpost(.end, log: Self.performanceLog, name: "Recitation window processing", signpostID: span) }
            next.takes[takeIndex].frames = max(next.takes[takeIndex].frames, window.endFrame)
            record = next
            let recognized: QuranRecognitionWorker.Result
            do {
                let activity = await Task.detached(priority: .userInitiated) {
                    try? QuranVoiceActivity.scan(QuranRecognitionAudio.conditioned(window.samples))
                }.value
                guard revision == token, !Task.isCancelled else { return }
                if activity?.hasSpeech == false && worker.capabilities.processesLocally {
                    recognized = .noSpeechWindow()
                } else {
                if !prepared {
                    // Cold model loading has its own bounded deadline, after
                    // capture is already writing PCM. Do not charge model
                    // startup against the shorter per-window decode deadline.
                    trackingFeedback = .init(activity: .preparingModel, startedAt: ProcessInfo.processInfo.systemUptime)
                    try await NoorOperationDeadline.run(seconds: 45) { try await self.worker.prepare() }
                    guard revision == token, !Task.isCancelled else { return }
                    prepared = true
                }
                trackingFeedback = .init(activity: .recognizing, startedAt: ProcessInfo.processInfo.systemUptime)
                recognized = try await NoorOperationDeadline.run(seconds: recognitionTimeout) {
                    try await self.recognizeWindow(window)
                }
                }
            }
            catch is CancellationError { return }
            catch {
                guard revision == token, var current = record else { return }
                current.recognitionUnavailable = true; noteExposedPracticeText(&current)
                record = current; uncertain = true; withdrawUnavailableTracking()
                do { try save(current) }
                catch { stopForJournalFailure(); return }
                if (error as? URLError)?.code == .timedOut {
                    message = "تعذّر التتبع الآن. أوقف التسميع ثم أعد المحاولة؛ يمكنك متابعة قراءة المصحف."
                    // A Core ML call can ignore cancellation. Do not queue more
                    // recognition behind it or accept its eventual late result.
                    return
                }
                continue // Recording remains independent of model failure.
            }
            guard revision == token, !Task.isCancelled, var current = record, let inputTracker = tracker else { return }
            do {
                trackingFeedback = .init(activity: .locatingPassage, startedAt: ProcessInfo.processInfo.systemUptime)
                // Full-Quran candidate matching and ambiguity resolution must
                // not run on MainActor for every audio window. Work on a value
                // copy; only this still-current take may publish its result.
                let displayPolicy = practiceVisibility
                let displayLocation = listeningLocation
                let alignment = Task.detached(priority: .userInitiated) {
                    var nextTracker = inputTracker
                    try Task.checkCancellation()
                    try nextTracker.reconsiderAudio(takeID: take, start: window.offset,
                        end: Double(window.endFrame) / 16_000)
                    var additions: [QuranWordEvidence] = []
                    for run in recognized.runs {
                        try Task.checkCancellation()
                        additions += try nextTracker.consume(run, takeID: take, offset: window.offset)
                    }
                    // Long-session evidence can contain many repeated takes.
                    // Reduce that history off the UI actor as well as matching.
                    let visible = displayPolicy.newlyShownVerses(evidence: nextTracker.evidence)
                    let revealed = nextTracker.revealedIDs
                    let matched = nextTracker.evidence.contains {
                        $0.takeID == take && $0.start >= window.offset && $0.end <= Double(window.endFrame) / 16_000
                    }
                    var nextLocation = displayLocation
                    nextLocation.update(nextTracker.evidence, matchingCurrentWindow: matched)
                    try Task.checkCancellation()
                    return (nextTracker, additions, visible, revealed, matched, nextLocation)
                }
                let (updatedTracker, additions, completedVerses, recognizedIDs, matchedThisWindow, updatedLocation) = try await withTaskCancellationHandler(
                    operation: { try await alignment.value }, onCancel: { alignment.cancel() })
                guard revision == token, !Task.isCancelled else { return }
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
                    observed.processingConfiguration = recognized.processingConfiguration
                    observed.independentRecognition = recognized.independentRecognition
                }
                var spans = current.observedSpeech ?? []
                // Keep recognizer revisions as source evidence. Assessment can
                // supersede an interpretation without erasing what it decoded.
                if spans.last != observed { spans.append(observed) }
                let assessmentInput = Array(spans.suffix(16))
                let referenceWords = updatedTracker.expected
                let priorEvents = current.wordingEvents ?? []
                // Assessment must know when previously shown/retracted text
                // assisted a later attempt; visibility is never mastery.
                retainShownText(&current,completed:completedVerses,recognizedIDs:recognizedIDs)
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
                // If an interpretation is later retracted, its text can stay
                // visible without becoming permanent correctness evidence.
                retainShownText(&current,completed:completedVerses,recognizedIDs:recognizedIDs)
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
                revealed = recognizedIDs
                listeningLocation = updatedLocation
                if let located = listeningLocation.verse { currentVerse = located }
                activeWordID = listeningLocation.activeNativeID
                uncertain = additions.isEmpty || recognized.hasUnresolvedSpeech || activeWordID == nil
                if recognized.runs.isEmpty {
                    trackingUncertainty = recognized.hasUnresolvedSpeech ? .unreliableWords : .noSpeech
                } else if !matchedThisWindow || activeWordID == nil { trackingUncertainty = .passageUnclear }
                else { trackingUncertainty = recognized.hasUnresolvedSpeech ? .unreliableWords : .none }
            } catch is CancellationError { return }
            catch { guard revision == token else { return }; stopForJournalFailure(); return }

        }
    }
    private func withdrawUnavailableTracking() {
        // Prior accepted words and shown ayahs remain part of this session,
        // but an unavailable recognizer cannot claim one is being heard now.
        recognitionAvailable = false
        listeningLocation.update([], matchingCurrentWindow: false)
        activeWordID = nil
    }
    private func stopForJournalFailure() {
        message = "تعذّر تحديث التتبع. توقف الميكروفون؛ أعد المحاولة داخل المصحف."
        // Do not await this from the inference task: pause drains that task.
        Task { [weak self] in await self?.pause() }
    }
    func pause() async {
        guard !closing else { return }
        if state == .permission || state == .preparing {
            revision = UUID()
            closing = true; state = .processing
            defer { closing = false }
            // Hardware startup is asynchronous. Drain its serial lane before
            // closing the take; never leave a late microphone running.
            if let captureStart { _ = try? await captureStart.value }
            var closedFrames: Int64?
            if let capture {
                if case .success(let frames) = await capture.stop() { closedFrames = frames }
                self.capture = nil
            }
            capturing = false
            if var current = record, !current.takes.isEmpty {
                if closedFrames == nil, let journal,
                   let file = try? AVAudioFile(forReading: journal.audio(session: current.id, take: current.takes.last!.id)) {
                    closedFrames = file.length
                }
                if let closedFrames { current.takes[current.takes.count - 1].frames = closedFrames }
                current.takes[current.takes.count - 1].closed = true
                current.phase = .paused; record = current
                try? save(current)
            }
            if let lease = audioFocusLease {
                try? setSessionActive(false)
                NoorAudioFocus.shared.releaseRecording(lease); audioFocusLease = nil
            }
            state = record == nil ? .idle : .paused; return
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
                    message = "توقف الميكروفون بسبب مشكلة في معالجة الصوت. أعد المحاولة داخل المصحف."
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
        try? await NoorOperationDeadline.run(seconds: 3) { await self.worker.endTake() }
        if var current = record {
            current.phase = finishRequest ? .finished : .paused
            current.finishedAt = finishRequest ? Date() : nil
            do { try save(current); record = current; state = finishRequest ? .stopped : .paused }
            catch { record = current; state = .paused; message = "تعذّر تحديث حالة التسميع. أعد محاولة الإنهاء." }
        }
        closing = false
        try? setSessionActive(false)
        if let lease = audioFocusLease { NoorAudioFocus.shared.releaseRecording(lease) }
        audioFocusLease = nil
        if finishRequest { await discardWorkingSession() }
    }
    func finish() async {
        cancelGuided()
        finishRequest = true
        if state == .listening { await pause(); return }
        // Cancel permission/model continuations before disposing working files.
        guard !closing else { return }
        await discardWorkingSession()
    }
    private func discardWorkingSession() async {
        closing = true; defer { closing = false }
        state = .processing
        revision = UUID(); pump?.cancel(); pump = nil; mailbox = nil
        if let captureStart { _ = try? await captureStart.value }
        if let capture { _ = await capture.stop(); self.capture = nil }
        capturing = false
        if let lease = audioFocusLease {
            try? setSessionActive(false)
            NoorAudioFocus.shared.releaseRecording(lease); audioFocusLease = nil
        }
        guard var current = record else { state = .idle; return }
        current.phase = .finished; current.finishedAt = Date()
        record = current
        let sessionID = current.id
        do {
            guard let journal else { throw QuranJournalFailure.invalidRecord }
            try await Task.detached(priority: .utility) { try journal.discard(sessionID) }.value
            state = .stopped
        } catch { state = .paused; message = "تعذّر حذف ملفات التسميع المؤقتة. أعد محاولة الإنهاء بعد فتح قفل الجهاز." }
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

