import XCTest
@testable import Athar

final class QuranRecognitionCapabilityTests: XCTestCase {
    func testWindowedRecognizerDoesNotAdvertisePronunciationOrCalibratedCorrectness() {
        let backend: any QuranSpeechRecognitionProvider = QuranRecognitionWorker()
        XCTAssertEqual(backend.capabilities.configuredLanguage, "ar")
        XCTAssertEqual(backend.capabilities.delivery, .overlappingAudioWindows)
        XCTAssertTrue(backend.capabilities.processesLocally)
        XCTAssertTrue(backend.capabilities.wordTimestamps)
        XCTAssertFalse(backend.capabilities.phonemeEvidence)
        XCTAssertFalse(backend.capabilities.calibratedWordingAssessment)
        XCTAssertFalse(backend.capabilities.validatedTajweedAssessment)
    }
}
