import XCTest
@testable import Athar

final class PublishingContentTests: XCTestCase {
    func testBundledLegalDocumentsLoadOfflineWithoutAUserAccount() throws {
        let content = try XCTUnwrap(NoorLegalContent.current)
        XCTAssertEqual(content.appName, "نور الروح")
        XCTAssertEqual(content.accountMode, "local-only")
        XCTAssertEqual(Set(content.documents.map(\.id)), ["privacy", "terms", "support"])
        XCTAssertTrue(content.documents.allSatisfy { !$0.sections.isEmpty })
    }
    func testIncompleteOrAccountBackedLegalResourceIsRejected() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "app-legal", withExtension: "json"))
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["accountMode"] = "server-backed"
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)), "A local-only policy cannot represent an account-backed service.")
        object["accountMode"] = "local-only"; object["documents"] = []
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)))
    }
}
