import XCTest
@testable import Athar

/// Scheduling and PCM identity regressions, not acoustic or microphone tests.
final class QuranWindowMailboxTests: XCTestCase {
    private func window(ending second: Int) -> QuranAudioWindow {
        let end = second * 16_000
        let start = max(0, end - 128_000)
        return .init(samples: (start..<end).map { Float($0) / 1_000_000 },
                     startFrame: Int64(start), endFrame: Int64(end))
    }
    func testColdPreparationKeepsBeginningAndEveryInterveningFrame() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let first = try XCTUnwrap(mailbox.take())
        XCTAssertEqual(first.startFrame, 0)
        // Simulate 45 seconds of model preparation after the first window.
        for second in 3...47 { mailbox.put(window(ending: second)) }
        var coveredEnd = first.endFrame
        var count = 0
        while let next = try mailbox.take() {
            XCTAssertLessThanOrEqual(next.startFrame, coveredEnd - 16_000)
            XCTAssertGreaterThan(next.endFrame, coveredEnd)
            XCTAssertEqual(next.samples, window(ending: Int(next.endFrame / 16_000)).samples)
            coveredEnd = next.endFrame; count += 1
        }
        XCTAssertEqual(coveredEnd, 47 * 16_000)
        XCTAssertLessThanOrEqual(count, 8)
    }
    func testWaitingConsumerGetsNewestWindowWithoutLosingInitialAudio() throws {
        let mailbox = QuranWindowMailbox()
        for second in 2...8 { mailbox.put(window(ending: second)) }
        let first = try XCTUnwrap(mailbox.take())
        XCTAssertEqual(first.startFrame, 0)
        XCTAssertEqual(first.endFrame, 128_000)
        XCTAssertNil(try mailbox.take())
        for second in 9...20 {
            mailbox.put(window(ending: second))
            XCTAssertEqual(try mailbox.take()?.endFrame, Int64(second * 16_000))
        }
    }
    func testOverflowReportsUnavailableInsteadOfDroppingAudioSilently() throws {
        let mailbox = QuranWindowMailbox(capacity: 2)
        for second in 2...30 { mailbox.put(window(ending: second)) }
        XCTAssertThrowsError(try mailbox.take()) { error in
            guard case QuranWindowMailbox.Failure.overloaded = error else {
                return XCTFail("Expected bounded backlog failure, got \(error)")
            }
        }
        mailbox.put(window(ending: 31))
        XCTAssertThrowsError(try mailbox.take(), "A failed take must not pretend to recover by skipping its backlog")
    }
    func testNoncontiguousFirstWindowCannotInventCoverage() {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 20))
        XCTAssertThrowsError(try mailbox.take()) { error in
            guard case QuranWindowMailbox.Failure.discontinuousAudio = error else {
                return XCTFail("Expected missing audio rejection, got \(error)")
            }
        }
    }
}
