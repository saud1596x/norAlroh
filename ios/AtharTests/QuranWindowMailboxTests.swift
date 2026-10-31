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
    func testPreparedConsumerUsesLongerIdenticalPrefixInsteadOfDecodingStaleBeginning() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        for second in 3...8 { mailbox.put(window(ending: second)) }
        let refreshed = try mailbox.refreshCovering(held)
        XCTAssertEqual(refreshed.startFrame, 0)
        XCTAssertEqual(refreshed.endFrame, 128_000)
        XCTAssertEqual(refreshed.samples, window(ending: 8).samples)
        XCTAssertEqual(Array(refreshed.samples.prefix(held.samples.count)), held.samples)
        XCTAssertNil(try mailbox.take())
        mailbox.put(window(ending: 9))
        XCTAssertEqual(try mailbox.take()?.endFrame, 144_000)
    }
    func testLongColdRefreshExtendsOnlyOriginalPrefixAndRetainsEveryLaterFrame() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        for second in 3...47 { mailbox.put(window(ending: second)) }
        let refreshed = try mailbox.refreshCovering(held)
        XCTAssertEqual(refreshed.startFrame, held.startFrame)
        XCTAssertEqual(refreshed.endFrame, 128_000)
        XCTAssertEqual(refreshed.samples.count, 128_000)
        XCTAssertEqual(refreshed.samples, window(ending: 8).samples)
        XCTAssertEqual(Array(refreshed.samples.prefix(held.samples.count)), held.samples)
        var covered = refreshed.endFrame
        while let next = try mailbox.take() {
            XCTAssertLessThanOrEqual(next.startFrame, covered - 16_000)
            XCTAssertGreaterThan(next.endFrame, covered)
            XCTAssertEqual(next.samples, window(ending: Int(next.endFrame / 16_000)).samples)
            covered = next.endFrame
        }
        XCTAssertEqual(covered, 47 * 16_000)
    }
    func testTwentyThreeSecondColdRefreshLeavesShiftedWindowTailPending() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        for second in 3...23 { mailbox.put(window(ending: second)) }
        let refreshed = try mailbox.refreshCovering(held)
        XCTAssertEqual(refreshed.startFrame, 0)
        XCTAssertEqual(refreshed.endFrame, 8 * 16_000)
        XCTAssertEqual(refreshed.samples, window(ending: 8).samples)
        let tail = try XCTUnwrap(mailbox.take())
        XCTAssertEqual(tail.startFrame, 16_000)
        XCTAssertEqual(tail.endFrame, 9 * 16_000)
        XCTAssertEqual(tail.samples, window(ending: 9).samples)
        var covered = tail.endFrame
        while let next = try mailbox.take() {
            XCTAssertLessThanOrEqual(next.startFrame, covered - 16_000)
            XCTAssertEqual(next.samples, window(ending: Int(next.endFrame / 16_000)).samples)
            covered = next.endFrame
        }
        XCTAssertEqual(covered, 23 * 16_000)
    }
    func testShiftedOverlapCorruptionCannotExtendAColdPrefix() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        for second in 3...8 { mailbox.put(window(ending: second)) }
        let genuine = window(ending: 9)
        var changed = genuine.samples; changed[100] += 0.01
        mailbox.put(.init(samples: changed, startFrame: genuine.startFrame, endFrame: genuine.endFrame))
        XCTAssertThrowsError(try mailbox.refreshCovering(held))
        XCTAssertThrowsError(try mailbox.take())
    }
    func testMissingSourceIntervalCannotBeJoinedIntoARefreshedPrefix() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        mailbox.put(window(ending: 12)) // Starts at 4s: 2s of source PCM is missing.
        XCTAssertThrowsError(try mailbox.refreshCovering(held))
        XCTAssertThrowsError(try mailbox.take())
    }
    func testEqualNumericZeroCannotConcealChangedOverlapBytes() throws {
        let mailbox = QuranWindowMailbox()
        var original = window(ending: 2).samples; original[10] = 0
        mailbox.put(.init(samples: original, startFrame: 0, endFrame: 32_000))
        let held = try XCTUnwrap(mailbox.take())
        var changed = window(ending: 3).samples; changed[10] = -Float.zero
        XCTAssertEqual(original[10], changed[10])
        XCTAssertNotEqual(original[10].bitPattern, changed[10].bitPattern)
        mailbox.put(.init(samples: changed, startFrame: 0, endFrame: 48_000))
        XCTAssertThrowsError(try mailbox.refreshCovering(held))
    }
    func testRefreshRejectsDifferentBytesAtTheSameSourceFrames() throws {
        let mailbox = QuranWindowMailbox()
        mailbox.put(window(ending: 2))
        let held = try XCTUnwrap(mailbox.take())
        let genuine = window(ending: 3)
        var altered = genuine.samples; altered[10] += 0.01
        mailbox.put(.init(samples: altered, startFrame: genuine.startFrame, endFrame: genuine.endFrame))
        XCTAssertThrowsError(try mailbox.refreshCovering(held))
        XCTAssertThrowsError(try mailbox.take(), "A corrupt overlap cannot silently resume from later speech")
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
