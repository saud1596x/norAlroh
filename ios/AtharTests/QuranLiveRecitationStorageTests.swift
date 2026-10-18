import XCTest
import AVFoundation
import WhisperKit
@testable import Athar

final class QuranLiveRecitationStorageTests: XCTestCase {
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
        let waiting = await gate.waiting; XCTAssertTrue(waiting)
        let session = try XCTUnwrap(controller.record).id
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
        private(set) var waiting = false
        func wait() async { waiting = true; await withCheckedContinuation { reply = $0 } }
        func release() { reply?.resume(); reply = nil }
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
}
