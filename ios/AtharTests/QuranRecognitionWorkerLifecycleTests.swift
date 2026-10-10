import XCTest
@testable import Athar

/// Explicitly injected non-cancellable backend; not microphone/ASR evidence.
final class QuranRecognitionWorkerLifecycleTests: XCTestCase {
    @MainActor func testCancellingDeadlineCallerMarksWorkerInferenceAndDoesNotQueueNextSession() async throws {
        let backend = StuckBackend()
        let worker = QuranRecognitionWorker(decodeOverride: { try await backend.decode($0) })
        let window = QuranAudioWindow(samples: [0.06], startFrame: 0, endFrame: 1)
        let caller = Task {
            try await NoorOperationDeadline.run(seconds: 30) { try await worker.recognize(window) }
        }
        let readyBy = Date().addingTimeInterval(3)
        while await backend.calls == 0 && Date() < readyBy {
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
        while await backend.calls == 0 && Date() < deadline {
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
