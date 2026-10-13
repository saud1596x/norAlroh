import XCTest
@testable import Athar

final class QuranRecitationPositionTests: XCTestCase {
    func testSameVerseCrossesPageAndCanReturnWithoutUsingItsFirstPage() {
        let words: [QuranAlignedWord] = [
            .init(id: 10, verse: "2:282", page: 48, aliases: [["اول"]]),
            .init(id: 11, verse: "2:282", page: 49, aliases: [["اخر"]])
        ]
        func evidence(_ id: Int, verse: String = "2:282") -> QuranWordEvidence {
            .init(nativeID: id, verse: verse, takeID: UUID(), start: 0, end: 1, minimumConfidence: 0.99)
        }
        XCTAssertEqual(QuranRecitationPosition.page(for: evidence(10), in: words), 48)
        XCTAssertEqual(QuranRecitationPosition.page(for: evidence(11), in: words), 49)
        XCTAssertEqual(QuranRecitationPosition.page(for: evidence(10), in: words), 48)
        XCTAssertNil(QuranRecitationPosition.page(for: evidence(11, verse: "2:283"), in: words))
        XCTAssertNil(QuranRecitationPosition.page(for: evidence(12), in: words))
        XCTAssertNil(QuranRecitationPosition.page(for: nil, in: words))
    }
}
