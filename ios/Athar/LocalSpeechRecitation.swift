import Foundation
import AVFoundation
import Combine
import UIKit
import WhisperKit

@MainActor final class LocalSpeechRecitation: ObservableObject {
    static let model = "large-v3-v20240930_626MB"
    @Published private(set) var preparing = false
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var deleting = false
    @Published private(set) var ready = false
    @Published private(set) var listening = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var settling = false
    @Published private(set) var transcript = ""
    @Published private(set) var anchor = 0 { didSet { persistPosition() } }
    @Published private(set) var savedPosition: SpeechSessionPosition?
    @Published private(set) var observations: [RecitationObservation] = []
    private var ledger = RecitationObservationLedger()
    @Published private(set) var comparison: RecitationComparison?
    @Published private(set) var status = "جهّز النموذج قبل بدء المتابعة الصوتية."
    @Published var message: String?
    private var activeWords: [RecitationExpectedWord] = []
    private let positions: SpeechPositionStore
    var unreadablePosition: Data? { positions.unreadable }
    var previousPosition: Data? { defaults.data(forKey: "noor.speech.previousPosition.v1") }
    private var usedHelp = false
    private var pipeline: WhisperKit?
    private var preparingTask: Task<Void, Never>?
    private var inferenceTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var buffer = RecitationAudioBuffer()
    private var revision = 0
    private let defaults = UserDefaults.standard
    private let folderKey = "noor.speechModelFolder.v1"
    init() {
        positions = SpeechPositionStore(); savedPosition = positions.value
    }
    func dismissObservation(_ index: Int) { ledger.dismiss(index); observations = ledger.ordered }
    private func collect(_ result: RecitationComparison) {
        ledger.ingest(result, expected: activeWords, at: Date()); observations = ledger.ordered
    }
    func markHelpUsed() { usedHelp = true; persistPosition() }
    private func persistPosition() {
        guard let value = SpeechSessionPosition.make(words: activeWords, nextWord: anchor, usedHelp: usedHelp) else { return }
        if positions.save(value) { savedPosition = value }
        else { message = "تعذّر حفظ موضع التسميع. احتُفظ ببيانات الجلسة السابقة دون استبدال." }
    }
    func eraseSavedPosition() { stop(clear: true); positions.erase(); savedPosition = nil; usedHelp = false }
    private var cache: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NoorSpeech", isDirectory: true)
    }
    func prepareLocalIfAvailable() {
        guard let path = defaults.string(forKey: folderKey), let cache, path.hasPrefix(cache.path + "/"), FileManager.default.fileExists(atPath: path) else { return }
        prepare(downloadAllowed: false)
    }
    func prepare(downloadAllowed: Bool = true) {
        guard !preparing, !deleting, !ready, let cache else { return }
        preparing = true
        preparingTask = Task { [weak self] in
            guard let self else { return }
            defer { preparing = false; downloadProgress = nil }
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                var folder = cache; var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
                let saved = defaults.string(forKey: folderKey)
                let local = saved.flatMap { path -> String? in
                    guard path.hasPrefix(cache.path + "/"), FileManager.default.fileExists(atPath: path) else { return nil }; return path
                }
                guard local != nil || downloadAllowed else { throw CocoaError(.fileReadNoSuchFile) }
                status = local == nil ? "تنزيل النموذج متعدد اللغات وتجهيزه…" : "تحميل النموذج المحلي…"
                var selectedFolder = local
                downloadProgress = nil
                if selectedFolder == nil {
                    let free = try NoorAudioIntegrity.availableCapacity(at: cache)
                    guard free >= 1_500_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                    let downloaded = try await WhisperKit.download(variant: Self.model, downloadBase: cache) { [weak self] progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in guard let self, self.preparing else { return }; self.downloadProgress = min(1, max(0, fraction)) }
                    }
                    try Task.checkCancellation(); selectedFolder = downloaded.path
                }
                downloadProgress = nil; status = "التحقق من النموذج وتحميله…"
                let config = WhisperKitConfig(model: Self.model, downloadBase: cache, modelRepo: "argmaxinc/whisperkit-coreml",
                    modelFolder: selectedFolder, tokenizerFolder: cache.appendingPathComponent("Tokenizers"), verbose: false,
                    prewarm: true, load: true, download: false)
                let loaded = try await WhisperKit(config)
                try Task.checkCancellation()
                if let folder = loaded.modelFolder, folder.path.hasPrefix(cache.path + "/") { defaults.set(folder.path, forKey: folderKey) }
                pipeline = loaded; ready = true; status = "النموذج جاهز؛ معالجة الصوت على جهازك."
            } catch {
                ready = false; status = "تعذّر تجهيز النموذج. يمكنك إعادة المحاولة."
                if Task.isCancelled { status = "أُوقف تجهيز النموذج. أعد المحاولة لاستكمال الملفات المتاحة." }
                else { message = "لم يكتمل التنزيل أو التحميل. تحقق من الاتصال والمساحة المتاحة وأعد المحاولة." }
            }
        }
    }
    func cancelPreparation() { guard preparing else { return }; preparingTask?.cancel(); status = "إيقاف تجهيز النموذج…" }
    func start(expected: [RecitationExpectedWord], recorder: LocalRecitationRecorder, resumeAt: Int = 0, helped: Bool = false) async {
        guard ready, !listening, !requestingPermission, !deleting, !expected.isEmpty, let pipeline else { return }
        guard expected.count <= 1500, (0...expected.count).contains(resumeAt), positions.unreadable == nil else {
            message = positions.unreadable == nil ? "اختر نطاقًا أقصر للتسميع على هذا الجهاز." : "تعذّر فتح موضع التسميع السابق. صدّر بياناتك قبل بدء جلسة جديدة."; return
        }
        let waitingRevision = revision
        requestingPermission = true
        defer { requestingPermission = false }
        // A cancelled Core ML decode can take time to return. Never reuse or unload
        // that model while its previous transcribe call is still running.
        await inferenceTask?.value
        guard waitingRevision == revision, !deleting else { return }
        revision += 1
        let attempt = revision
        inferenceTask = nil; settling = false
        let granted = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard attempt == revision, UIApplication.shared.applicationState == .active else { return }
        guard granted else { message = "اسمح بالميكروفون من إعدادات iOS للمتابعة الصوتية. القراءة والمراجعة اليدوية متاحتان."; return }
        let continuing = resumeAt > 0 && SpeechSessionPosition.digest(activeWords) == SpeechSessionPosition.digest(expected)
        activeWords = expected; usedHelp = helped
        recorder.stop(); buffer.erase(); buffer = RecitationAudioBuffer(); transcript = ""; comparison = nil
        if !continuing { ledger = RecitationObservationLedger(); observations = [] }
        anchor = resumeAt
        do {
            let capture = buffer
            guard let processor = pipeline.audioProcessor as? AudioProcessor else { throw CocoaError(.featureUnsupported) }
            try processor.startRecordingLive(inputDeviceID: nil) { [weak processor] samples in
                capture.append(samples)
                // WhisperKit 1.1.0 invokes this on its capture processing queue.
                // Bound its duplicate storage on that same queue, not during a decode.
                processor?.purgeAudioSamples(keepingLast: 2 * 16000)
                if let processor, processor.audioEnergy.count > 20 {
                    processor.audioEnergy.removeFirst(processor.audioEnergy.count - 20)
                }
            }
            listening = true; status = "استمع لتسميعك وأقارن الكلمات محليًا…"
            let generation = revision, began = Date()
            durationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard let self, generation == revision, listening else { return }
                    if Date().timeIntervalSince(began) >= 300 { stop(); status = "توقفت الجلسة بعد خمس دقائق."; return }
                }
            }
            inferenceTask = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled && generation == revision && listening {
                        try await Task.sleep(nanoseconds: 2_500_000_000)
                        if Date().timeIntervalSince(began) >= 300 { stop(); status = "توقفت الجلسة بعد خمس دقائق."; return }
                        guard let window = buffer.nextWindow() else { continue }
                        if window.lostSamples > 0 {
                            stop(clear: true)
                            message = "لم يستطع الجهاز متابعة الصوت بالسرعة المطلوبة. أعد المقطع بعد إيقاف التطبيقات الثقيلة."
                            return
                        }
                        let samples = window.samples
                        let energy = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
                        guard energy > 0.00001 else {
                            buffer.consume(through: window.end)
                            status = "بانتظار صوت واضح…"; continue
                        }
                        let options = DecodingOptions(verbose: false, task: .transcribe, language: "ar", temperature: 0,
                            temperatureFallbackCount: 0, usePrefillPrompt: true, skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true)
                        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
                        guard generation == revision, listening, !Task.isCancelled else { return }
                        buffer.consume(through: window.end)
                        let segments = results.flatMap(\.segments)
                        guard !segments.isEmpty, segments.allSatisfy({ $0.avgLogprob >= -1 && $0.noSpeechProb < 0.6 }) else {
                            status = "التعرّف غير مؤكّد. أعد المقطع بصوت واضح."; comparison = nil; continue
                        }
                        transcript = results.map(\.text).joined(separator: " ")
                        let next = RecitationComparison.align(expected: expected, heard: transcript, anchor: anchor)
                        comparison = next; collect(next)
                        if next.reliableAlignment {
                            anchor = next.endIndex
                            status = next.possibleDifferences.isEmpty ? "تطابقت كلمات المقطع المسموع." : "ظهرت فروق محتملة؛ راجع المسموع مع النص."
                        } else { status = "لم أتمكن من مطابقة المقطع بثقة. أعده من بداية الآية." }
                    }
                } catch {
                    guard generation == revision else { return }
                    let cancelled = Task.isCancelled
                    stop(); if !cancelled { message = "تعذرت معالجة الصوت. أعد بدء المتابعة." }
                }
            }
        } catch { stop(); message = "تعذر تشغيل الميكروفون للمتابعة الصوتية." }
    }
    func stop(clear: Bool = false) {
        let wasListening = listening
        let samples = wasListening && !clear
            ? (buffer.nextWindow(minimumNewSamples: 16000, maximumSamples: 30 * 16000)?.samples ?? []) : []
        let finalAnchor = anchor
        let expected = activeWords
        revision += 1; inferenceTask?.cancel()
        let pending = inferenceTask, generation = revision, model = pipeline
        durationTask?.cancel(); durationTask = nil
        pipeline?.audioProcessor.stopRecording(); pipeline?.audioProcessor.purgeAudioSamples(keepingLast: 0)
        listening = false; buffer.erase()
        if wasListening { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        if clear { activeWords = []; transcript = ""; comparison = nil; anchor = 0; ledger = RecitationObservationLedger(); observations = [] }
        guard pending != nil || !samples.isEmpty else { settling = false; return }
        settling = true
        if !samples.isEmpty { status = "أراجع نهاية المقطع…" }
        inferenceTask = Task { [weak self] in
            await pending?.value
            guard let self, generation == revision, !Task.isCancelled else { return }
            defer { if generation == revision { inferenceTask = nil; settling = false } }
            guard !samples.isEmpty, samples.count >= 16000, let model else { return }
            do {
                let options = DecodingOptions(verbose: false, task: .transcribe, language: "ar", temperature: 0,
                    temperatureFallbackCount: 0, usePrefillPrompt: true, skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true)
                let results = try await model.transcribe(audioArray: samples, decodeOptions: options)
                guard generation == revision, !Task.isCancelled else { return }
                let segments = results.flatMap(\.segments)
                guard !segments.isEmpty, segments.allSatisfy({ $0.avgLogprob >= -1 && $0.noSpeechProb < 0.6 }) else {
                    status = "لم تتضح نهاية المقطع. أعد الآية بهدوء."; return
                }
                transcript = results.map(\.text).joined(separator: " ")
                let result = RecitationComparison.align(expected: expected, heard: transcript, anchor: finalAnchor)
                comparison = result; collect(result)
                if result.reliableAlignment { anchor = result.endIndex }
                status = result.reliableAlignment ? "انتهى التسميع؛ راجع النتيجة واحفظ تقييم الآية." : "راجع المقطع بنفسك أو أعد تسميع الآية."
            } catch { if generation == revision { status = "تعذّر تحليل نهاية المقطع. يمكنك إعادة التسميع." } }
        }
    }
    @discardableResult func eraseModel() async -> Bool {
        guard !deleting else { return false }
        deleting = true; defer { deleting = false }
        let pending = inferenceTask
        stop(clear: true); preparingTask?.cancel(); await preparingTask?.value
        await pending?.value
        inferenceTask = nil; settling = false
        if let pipeline { await pipeline.unloadModels() }
        self.pipeline = nil; ready = false
        do {
            if let cache, FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
            defaults.removeObject(forKey: folderKey); status = "حُذف النموذج المحلي؛ موضع جلسة التسميع محفوظ."; return true
        } catch { message = "تعذّر حذف ملفات النموذج. حاول مجددًا."; return false }
    }
}
