import XCTest
@testable import Athar

final class QuranRecognitionAudioTests: XCTestCase {
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
        XCTAssertEqual(bounded[20], extremelyQuiet[20] * 32, accuracy: 0.000001)
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
