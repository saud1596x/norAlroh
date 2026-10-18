import XCTest
@testable import Athar

final class QuranRecognitionAudioTests: XCTestCase {
    func testTrackingFeedbackUsesActualPhaseWithGraceAndNeverCallsUncertaintyAnError() {
        let feedback = QuranTrackingFeedback(activity: .preparingModel, startedAt: 10)
        XCTAssertNil(feedback.message(now: 10.6), "A fast window must not flicker a work message")
        XCTAssertEqual(feedback.message(now: 11), "أستمع · تجهيز التتبع")
        XCTAssertNil(feedback.message(now: 9))
        XCTAssertNil(feedback.message(now: .nan))
        XCTAssertEqual(QuranTrackingFeedback(activity: .recognizing, startedAt: 10).message(now: 11),
                       "أستمع · معالجة التلاوة")
        XCTAssertEqual(QuranTrackingUncertainty.passageUnclear.message, "أستمع · أكمل التلاوة ليتضح الموضع")
        XCTAssertNil(QuranTrackingUncertainty.none.message)
    }
    func testQuietInferenceGainPreservesOriginalSamplesAndSilence() throws {
        let input = (0..<16000).map { Float(sin(Double($0) * 0.1) * 0.005) }
        let original = input
        let conditioned = try QuranRecognitionAudio.conditioned(input)
        XCTAssertEqual(input, original, "Conditioning must not alter archived microphone PCM")
        XCTAssertEqual(conditioned.count, input.count, "Word timestamps must keep the original sample clock")
        let rms = sqrt(conditioned.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(conditioned.count))
        XCTAssertEqual(rms, 0.06, accuracy: 0.000001)
        let extremelyQuiet = input.map { $0 * 0.001 }
        let bounded = try QuranRecognitionAudio.conditioned(extremelyQuiet)
        XCTAssertEqual(bounded[20], extremelyQuiet[20] * 256, accuracy: 0.000001)
        XCTAssertEqual(try QuranRecognitionAudio.conditioned([Float](repeating: 0, count: 16000)),
                       [Float](repeating: 0, count: 16000))
        XCTAssertThrowsError(try QuranRecognitionAudio.conditioned([.nan]))
        XCTAssertThrowsError(try QuranRecognitionAudio.conditioned([]))
    }
    func testAlreadyAudibleInputIsNotClippedOrChanged() throws {
        let input: [Float] = [0.95, -0.95, 0.4, -0.4]
        XCTAssertEqual(try QuranRecognitionAudio.conditioned(input), input)
    }

    func testWeakInputWithTransientKeepsPeakHeadroomAndSampleTiming() throws {
        var input = [Float](repeating: 0.0001, count: 16000)
        input[4000] = 0.02; input[8000] = -0.02
        let output = try QuranRecognitionAudio.conditioned(input)
        XCTAssertEqual(output.count, input.count)
        XCTAssertEqual(output[4000], 0.9, accuracy: 0.000001)
        XCTAssertEqual(output[8000], -0.9, accuracy: 0.000001)
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 0.900001 })
        XCTAssertEqual(input[4000], 0.02, "Original audio remains available unchanged")
    }
    func testDCOffsetIsRemovedFromInferenceCopyWithoutChangingClockOrOriginal() throws {
        let voice = (0..<16000).map { Float(sin(Double($0) * 0.1) * 0.001) }
        let input = voice.map { $0 + 0.15 }, original = voice.map { $0 + 0.15 }
        let output = try QuranRecognitionAudio.conditioned(input)
        XCTAssertEqual(input, original)
        XCTAssertEqual(output.count, input.count)
        XCTAssertEqual(output.reduce(0.0) { $0 + Double($1) } / Double(output.count), 0, accuracy: 0.000001)
        let rms = sqrt(output.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(output.count))
        XCTAssertEqual(rms, 0.06, accuracy: 0.000001)
        XCTAssertEqual(try QuranRecognitionAudio.conditioned(Array(repeating: Float(0.15), count: 16000)),
                       Array(repeating: Float(0), count: 16000))
        XCTAssertThrowsError(try QuranRecognitionAudio.conditioned([1.1, -1.1]))
    }
}
