import Foundation
import SwiftUI

struct NoorLegalSection: Decodable, Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

struct NoorLegalDocument: Decodable, Identifiable {
    let id: String
    let title: String
    let sections: [NoorLegalSection]
}

struct NoorLegalContent: Decodable {
    struct Contact: Decodable {
        let supportEmail: String?
        let privacyURL: URL?
        let supportURL: URL?
        let termsURL: URL?
        var emailURL: URL? {
            guard let supportEmail, !supportEmail.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "mailto"; components.path = supportEmail
            return components.url
        }
    }
    let version: Int
    let updatedAt: String
    let appName: String
    let publisherName: String
    let accountMode: String
    let contact: Contact
    let documents: [NoorLegalDocument]
    static func decode(_ data: Data) -> NoorLegalContent? {
        guard let result = try? JSONDecoder().decode(Self.self, from: data),
              result.version == 1, result.accountMode == "local-only",
              !result.appName.isEmpty, !result.publisherName.isEmpty,
              Set(result.documents.map(\.id)) == ["privacy", "terms", "support"],
              result.documents.count == 3,
              result.documents.allSatisfy({ !$0.title.isEmpty && !$0.sections.isEmpty && $0.sections.allSatisfy { !$0.title.isEmpty && !$0.text.isEmpty } }) else { return nil }
        return result
    }
    static let current: NoorLegalContent? = {
        guard let url = Bundle.main.url(forResource: "app-legal", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }()
}

struct NoorLegalDocumentView: View {
    let documentID: String
    private var title: String {
        switch documentID {
        case "privacy": "سياسة الخصوصية"
        case "terms": "شروط الاستخدام"
        default: "الدعم والمساعدة"
        }
    }
    var body: some View {
        ScrollView {
            if let content = NoorLegalContent.current,
               let document = content.documents.first(where: { $0.id == documentID }) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(content.appName).font(.title2.bold())
                    Text("الناشر: \(content.publisherName)").font(.subheadline)
                    Text("آخر تحديث: \(content.updatedAt)").font(.caption).foregroundStyle(.secondary)
                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(section.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let url = content.contact.emailURL {
                        Link("تواصل مع الدعم", destination: url).frame(minHeight: 44)
                            .accessibilityIdentifier("legal.contact")
                    }
                    if documentID == "privacy", let url = content.contact.privacyURL {
                        Link("سياسة الخصوصية على الويب", destination: url).frame(minHeight: 44)
                    }
                    if documentID == "support", let url = content.contact.supportURL {
                        Link("صفحة الدعم على الويب", destination: url).frame(minHeight: 44)
                    }
                    if documentID == "terms" {
                        Link("اتفاقية Apple القياسية", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            .frame(minHeight: 44)
                    }
                }.padding(24)
            } else {
                ContentUnavailableView("تعذر فتح الصفحة", systemImage: "doc.text", description: Text("ملف المعلومات غير متاح. أعد تثبيت نسخة موثوقة."))
            }
        }.background(Theme.background).navigationTitle(title)
            .accessibilityIdentifier("legal.\(documentID)")
    }
}
