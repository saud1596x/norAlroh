import XCTest
@testable import Athar

final class RecitationObservationTests: XCTestCase {
    private func words() throws -> [RecitationExpectedWord] {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        return RecitationComparison.words(chapter: corpus[0], from: 1, to: 7)
    }
    func testCorrectionResolvesCandidateAndLaterRecurrenceGetsNewGracePeriod() throws {
        let words = try words(), began = Date(timeIntervalSince1970: 100)
        var ledger = RecitationObservationLedger()
        let difference = RecitationComparison(matchedIndices: [1,2,3], possibleDifferences: [.init(id: 0, wordIndex: 0, expected: words[0].text, heard: "اختلاف")], endIndex: 4, reliableAlignment: true)
        ledger.ingest(difference, expected: words, at: began)
        XCTAssertFalse(try XCTUnwrap(ledger.notes[0]).readyForReview(at: began.addingTimeInterval(7)))
        XCTAssertTrue(try XCTUnwrap(ledger.notes[0]).readyForReview(at: began.addingTimeInterval(8)))
        ledger.ingest(.init(matchedIndices: [0,1,2], possibleDifferences: [], endIndex: 3, reliableAlignment: true), expected: words, at: began.addingTimeInterval(9))
        XCTAssertTrue(try XCTUnwrap(ledger.notes[0]).corrected)
        XCTAssertFalse(try XCTUnwrap(ledger.notes[0]).readyForReview(at: began.addingTimeInterval(20)))
        ledger.ingest(difference, expected: words, at: began.addingTimeInterval(21))
        XCTAssertFalse(try XCTUnwrap(ledger.notes[0]).readyForReview(at: began.addingTimeInterval(22)))
    }
    func testUncertainRecognitionDoesNotCreateOrResolveNotesAndDismissedNotesStayExcluded() throws {
        let words = try words(), began = Date(timeIntervalSince1970: 100)
        var ledger = RecitationObservationLedger()
        let differences: [RecitationDifference] = [.init(id: 0, wordIndex: 0, expected: words[0].text, heard: nil), .init(id: 1, wordIndex: 99999, expected: "invalid", heard: nil)]
        ledger.ingest(.init(matchedIndices: [], possibleDifferences: differences, endIndex: 4, reliableAlignment: false), expected: words, at: began)
        XCTAssertTrue(ledger.notes.isEmpty)
        let reliable = RecitationComparison(matchedIndices: [1,2,3], possibleDifferences: differences, endIndex: 4, reliableAlignment: true)
        ledger.ingest(reliable, expected: words, at: began)
        XCTAssertEqual(ledger.notes.count, 1)
        ledger.ingest(.init(matchedIndices: [0], possibleDifferences: [], endIndex: 1, reliableAlignment: false), expected: words, at: began)
        XCTAssertFalse(try XCTUnwrap(ledger.notes[0]).corrected)
        ledger.dismiss(0)
        ledger.ingest(reliable, expected: words, at: began.addingTimeInterval(30))
        XCTAssertTrue(try XCTUnwrap(ledger.notes[0]).dismissed)
        XCTAssertFalse(try XCTUnwrap(ledger.notes[0]).readyForReview(at: began.addingTimeInterval(40)))
    }
}
