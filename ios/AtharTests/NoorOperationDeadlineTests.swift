import XCTest
@testable import Athar

final class NoorOperationDeadlineTests: XCTestCase {
    @MainActor func testCallerCancellationReturnsBeforeUncooperativeSDKAndMarksItsTaskCancelled() async throws {
        let entered = expectation(description: "SDK continuation entered")
        var late: CheckedContinuation<Int, Never>?
        var cancelledWhenSDKReturns = false
        let finishedLate = expectation(description: "Late SDK work returns once")
        let caller = Task {
            try await NoorOperationDeadline.run(seconds: 30) {
                let value: Int = await withCheckedContinuation { late = $0; entered.fulfill() }
                cancelledWhenSDKReturns = Task.isCancelled
                finishedLate.fulfill()
                return value
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        caller.cancel()
        do {
            _ = try await NoorOperationDeadline.run(seconds: 1) { try await caller.value }
            XCTFail("Caller cancellation must return without waiting for the SDK")
        } catch is CancellationError {
            // The deadline must not reinterpret explicit cancellation as timeout.
        } catch { XCTFail("Expected cancellation, received \(error)") }
        try XCTUnwrap(late).resume(returning: 42)
        await fulfillment(of: [finishedLate], timeout: 3)
        XCTAssertTrue(cancelledWhenSDKReturns, "Cancellation must reach the SDK wrapper task")
        let next = try await NoorOperationDeadline.run { 7 }
        XCTAssertEqual(next, 7, "A late completion must not resume another operation")
    }
    @MainActor func testSDKThatIgnoresCancellationCannotKeepScreenBusyOrResumeTwice() async throws {
        var late: CheckedContinuation<Int, Never>?
        let started = Date()
        do {
            _ = try await NoorOperationDeadline.run(seconds: 0.05) {
                await withCheckedContinuation { late = $0 }
            }
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try XCTUnwrap(late).resume(returning: 42)
        await Task.yield()
        let next = try await NoorOperationDeadline.run { 7 }
        XCTAssertEqual(next, 7)
    }
    @MainActor func testFailureReturnsWithoutWaitingForDeadline() async {
        do {
            _ = try await NoorOperationDeadline.run(seconds: 30) { throw URLError(.notConnectedToInternet) } as Int
            XCTFail("Expected network failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
}
