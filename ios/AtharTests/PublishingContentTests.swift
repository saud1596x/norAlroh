import XCTest
@testable import Athar

final class PublishingContentTests: XCTestCase {
    func testBundledLegalDocumentsLoadOfflineWithoutAUserAccount() throws {
        let content = try XCTUnwrap(NoorLegalContent.current)
        XCTAssertEqual(content.appName, "نور الروح")
        XCTAssertTrue(["local-only", "firebase-opt-in"].contains(content.accountMode))
        XCTAssertEqual(Set(content.documents.map(\.id)), ["privacy", "terms", "support"])
        XCTAssertTrue(content.documents.allSatisfy { !$0.sections.isEmpty })
    }
    func testIncompleteOrUnknownLegalResourceIsRejected() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "app-legal", withExtension: "json"))
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["accountMode"] = "server-backed"
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)), "Unknown privacy modes must not be accepted.")
        object["accountMode"] = "local-only"; object["documents"] = []
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)))
    }
    func testAccountPolicyRequiresTheNewSchemaAndRemainsAvailableOffline() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "app-legal", withExtension: "json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["accountMode"] = "firebase-opt-in"; object["version"] = 1
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)))
        object["version"] = 2
        let content = try XCTUnwrap(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(content.contact.supportEmail, "noralrohsupport@gmail.com")
        XCTAssertEqual(content.contact.emailURL?.scheme, "mailto")
        object["accountMode"] = "local-only"
        XCTAssertNil(NoorLegalContent.decode(try JSONSerialization.data(withJSONObject: object)))
    }
}
