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
    func testOfflinePoliciesDescribeLocalRecognitionAndExplicitAudioRemoval() throws {
        let content = try XCTUnwrap(NoorLegalContent.current)
        let privacy = try XCTUnwrap(content.documents.first { $0.id == "privacy" })
        let recording = try XCTUnwrap(privacy.sections.first { $0.title == "تسجيل التسميع" })
        XCTAssertTrue(recording.text.contains("إذن الميكروفون"))
        XCTAssertTrue(recording.text.contains("نموذج تعرّف محلي"))
        XCTAssertTrue(recording.text.contains("لا يرسل صوت التسميع"))
        XCTAssertTrue(recording.text.contains("دقة النتائج ليست مضمونة"))
        XCTAssertTrue(recording.text.contains("لا تمثل تصحيحًا معتمدًا"))
        XCTAssertTrue(recording.text.contains("يبقى النص متاحًا عند تعذر التعرف"))
        XCTAssertTrue(recording.text.contains("أزيلت شاشة سجلات التسميع"))
        let removal = try XCTUnwrap(privacy.sections.first { $0.title == "التصدير والحذف وسحب الإذن" })
        XCTAssertTrue(removal.text.contains("ملف غير مشفر"))
        XCTAssertTrue(removal.text.contains("حذف تسجيلات التسميع إجراء مستقل"))
        XCTAssertTrue(removal.text.contains("بتأكيد"))
        XCTAssertTrue(removal.text.contains("لا يحذف علامات القراءة أو سجل الحفظ أو الحساب"))
        XCTAssertTrue(removal.text.contains("لا يحذف الملفات التي صدّرتها خارج التطبيق"))
        let all = content.documents.flatMap { $0.sections.map(\.text) }.joined(separator: "\n")
        XCTAssertFalse(all.contains("جهّز النموذج")); XCTAssertFalse(all.contains("Hugging Face"))
        XCTAssertFalse(all.contains("لا يوجد تحويل للكلام إلى نص"))
        XCTAssertFalse(all.contains("لا يستخدم الإصدار الحالي محرك تحويل كلام إلى نص"))
        XCTAssertFalse(all.contains("من «تسجيلات التسميع»"), "Removed history screen must not remain in help instructions.")
        XCTAssertFalse(all.contains("لا توجد نتيجة صوتية آلية"))
        if content.accountMode == "firebase-opt-in" {
            XCTAssertTrue(all.contains("Firebase Authentication"))
            XCTAssertTrue(all.contains("Cloud Firestore"))
            XCTAssertTrue(all.contains("معرّفًا عشوائيًا للجهاز"))
            XCTAssertTrue(all.contains("علامة حذف مرتبطة بمعرّف الحساب"))
            XCTAssertTrue(removal.text.contains("حذف الحساب"))
            XCTAssertTrue(removal.text.contains("الحذف لم يكتمل"))
            XCTAssertFalse(all.contains("دون مزامنة إلى خادم نور الروح"))
        }
    }
    func testRequiredContentNoticesRemainBundledOutsidePrivacyCopy() throws {
        let tanzilURL = try XCTUnwrap(Bundle.main.url(forResource: "Tanzil-LICENSE", withExtension: "txt"))
        let tanzil = try String(contentsOf: tanzilURL, encoding: .utf8)
        XCTAssertTrue(tanzil.contains("Tanzil Project"))
        XCTAssertTrue(tanzil.contains("tanzil.net"))
        XCTAssertTrue(tanzil.contains("CHANGING IT IS NOT ALLOWED"))
        for name in ["WHISPERKIT-LICENSE", "WHISPER-MODEL-LICENSE", "ADHAN-SWIFT-LICENSE"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "txt"))
            let notice = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(notice.contains("MIT License"))
            XCTAssertTrue(notice.contains("copyright notice"))
        }
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
