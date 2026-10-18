import XCTest
@testable import Athar

/// Explicitly injected non-cancellable backend; not microphone/ASR evidence.
final class QuranRecognitionWorkerLifecycleTests: XCTestCase {
    func testUntimedSegmentCannotDisappearAndJoinNeighboringQuranWords() {
        var gate = QuranLocalWordEvidence()
        let samples = Array(repeating: Float(0.06), count: 64_000)
        gate.consume(text: "قل", start: 0, end: 0.2, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        gate.consume(text: "هو", start: 0.3, end: 0.5, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        gate.interrupt(unassessableText: "كلام غير واضح")
        gate.consume(text: "الله", start: 1.5, end: 1.7, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        gate.consume(text: "أحد", start: 1.8, end: 2, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        XCTAssertEqual(gate.runs.filter { !$0.isEmpty }.map { $0.map(\.text) }, [["قل", "هو"], ["الله", "أحد"]])
        XCTAssertTrue(gate.unresolved)
        XCTAssertEqual(gate.observations[2].observedText, "كلام غير واضح")
        XCTAssertEqual(gate.observations[2].recognitionState, "unassessable")
        XCTAssertNil(gate.observations[2].startInTakeSeconds)
        XCTAssertNil(gate.observations[2].backendConfidence)
    }
    func testBundledLowConfidenceWordKeepsItsSourceAndDoesNotJoinNeighbors() {
        var gate = QuranLocalWordEvidence()
        let samples = Array(repeating: Float(0.06), count: 64_000)
        for (index, text) in ["قل", "هو", "سيارة", "الله", "أحد"].enumerated() {
            gate.consume(text: text, start: Float(index) * 0.3, end: Float(index) * 0.3 + 0.2,
                confidence: index == 2 ? 0.4 : 0.99, speechSegment: true, samples: samples, offset: 2)
        }
        XCTAssertEqual(gate.runs.filter { !$0.isEmpty }.map { $0.map(\.text) }, [["قل", "هو"], ["الله", "أحد"]])
        XCTAssertEqual(gate.observations.map(\.observedText), ["قل", "هو", "سيارة", "الله", "أحد"])
        XCTAssertEqual(gate.observations[2].recognitionState, "unassessable")
        XCTAssertTrue(gate.unresolved)
    }
    func testBundledWordCannotClaimAudioBeyondWindowOrOverlapEarlierWord() {
        var gate = QuranLocalWordEvidence()
        let samples = Array(repeating: Float(0.06), count: 16_000)
        gate.consume(text: "قل", start: 0, end: 0.5, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        gate.consume(text: "هو", start: 0.2, end: 0.7, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        gate.consume(text: "أحد", start: 0.8, end: 1.05, confidence: 0.99, speechSegment: true, samples: samples, offset: 0)
        XCTAssertEqual(gate.runs.flatMap { $0 }.map(\.text), ["قل"])
        XCTAssertEqual(gate.rejectedTiming, 2)
        XCTAssertNil(gate.observations[2].startInTakeSeconds)
    }
    func testBundledNoSpeechHypothesisRemainsAuditableAndCannotAwardProgress() {
        var gate = QuranLocalWordEvidence()
        gate.consume(text: "قل", start: 0, end: 0.2, confidence: 0.99, speechSegment: false,
            samples: Array(repeating: 0.06, count: 16_000), offset: 0)
        XCTAssertTrue(gate.runs.flatMap { $0 }.isEmpty)
        XCTAssertEqual(gate.observations.first?.observedText, "قل")
        XCTAssertEqual(gate.observations.first?.recognitionState, "unassessable")
    }
    @MainActor func testQuranBindingRemainsAvailableWhileOldInferenceCannotReturn() async throws {
        let data = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: data).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let backend = StuckBackend()
        let worker = QuranRecognitionWorker(decodeOverride: { try await backend.decode($0) })
        let inference = Task { try await worker.recognize(.init(samples: [0.06], startFrame: 0, endFrame: 1)) }
        let deadline = Date().addingTimeInterval(3)
        while (await backend.calls) == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let started = await backend.calls
        XCTAssertEqual(started, 1)
        inference.cancel()
        do {
            let bound = try await NoorOperationDeadline.run(seconds: 5) {
                try await worker.bind(snapshot: snapshot, verseKeys: keys)
            }
            XCTAssertEqual(Set(bound.map(\.verse)), Set(keys))
        } catch {
            await backend.release(); _ = try? await inference.value
            throw error
        }
        await backend.release(); _ = try? await inference.value
    }
    func testWarmBindingDoesNotTrustSameEditionWithAlteredWords() async throws {
        let data = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        let original = try JSONDecoder().decode(QCFV2Snapshot.self, from: data).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { chapter in chapter.ayahs.map { "\(chapter.number):\($0.number)" } }
        let worker = QuranRecognitionWorker()
        let first = try await worker.bind(snapshot: original, verseKeys: keys)
        let reused = try await worker.bind(snapshot: original, verseKeys: keys)
        XCTAssertEqual(first.map(\.id), reused.map(\.id))
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(document["records"] as? [[String: Any]])
        let index = try XCTUnwrap(rows.firstIndex { $0["record_type"] as? String == "mushaf_word" })
        rows[index]["text"] = "altered"; document["records"] = rows
        let changed = try JSONDecoder().decode(QCFV2Snapshot.self, from: JSONSerialization.data(withJSONObject: document))
        do { _ = try await worker.bind(snapshot: changed, verseKeys: keys); XCTFail("Changed glyphs must never reuse a warm binding") }
        catch { /* The invalid edition is deliberately rejected. */ }
    }
    @MainActor func testCancellingDeadlineCallerMarksWorkerInferenceAndDoesNotQueueNextSession() async throws {
        let backend = StuckBackend()
        let worker = QuranRecognitionWorker(decodeOverride: { try await backend.decode($0) })
        let window = QuranAudioWindow(samples: [0.06], startFrame: 0, endFrame: 1)
        let caller = Task {
            try await NoorOperationDeadline.run(seconds: 30) { try await worker.recognize(window) }
        }
        let readyBy = Date().addingTimeInterval(3)
        while (await backend.calls) == 0 && Date() < readyBy {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await backend.calls
        XCTAssertEqual(started, 1)
        caller.cancel()
        do {
            _ = try await NoorOperationDeadline.run(seconds: 1) { try await caller.value }
            XCTFail("The cancelled pump caller must return without waiting for Core ML")
        } catch is CancellationError {
        } catch { XCTFail("Expected caller cancellation, received \(error)") }
        do {
            _ = try await NoorOperationDeadline.run(seconds: 1) { try await worker.recognize(window) }
            XCTFail("A following session must not queue behind cancelled inference")
        } catch QuranRecognitionFailure.previousInferenceStillRunning {
        } catch { XCTFail("Expected unavailable inference, received \(error)") }
        let whileBlocked = await backend.calls
        XCTAssertEqual(whileBlocked, 1)
        await backend.release()
        // The SDK returns asynchronously after caller cancellation. Wait only
        // for actor cleanup, rather than accepting or displaying its late result.
        let recoverBy = Date().addingTimeInterval(3)
        var recovered = false
        while !recovered && Date() < recoverBy {
            do { _ = try await worker.recognize(window); recovered = true }
            catch QuranRecognitionFailure.previousInferenceStillRunning {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        XCTAssertTrue(recovered)
        let afterRecovery = await backend.calls
        XCTAssertEqual(afterRecovery, 2)
    }
    func testCancelledStuckInferenceDoesNotQueueLaterSessionAndWorkerRecoversAfterReturn() async throws {
        let backend = StuckBackend()
        let worker = QuranRecognitionWorker(decodeOverride: { try await backend.decode($0) })
        let window = QuranAudioWindow(samples: [0.06], startFrame: 0, endFrame: 1)
        let first = Task { try await worker.recognize(window) }
        let deadline = Date().addingTimeInterval(3)
        while (await backend.calls) == 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await backend.calls
        XCTAssertEqual(started, 1)
        first.cancel()
        // Allow the cancellation handler to mark the underlying inference task.
        // A deadline independently bounds the assertion if the regression queues.
        do {
            _ = try await NoorOperationDeadline.run(seconds: 1) { try await worker.recognize(window) }
            XCTFail("A new session must not wait behind cancelled Core ML inference")
        } catch QuranRecognitionFailure.previousInferenceStillRunning {
            // The distinct error lets the controller report unavailable tracking.
        } catch {
            XCTFail("Expected immediate unavailable inference, received \(error)")
        }
        let callsWhileBlocked = await backend.calls
        XCTAssertEqual(callsWhileBlocked, 1, "No second decode may enter the stuck backend")
        await backend.release()
        _ = try? await first.value
        _ = try await worker.recognize(window)
        let callsAfterRecovery = await backend.calls
        XCTAssertEqual(callsAfterRecovery, 2, "A returned cancelled task must not permanently poison the worker")
    }

    private actor StuckBackend {
        private(set) var calls = 0
        private var pending: CheckedContinuation<QuranRecognitionWorker.Result, Never>?
        func decode(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result {
            calls += 1
            if calls == 1 {
                return await withCheckedContinuation { pending = $0 }
            }
            return .init(runs: [], hasUnresolvedSpeech: false)
        }
        func release() {
            pending?.resume(returning: .init(runs: [], hasUnresolvedSpeech: false))
            pending = nil
        }
    }
}
