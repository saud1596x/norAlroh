import SwiftUI

struct NoorEntrance: ViewModifier {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var visible = false
    var delay: Double
    func body(content: Content) -> some View {
        content.opacity(visible || reduced || store.data.lowMotion ? 1 : 0)
            .offset(y: visible || reduced || store.data.lowMotion ? 0 : 12)
            .onAppear {
                withAnimation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.55, bounce: 0.08).delay(delay)) { visible = true }
            }
            .onDisappear { visible = false }
    }
}
extension View {
    func noorEntrance(delay: Double = 0) -> some View { modifier(NoorEntrance(delay: delay)) }
}
struct NoorPressStyle: ButtonStyle {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduced && !store.data.lowMotion ? 0.975 : 1)
            .animation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.25, bounce: 0.1), value: configuration.isPressed)
    }
}
struct NoorAmbientOrnament: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var ink: Color = Theme.gold
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || store.data.lowMotion || lowPower || !visible || phase != .active)) { context in
            let t = reduced || store.data.lowMotion ? 0 : context.date.timeIntervalSince1970
            NoorRosette().stroke(ink.opacity(0.12), lineWidth: 1)
                .rotationEffect(.degrees(sin(t / 12) * 12))
                .scaleEffect(1 + CGFloat(sin(t / 6)) * 0.025)
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

enum ArabicSearch {
    static func digits(_ value: Int) -> String {
        let numerals = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).map { character in
            character.wholeNumberValue.map { numerals[$0] } ?? character
        })
    }
    static func integer(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 9 else { return nil }
        var digits = ""
        for character in trimmed {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            digits += String(value)
        }
        return Int(digits)
    }
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
        // Foundation's diacritic folding alone does not consistently remove Arabic vowel marks.
        let unmarked = String(String.UnicodeScalarView(folded.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: return false
            default: return true
            }
        }))
        return unmarked
            .replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression)
            .replacingOccurrences(of: "[\u{0640}\u{200E}\u{200F}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "ى", with: "ي")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
