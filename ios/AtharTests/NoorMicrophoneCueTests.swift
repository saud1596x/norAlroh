import XCTest
@testable import Athar

/// Ordering/cancellation tests with a manual sound driver. They are not
/// evidence that a physical speaker, haptic motor or microphone was exercised.
@MainActor final class NoorMicrophoneCueTests: XCTestCase {
    private final class Driver: NoorMicrophoneCueDriver {
        var available = true
        var played = 0
        var completion: (@MainActor @Sendable () -> Void)?
        func prepare() -> Bool { available }
        func play(completion: @escaping @MainActor @Sendable () -> Void) { played += 1; self.completion = completion }
        func cancel() { }
    }
    func testCaptureWaitsForSoundCompletionAndAcousticClearance() async throws {
        let driver = Driver()
        let active = NoorMicrophoneCue(driver: driver, haptics: false)
        var starts = 0
        active.begin { starts += 1 }; active.begin { starts += 10 }
        XCTAssertEqual(driver.played, 1); XCTAssertTrue(active.pending); XCTAssertEqual(starts, 0)
        driver.completion?()
        XCTAssertEqual(starts, 0, "Sound completion cannot skip the acoustic tail")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(starts, 1); XCTAssertFalse(active.pending)
        driver.completion?()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(starts, 1, "A duplicate callback cannot acquire another microphone")
    }
    func testPrimaryCaptureStartsImmediatelyWithoutPreparingOrPlayingSound() {
        let driver = Driver(); let cue = NoorMicrophoneCue(driver: driver, haptics: false)
        var starts = 0
        cue.beginCapture { starts += 1 }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(driver.played, 0)
        XCTAssertFalse(cue.pending)
        XCTAssertNil(cue.error)
    }
    func testPrimaryCaptureInvalidatesAnOutstandingSoundAndItsLateCallback() async throws {
        let driver = Driver(); let cue = NoorMicrophoneCue(driver: driver, haptics: false)
        var obsoleteStarts = 0, directStarts = 0
        cue.begin { obsoleteStarts += 1 }
        let lateCompletion = driver.completion
        cue.beginCapture { directStarts += 1 }
        lateCompletion?()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(directStarts, 1)
        XCTAssertEqual(obsoleteStarts, 0)
        XCTAssertFalse(cue.pending)
    }
    func testLeavingReaderInvalidatesLateSoundCompletion() async throws {
        let driver = Driver(); let cue = NoorMicrophoneCue(driver: driver, haptics: false)
        var starts = 0
        cue.begin { starts += 1 }; cue.cancel(); driver.completion?()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(starts, 0); XCTAssertFalse(cue.pending)
    }
    func testUnavailableFileStartsQuietlyWithoutQueuingAudio() {
        let driver = Driver(); driver.available = false
        let cue = NoorMicrophoneCue(driver: driver, haptics: false)
        var starts = 0; cue.begin { starts += 1 }
        XCTAssertEqual(starts, 1); XCTAssertEqual(driver.played, 0); XCTAssertFalse(cue.pending)
    }
    func testSoundTimeoutNeverStartsCaptureFromAnUnconfirmedCue() async throws {
        let driver = Driver(); let cue = NoorMicrophoneCue(driver: driver, haptics: false, deadlineNanoseconds: 20_000_000)
        var starts = 0; cue.begin { starts += 1 }
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(starts, 0); XCTAssertFalse(cue.pending); XCTAssertNotNil(cue.error)
        driver.completion?()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(starts, 0)
    }
    func testBundledUIFeedbackIsBriefQuietPCMNotARecitationFixture() throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "mic-start", withExtension: "wav")))
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        let bytes = [UInt8](data)
        func integer(_ offset: Int, _ length: Int) -> Int {
            (0..<length).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        XCTAssertEqual(integer(20, 2), 1); XCTAssertEqual(integer(22, 2), 1)
        XCTAssertEqual(integer(24, 4), 44_100); XCTAssertEqual(integer(34, 2), 16)
        let count = integer(40, 4)
        XCTAssertEqual(data.count, count + 44); XCTAssertLessThanOrEqual(Double(count) / 88_200, 0.08)
        let samples = stride(from: 44, to: data.count, by: 2).map { abs(Int(Int16(bitPattern: UInt16(integer($0, 2))))) }
        XCTAssertGreaterThan(samples.max() ?? 0, 0); XCTAssertLessThanOrEqual(samples.max() ?? 0, 1_500)
    }
}
