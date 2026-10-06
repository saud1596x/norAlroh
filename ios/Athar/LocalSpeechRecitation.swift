import Foundation
import AVFoundation
import Combine
import UIKit
import WhisperKit

@MainActor final class LocalSpeechRecitation: ObservableObject {
    static let model = "large-v3-v20240930_626MB"
    @Published private(set) var preparing = false
    @Published private(set) var deleting = false
    @Published private(set) var ready = false
    @Published private(set) var listening = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var settling = false
    @Published private(set) var transcript = ""
    @Published private(set) var anchor = 0
    @Published private(set) var comparison: RecitationComparison?
    @Published private(set) var status = "جهّز النموذج قبل بدء المتابعة الصوتية."
    @Published var message: String?
    private var activeWords: [RecitationExpectedWord] = []
    private var pipeline: WhisperKit?
    private var preparingTask: Task<Void, Never>?
    private var inferenceTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var buffer = RecitationAudioBuffer()
    private var revision = 0
    private let defaults = UserDefaults.standard
    private let folderKey = "noor.speechModelFolder.v1"
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
            defer { preparing = false }
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                var folder = cache; var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
                let saved = defaults.string(forKey: folderKey)
                let local = saved.flatMap { path -> String? in
                    guard path.hasPrefix(cache.path + "/"), FileManager.default.fileExists(atPath: path) else { return nil }; return path
                }
                guard local != nil || downloadAllowed else { throw CocoaError(.fileReadNoSuchFile) }
                status = local == nil ? "تنزيل النموذج متعدد اللغات وتجهيزه…" : "تحميل النموذج المحلي…"
                let config = WhisperKitConfig(model: Self.model, downloadBase: cache, modelRepo: "argmaxinc/whisperkit-coreml",
                    modelFolder: local, tokenizerFolder: cache.appendingPathComponent("Tokenizers"), verbose: false,
                    prewarm: true, load: true, download: local == nil)
                let loaded = try await WhisperKit(config)
                try Task.checkCancellation()
                if let folder = loaded.modelFolder, folder.path.hasPrefix(cache.path + "/") { defaults.set(folder.path, forKey: folderKey) }
                pipeline = loaded; ready = true; status = "النموذج جاهز؛ معالجة الصوت على جهازك."
            } catch {
                ready = false; status = "تعذّر تجهيز النموذج. يمكنك إعادة المحاولة."
                if !Task.isCancelled { message = "لم يكتمل التنزيل أو التحميل. تحقق من الاتصال والمساحة المتاحة وأعد المحاولة." }
            }
        }
    }
    func start(expected: [RecitationExpectedWord], recorder: LocalRecitationRecorder) async {
        guard ready, !listening, !requestingPermission, !deleting, !expected.isEmpty, let pipeline else { return }
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
        activeWords = expected
        recorder.stop(); buffer.erase(); buffer = RecitationAudioBuffer(); transcript = ""; comparison = nil; anchor = 0
        do {
            let capture = buffer
            try pipeline.audioProcessor.startRecordingLive(inputDeviceID: nil) { samples in capture.append(samples) }
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
                        let samples = buffer.snapshot()
                        guard samples.count >= 16000 * 2 else { continue }
                        let tail = samples.suffix(16000 * 2)
                        let energy = tail.reduce(0.0) { $0 + Double($1 * $1) } / Double(tail.count)
                        guard energy > 0.00001 else { status = "بانتظار صوت واضح…"; continue }
                        let options = DecodingOptions(verbose: false, task: .transcribe, language: "ar", temperature: 0,
                            temperatureFallbackCount: 0, usePrefillPrompt: true, skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true)
                        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
                        guard generation == revision, listening, !Task.isCancelled else { return }
                        let segments = results.flatMap(\.segments)
                        guard !segments.isEmpty, segments.allSatisfy({ $0.avgLogprob >= -1 && $0.noSpeechProb < 0.6 }) else {
                            status = "التعرّف غير مؤكّد. أعد المقطع بصوت واضح."; comparison = nil; continue
                        }
                        transcript = results.map(\.text).joined(separator: " ")
                        let next = RecitationComparison.align(expected: expected, heard: transcript, anchor: anchor)
                        comparison = next
                        if next.reliableAlignment {
                            anchor = max(anchor, next.endIndex)
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
        let samples = wasListening && !clear ? buffer.snapshot() : []
        let expected = activeWords
        revision += 1; inferenceTask?.cancel()
        let pending = inferenceTask, generation = revision, model = pipeline
        durationTask?.cancel(); durationTask = nil
        pipeline?.audioProcessor.stopRecording(); pipeline?.audioProcessor.purgeAudioSamples(keepingLast: 0)
        listening = false; buffer.erase()
        if wasListening { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        if clear { transcript = ""; comparison = nil; anchor = 0; activeWords = [] }
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
                let result = RecitationComparison.align(expected: expected, heard: transcript, anchor: 0)
                comparison = result
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
            defaults.removeObject(forKey: folderKey); status = "حُذف النموذج المحلي وبيانات المتابعة."; return true
        } catch { message = "تعذّر حذف ملفات النموذج. حاول مجددًا."; return false }
    }
}
