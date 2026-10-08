import Foundation
import AVFoundation
import Combine

@MainActor final class QuranRecitationController: ObservableObject {
    enum State { case idle, permission, preparing, listening, paused, processing, stopped }
    @Published private(set) var state = State.idle
    @Published private(set) var record: QuranRecitationRecord?
    @Published private(set) var revealed = Set<Int>()
    @Published private(set) var currentVerse: String?
    @Published private(set) var uncertain = false
    @Published private(set) var permissionDenied = false
    @Published var message: String?
    private let worker = QuranRecognitionWorker()
    private var capture: QuranMicrophoneCapture?
    private var mailbox: QuranWindowMailbox?
    private var pump: Task<Void, Never>?
    private var capturing = false
    private var tracker: QuranRecitationTracker?
    private var words: [QuranAlignedWord] = []
    private var revision = UUID()
    private var finishRequest = false
    private var closing = false
    private var journal: QuranRecitationJournal? {
        (try? MushafRecordingArchive.root()).map(QuranRecitationJournal.init(root:))
    }
    private func save(_ value: QuranRecitationRecord) throws {
        guard let journal else { throw QuranJournalFailure.invalidRecord }
        try journal.save(value)
    }
    var hasSession: Bool { record != nil && state != .stopped && state != .idle }
    var hiddenIDs: Set<Int> {
        guard hasSession else { return [] }
        return Set(tracker?.expected.map(\.id) ?? []).subtracting(revealed)
    }
    var status: String {
        switch state {
        case .idle: return "ابدأ التسميع"
        case .permission: return "إذن الميكروفون"
        case .preparing: return "تهيئة التسميع"
        case .listening:
            if record?.recognitionUnavailable == true { return "التسجيل مستمر · التتبع متعذر" }
            return uncertain ? "أستمع · أنتظر وضوح الموضع" : "أستمع إليك"
        case .paused: return "متوقف مؤقتًا"
        case .processing: return "حفظ الجلسة ومعالجة التلاوة"
        case .stopped: return "انتهت الجلسة"
        }
    }
    func start(keys: [String], page: Int, snapshot: QCFV2Snapshot, corpus: [Surah]) async {
        guard state == .idle || state == .stopped else { return }
        let token = UUID(); revision = token; message = nil; permissionDenied = false
        record = nil; tracker = nil; revealed = []; currentVerse = nil
        state = .permission
        guard await AVAudioApplication.requestRecordPermission() else {
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
            try bind(snapshot: snapshot, corpus: corpus)
            try await worker.prepare()
            guard revision == token, state == .preparing else { return }
            let scope = Set(keys)
            tracker = QuranRecitationTracker(expected: words.filter { scope.contains($0.verse) })
            revealed = []; currentVerse = keys.first; uncertain = false; finishRequest = false
            let next = QuranRecitationRecord(keys: keys, originPage: page)
            try journal.create(next); record = next
            try await beginTake(token: token)
        } catch {
            guard revision == token else { return }
            state = record == nil ? .idle : .paused
            message = "تعذّر تجهيز التسميع. لم يبدأ الميكروفون؛ تحقق من المساحة المتاحة ثم أعد المحاولة."
        }
    }
    private func bind(snapshot: QCFV2Snapshot, corpus: [Surah]) throws {
        guard words.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "recitation-word-script", withExtension: "json") else {
            throw QuranAlignmentFailure.invalidScript
        }
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: url))
        let verseKeys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let native = try snapshot.validated().records.filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }
            .map { QuranNativeWord(id: $0.id, verse: verseKeys[$0.verse_id! - 1],
                position: $0.position_in_verse!, page: $0.page_number!, glyph: $0.text!) }
        words = try script.bind(native: native, verseKeys: verseKeys)
    }
    func restore(id: UUID, snapshot: QCFV2Snapshot, corpus: [Surah]) {
        guard state == .idle || state == .stopped else { return }
        do {
            guard let journal else { throw QuranJournalFailure.invalidRecord }
            var restored = try journal.load(id)
            guard restored.phase != .finished,
                  MushafStudySession(keys: restored.keys, scope: .range, page: restored.originPage).valid(corpus: corpus) else {
                throw QuranJournalFailure.invalidRecord
            }
            try bind(snapshot: snapshot, corpus: corpus)
            for index in restored.takes.indices {
                let take = restored.takes[index]
                let url = journal.audio(session: restored.id, take: take.id)
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
            currentVerse = restored.evidence.last?.verse ?? restored.keys.first
            finishRequest = false; revision = UUID(); uncertain = restored.recognitionUnavailable; state = .paused
        } catch { message = "تعذّر استعادة الجلسة. لم تُحذف ملفات الصوت أو بياناتها؛ يمكنك فتح التسجيلات لفحص المتاح." }
    }
    func resume() async {
        guard state == .paused, !closing, record != nil else { return }
        permissionDenied = false; state = .permission
        let token = revision
        guard await AVAudioApplication.requestRecordPermission() else {
            guard revision == token else { return }
            state = .paused; permissionDenied = true; message = "الميكروفون غير مسموح. تقدمك وتسجيلاتك محفوظة."; return
        }
        guard revision == token, state == .permission else { return }
        do {
            state = .preparing
            try await worker.prepare()
            guard revision == token, state == .preparing else { return }
            try await beginTake(token: token)
        }
        catch { state = .paused; message = "تعذّر استئناف الميكروفون. احتُفظ بالتسجيل السابق." }
    }
    private func beginTake(token: UUID) async throws {
        guard var next = record, let journal else { throw QuranJournalFailure.invalidRecord }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audio.setActive(true)
        var started = false
        defer { if !started { try? audio.setActive(false, options: .notifyOthersOnDeactivation) } }
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
            let microphone = try QuranMicrophoneCapture(writer: writer, onFailure: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.revision == token else { return }
                    self.message = "انقطع إدخال الصوت. احتُفظ بالتسجيل؛ استأنف عندما يصبح الميكروفون متاحًا."
                    await self.pause()
                }
            })
            capture = microphone; self.mailbox = mailbox; capturing = true
            try microphone.start(); started = true; state = .listening
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
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
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
            next.takes[takeIndex].frames = max(next.takes[takeIndex].frames, window.endFrame)
            record = next
            let recognized: QuranRecognitionWorker.Result
            do { recognized = try await worker.recognize(window) }
            catch is CancellationError { return }
            catch {
                guard revision == token, var current = record else { return }
                current.recognitionUnavailable = true; record = current; uncertain = true
                do { try save(current) }
                catch { stopForJournalFailure(); return }
                continue // Recording remains independent of model failure.
            }
            guard revision == token, !Task.isCancelled, var current = record, var updatedTracker = tracker else { return }
            do {
                var additions: [QuranWordEvidence] = []
                for run in recognized.runs {
                    additions += try updatedTracker.consume(run, takeID: take, offset: window.offset)
                }
                current.evidence += additions; current.recognitionUnavailable = false
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
        let deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            pending?.cancel()
            if var current = self?.record { current.recognitionUnavailable = true; self?.record = current }
        }
        await pending?.value; deadline.cancel(); pump = nil; mailbox = nil
        if var current = record {
            current.phase = finishRequest ? .finished : .paused
            current.finishedAt = finishRequest ? Date() : nil
            do { try save(current); record = current; state = finishRequest ? .stopped : .paused }
            catch { record = current; state = .paused; message = "الصوت محفوظ، لكن تعذّر حفظ ملخص الجلسة. أعد محاولة الإنهاء." }
        }
        closing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
