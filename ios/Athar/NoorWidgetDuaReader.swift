import SwiftUI

// The URL contains the tapped ID. This screen never substitutes the current
// hour's prayer, changes the Quran position, or credits a reading session.
struct NoorWidgetDuaReader: View {
    let duaID: String
    @ScaledMetric(relativeTo: .title) private var readingFont = 28.0
    var body: some View {
        ScrollView {
            if let dua = NoorDuaCatalog.find(duaID) {
                VStack(alignment: .leading, spacing: 32) {
                    Text(dua.text)
                        .font(.system(size: readingFont, weight: .regular, design: .serif))
                        .lineSpacing(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("widget.dua.text")
                    ShareLink(item: dua.text) { Label("مشاركة الدعاء", systemImage: "square.and.arrow.up") }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("تعذر فتح الدعاء", systemImage: "hands.sparkles", description: Text("عد إلى الأداة وافتح الدعاء مجددًا."))
            }
        }
        .navigationTitle("دعاء")
        .environment(\.layoutDirection, .rightToLeft)
    }
}
