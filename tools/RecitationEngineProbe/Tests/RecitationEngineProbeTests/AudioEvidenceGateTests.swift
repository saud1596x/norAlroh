import XCTest
@testable import RecitationEvidence

final class AudioEvidenceGateTests: XCTestCase {
    func testObservedSilenceHallucinationCannotReachReader() {
        let silence = [Float](repeating: 0, count: 128_000)
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 28.58, end: 29.98,
            probability: 0.99), samples: silence), .invalidTiming)
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 1, end: 2,
            probability: 0.99), samples: silence), .insufficientAudio)
    }
    func testUncertainAndLowVolumeAudioStaysUnresolved() {
        let audible = [Float](repeating: 0.06, count: 16_000)
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 0.1, end: 0.6,
            probability: 0.4), samples: audible), .lowConfidence)
        let quiet = [Float](repeating: 0.01, count: 16_000)
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 0.1, end: 0.6,
            probability: 0.99), samples: quiet), .insufficientAudio)
    }
    func testBadEvidenceCannotBeClampedIntoValidWord() {
        let audible = [Float](repeating: 0.06, count: 16_000)
        let badTimes: [(Float, Float)] = [(-0.1, 0.5), (0.8, 0.4), (0.5, 0.5), (0.5, 2), (.nan, 0.8)]
        for pair in badTimes {
            XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: pair.0, end: pair.1,
                probability: 0.99), samples: audible), .invalidTiming)
        }
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 0.1, end: 0.6,
            probability: .infinity), samples: audible), .lowConfidence)
        var corrupt = audible; corrupt[100] = .nan
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 0.1, end: 0.6,
            probability: 0.99), samples: corrupt), .invalidAudio)
    }
    func testWordNeedsSoundAtItsOwnTimeNotElsewhereInWindow() {
        let separated = [Float](repeating: 0.06, count: 8_000) + [Float](repeating: 0, count: 8_000)
        XCTAssertNil(AudioEvidenceGate.rejection(.init(start: 0.1, end: 0.4,
            probability: 0.99), samples: separated))
        XCTAssertEqual(AudioEvidenceGate.rejection(.init(start: 0.6, end: 0.9,
            probability: 0.99), samples: separated), .insufficientAudio)
    }
}
