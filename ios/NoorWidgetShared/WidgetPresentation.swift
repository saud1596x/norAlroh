import SwiftUI
import WidgetKit

#if NOOR_ACCEPTANCE_TESTING
// Resolved by the native design fixture, without changing shipping layout.
struct NoorDuaDesignBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif

enum NoorDuaComposition: String, CaseIterable { case linear, editorial, najdi }

enum NoorWidgetPalette {
    static let ink = Color(red: 16/255, green: 26/255, blue: 23/255)
    static let surface = Color(red: 25/255, green: 40/255, blue: 34/255)
    static let ivory = Color(red: 244/255, green: 238/255, blue: 226/255)
    static let sand = Color(red: 191/255, green: 167/255, blue: 122/255)
}

struct NoorNajdiEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return path }
        let unit = min(rect.width, 8)
        path.move(to: CGPoint(x: rect.midX, y: 0))
        for i in 0..<Int(rect.height / (unit * 2)) {
            let y = CGFloat(i) * unit * 2
            path.addLine(to: CGPoint(x: rect.midX, y: y))
            path.addLine(to: CGPoint(x: rect.midX - unit / 2, y: y + unit))
            path.addLine(to: CGPoint(x: rect.midX, y: y + unit * 2))
        }
        return path
    }
}

// The same component is used by WidgetKit, in-app discovery, and composition
// previews. Quran content is real Text, with no ellipsis or aggressive scaling.
struct NoorDuaWidgetComposition: View {
    let dua: NoorDua
    let family: WidgetFamily
    var composition: NoorDuaComposition = .najdi
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .body) private var smallFont = 18.0
    @ScaledMetric(relativeTo: .title3) private var mediumFont = 22.0
    @ScaledMetric(relativeTo: .title) private var largeFont = 28.0
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private var textColor: Color { renderingMode == .fullColor ? (scheme == .dark ? NoorWidgetPalette.ivory : NoorWidgetPalette.ink) : .primary }
    var body: some View {
        HStack(spacing: small ? 8 : 16) {
            if composition == .najdi, !small {
                NoorNajdiEdge().stroke(textColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 8).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: large ? 24 : 8) {
                Text("دعاء").font(.caption.weight(.medium)).foregroundStyle(textColor.opacity(0.72))
                if large || composition == .editorial { Spacer(minLength: 0) }
                Text(dua.text)
                    .font(.system(size: large ? largeFont : small ? smallFont : mediumFont, weight: .regular, design: .serif))
                    .lineSpacing(large ? 10 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("widget.dua.\(dua.id)")
                    #if NOOR_ACCEPTANCE_TESTING
                    .anchorPreference(key: NoorDuaDesignBoundsKey.self, value: .bounds) { ["text": $0] }
                    #endif
                if large || composition == .editorial { Spacer(minLength: 0) }
                if composition == .linear || large {
                    Rectangle().fill(textColor.opacity(0.25)).frame(width: 32, height: 1).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .foregroundStyle(textColor)
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityElement(children: .combine)
        #if NOOR_ACCEPTANCE_TESTING
        .transformAnchorPreference(key: NoorDuaDesignBoundsKey.self, value: .bounds) { value, anchor in
            value["component"] = anchor
        }
        #endif
    }
}
