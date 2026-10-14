import XCTest
@testable import Athar

final class QuranRecognitionAudioTests: XCTestCase {
    func testQuietInferenceGainPreservesOriginalSamplesAndSilence() throws {
        let input = (0..<16000).map { Float(sin(Double($0) * 0.1) * 0.005) }
        let original = input
        let conditioned = try QuranRecognitionAudio.conditioned(input)
        XCTAssertEqual(input, original, "Conditioning must not alter archived microphone PCM")
        XCTAssertEqual(conditioned.count, input.count, "Word timestamps must keep the original sample clock")
        XCTAssertEqual(conditioned[20], input[20] * 8, accuracy: 0.000001)
        XCTAssertEqual(try QuranRecognitionAudio.conditioned([Float](repeating: 0, count: 16000)),
                       [Float](repeating: 0, count: 16000))
        XCTAssertThrowsError(try QuranRecognitionAudio.conditioned([.nan]))
        XCTAssertThrowsError(try QuranRecognitionAudio.conditioned([]))
    }
    func testAlreadyAudibleInputIsNotClippedOrChanged() throws {
        let input: [Float] = [0.95, -0.95, 0.4, -0.4]
        XCTAssertEqual(try QuranRecognitionAudio.conditioned(input), input)
    }
}
