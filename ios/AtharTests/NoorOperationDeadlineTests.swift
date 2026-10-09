import XCTest
@testable import Athar

final class NoorOperationDeadlineTests: XCTestCase {
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
