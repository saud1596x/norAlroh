import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

final class QuranLiveRecitationStorageTests: XCTestCase {
    @MainActor func testCapturedTimeUsesWrittenPCMWhileRecognitionPreparationIsBlocked() async throws {
        // Real bundled PCM, injected capture/preparation barrier: this proves
        // capture-clock ordering, not real microphone or ASR quality.
        func stage(_ name: String) {
            NSLog("NOOR_CAPTURE_CLOCK_TEST %@ uptime=%.3f", name, ProcessInfo.processInfo.systemUptime)
        }
        stage("pcm.load.begin")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "001002", withExtension: "mp3"))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: source.path)
        stage("pcm.load.end")
        XCTAssertGreaterThan(samples.count, 80_000)
        let gate = CaptureStartGate()
        var capture: ReferenceCapture?
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognitionProvider: PreparationBarrierProvider(gate: gate),
            makeCapture: { writer, _ in
                let value = ReferenceCapture(writer: writer, samples: Array(samples.prefix(32_000)))
                capture = value; return value
            }, setSessionActive: { _ in })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        stage("capture.start.begin")
        await controller.start(keys: ["1:2"], page: 1, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        stage("capture.start.end")
        let openingDeadline = Date().addingTimeInterval(8)
        while !(await gate.waiting) && Date() < openingDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let waiting = await gate.waiting
        stage(waiting ? "preparation.barrier.entered" : "preparation.barrier.not-entered")
        guard waiting, let capture else {
            await gate.release(); await controller.finish()
            XCTFail("Injected recognition preparation did not reach its barrier"); return
        }
        for start in stride(from: 32_000, to: samples.count, by: 32_000) {
            capture.writer.append(Array(samples[start..<min(start + 32_000, samples.count)]))
        }
        let captureDeadline = Date().addingTimeInterval(8)
        while (controller.record?.takes.last?.frames ?? 0) < Int64(samples.count) && Date() < captureDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.record?.takes.last?.frames, Int64(samples.count),
                       "Cold recognition must not freeze capture time at its first pending window")
        let capturedSeconds = controller.record?.duration
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.record?.duration, capturedSeconds, "No new PCM means no invented elapsed capture time")
        XCTAssertTrue(controller.revealed.isEmpty)
        XCTAssertTrue(controller.record?.evidence.isEmpty == true)
        XCTAssertNil(controller.activeWordID, "Capture duration cannot invent recognized words")
        stage("captured.frames.checked")
        await gate.release()
        stage("capture.pause.begin")
        await controller.pause()
        stage("capture.pause.end")
        let record = try XCTUnwrap(controller.record), take = try XCTUnwrap(record.takes.last)
        let file = try AVAudioFile(forReading: QuranRecitationJournal(root: root).audio(session: record.id, take: take.id))
        XCTAssertEqual(file.length, Int64(samples.count))
        XCTAssertEqual(take.frames, file.length)
        await controller.finish()
        stage("capture.finish.end")
    }

    private struct PreparationBarrierProvider: QuranSpeechRecognitionProvider {
        let gate: CaptureStartGate
        var capabilities: QuranRecognitionCapabilities {
            .init(backendID: "capture-clock-fixture", modelID: "no-acoustic-recognition", modelRevision: "1",
                  configuredLanguage: "ar", delivery: .overlappingAudioWindows, processesLocally: true,
                  wordTimestamps: false, wordConfidence: false, phonemeEvidence: false,
                  calibratedWordingAssessment: false, validatedTajweedAssessment: false)
        }
        func prepare() async throws { await gate.wait() }
        func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
            .init(runs: [], hasUnresolvedSpeech: true)
        }
    }

    @MainActor func testFinishWhileHardwareStartsDrainsWithoutLateListeningOrRecreatedFiles() async throws {
        // Injected startup barrier only: verifies cancellation ordering and UI
        // responsiveness, not a real hardware or acoustic recognition result.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = CaptureStartGate()
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            makeCapture: { writer, _ in DelayedCapture(writer: writer, gate: gate) }, setSessionActive: { _ in })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let starting = Task { await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus) }
        let deadline = Date().addingTimeInterval(8)
        while !(await gate.waiting) && Date() < deadline { await Task.yield() }
        let waiting = await gate.waiting
        guard waiting, let session = controller.record?.id else {
            // Even a failing startup assertion must release its delayed task.
            // Throwing XCTUnwrap here used to leak the capture/focus lease into
            // later cases and turn one failure into many unrelated failures.
            await gate.release(); await controller.finish(); await starting.value
            XCTFail("Injected hardware start did not reach its barrier within the unchanged 8s deadline")
            return
        }
        let finishing = Task { await controller.finish() }
        while controller.state != .processing && Date() < deadline { await Task.yield() }
        XCTAssertEqual(controller.state, .processing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: QuranRecitationJournal(root: root).folder(session).path),
                      "Do not delete working audio while its hardware start is outstanding")
        await gate.release()
        await starting.value; await finishing.value
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: QuranRecitationJournal(root: root).folder(session).path))
        await Task.yield(); XCTAssertNotEqual(controller.state, .listening)
        XCTAssertTrue(controller.revealed.isEmpty)
    }

    private actor CaptureStartGate {
        private var reply: CheckedContinuation<Void, Never>?
        private var released = false
        private(set) var waiting = false
        func wait() async {
            waiting = true
            guard !released else { return }
            await withCheckedContinuation { reply = $0 }
        }
        func release() { released = true; reply?.resume(); reply = nil }
    }
    func testHardwareStartGateCanBeReleasedBeforeTheDelayedTaskEntersIt() async throws {
        let gate = CaptureStartGate()
        await gate.release()
        try await NoorOperationDeadline.run(seconds: 2) { await gate.wait() }
        let entered = await gate.waiting
        XCTAssertTrue(entered, "Failure cleanup must not lose a release that precedes task startup")
    }
    private final class DelayedCapture: QuranAudioCapture {
        private let writer: QuranPCMWriter
        private let gate: CaptureStartGate
        init(writer: QuranPCMWriter, gate: CaptureStartGate) { self.writer = writer; self.gate = gate }
        func start() async throws { await gate.wait() }
        func stop() async -> Result<Int64, Error> {
            await withCheckedContinuation { reply in writer.finish { reply.resume(returning: $0) } }
        }
    }

    @MainActor func testSilentInputWindowsRemainValidAcrossPauseResumeWithoutPreparingASROrInventingWords() async throws {
        // Explicit digital-silence negative control; not a physical microphone
        // or natural-learner accuracy claim. The actual UI suite covers input.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        var decodeCalls = 0
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognizeWindow: { _ in decodeCalls += 1; return .init(runs: [], hasUnresolvedSpeech: false) },
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: Array(repeating: 0, count: 32_000)) },
            setSessionActive: { _ in })
        let corpus = try XCTUnwrap(QuranResources.corpus)
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus)
        try await waitForSpans(controller, count: 1)
        XCTAssertEqual(controller.state, .listening)
        XCTAssertNil(controller.message)
        await controller.pause(); XCTAssertEqual(controller.state, .paused)
        await controller.resume()
        try await waitForSpans(controller, count: 2)
        XCTAssertEqual(controller.state, .listening)
        let record = try XCTUnwrap(controller.record)
        let saved = try QuranRecitationJournal(root: root).load(record.id)
        let spans = try XCTUnwrap(saved.observedSpeech)
        XCTAssertEqual(Set(spans.compactMap(\.recognitionWindowID)).count, spans.count)
        XCTAssertTrue(spans.allSatisfy { $0.wordObservations == [] && $0.words.isEmpty && $0.evidenceVersion == 1 })
        XCTAssertTrue(saved.evidence.isEmpty); XCTAssertTrue(controller.revealed.isEmpty)
        XCTAssertEqual(decodeCalls, 0, "Silence cannot manufacture recognition or warm ASR")
        await controller.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: QuranRecitationJournal(root: root).folder(record.id).path))
    }
    @MainActor private func waitForSpans(_ controller: QuranRecitationController, count: Int) async throws {
        let deadline = Date().addingTimeInterval(8)
        while (controller.record?.observedSpeech?.count ?? 0) < count && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThanOrEqual(controller.record?.observedSpeech?.count ?? 0, count)
    }
    @MainActor func testFinishClosesActualReferencePCMAndDeletesItsWorkingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let samples = Array(try AudioProcessor.loadAudioAsFloatArray(fromPath: source.path).prefix(16_000))
        XCTAssertEqual(samples.count, 16_000)
        let controller = QuranRecitationController(requestPermission: { true }, archiveRoot: root,
            recognizeWindow: { _ in .init(runs: [], hasUnresolvedSpeech: false) },
            recognitionProvider: StorageOnlyProvider(),
            makeCapture: { writer, _ in ReferenceCapture(writer: writer, samples: samples) }, setSessionActive: { _ in })
        await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: try XCTUnwrap(QuranResources.corpus))
        XCTAssertEqual(controller.state, .listening)
        await controller.pause()
        let record = try XCTUnwrap(controller.record), take = try XCTUnwrap(record.takes.first)
        let journal = QuranRecitationJournal(root: root)
        XCTAssertEqual(try AudioProcessor.loadAudioAsFloatArray(fromPath: journal.audio(session: record.id, take: take.id).path), samples)
        await controller.finish()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.folder(record.id).path))
        XCTAssertThrowsError(try journal.load(record.id))
    }

    @MainActor func testFinishDuringPermissionCannotOpenCaptureAfterPermissionReturns() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var reply: CheckedContinuation<Bool, Never>?
        var captureOpened = false
        let controller = QuranRecitationController(requestPermission: {
            await withCheckedContinuation { reply = $0 }
        }, archiveRoot: root, makeCapture: { writer, _ in
            captureOpened = true; return ReferenceCapture(writer: writer, samples: [])
        }, setSessionActive: { _ in })
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let start = Task { await controller.start(keys: ["112:1"], page: 604, snapshot: snapshot, corpus: corpus) }
        for _ in 0..<100 where reply == nil { await Task.yield() }
        let permission = try XCTUnwrap(reply)
        await controller.finish(); permission.resume(returning: true); await start.value
        XCTAssertEqual(controller.state, .idle); XCTAssertFalse(captureOpened); XCTAssertNil(controller.record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    private final class ReferenceCapture: QuranAudioCapture {
        let writer: QuranPCMWriter, samples: [Float]
        init(writer: QuranPCMWriter, samples: [Float]) { self.writer = writer; self.samples = samples }
        func start() throws { writer.append(samples) }
        func stop() async -> Result<Int64, Error> {
            await withCheckedContinuation { continuation in writer.finish { continuation.resume(returning: $0) } }
        }
    }
    private struct StorageOnlyProvider: QuranSpeechRecognitionProvider {
        let capabilities = QuranRecognitionCapabilities(backendID: "storage-only-fixture",
            modelID: "injected-empty-observations-not-ASR", modelRevision: "1", configuredLanguage: "ar",
            delivery: .overlappingAudioWindows, processesLocally: true, wordTimestamps: false,
            wordConfidence: false, phonemeEvidence: false, calibratedWordingAssessment: false,
            validatedTajweedAssessment: false)
        func prepare() async throws {}
        func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
            .init(runs: [], hasUnresolvedSpeech: false)
        }
    }
}
