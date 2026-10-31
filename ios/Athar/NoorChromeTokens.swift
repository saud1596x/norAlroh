import SwiftUI

// App chrome only. Mushaf paper, glyph colors and reader controls retain their
// existing Theme/renderer contracts; these tokens never override that environment.
struct NoorChromeTokens {
    let scheme: ColorScheme
    var background: Color { scheme == .dark ? NoorWidgetPalette.ink : NoorWidgetPalette.ivory }
    var surface: Color { scheme == .dark ? NoorWidgetPalette.surface : Color(red: 251/255, green: 248/255, blue: 241/255) }
    var primary: Color { scheme == .dark ? NoorWidgetPalette.ivory : NoorWidgetPalette.ink }
    var secondary: Color { primary.opacity(0.72) }
    var rule: Color { primary.opacity(0.18) }
    var readingBackground: Color { scheme == .dark ? NoorWidgetPalette.surface : NoorWidgetPalette.ink }
    var readingText: Color { NoorWidgetPalette.ivory }
    enum Space {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let section: CGFloat = 32
    }
    enum TypeStyle {
        static let greeting = Font.system(.title2, design: .serif)
        static let reading = Font.system(.largeTitle, design: .serif)
        static let heading = Font.headline
        static let body = Font.body
        static let supporting = Font.subheadline
    }
    enum Symbol {
        static let reading = "book.closed"
        static let prayer = "sun.horizon"
        static let direction = "arrow.left"
        static let account = "person.crop.circle"
    }
    static let motion = Animation.easeOut(duration: 0.18)
}

struct NoorChromePressStyle: ButtonStyle {
    var lowMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && !lowMotion ? 0.985 : 1)
            .animation(reduceMotion || lowMotion ? nil : NoorChromeTokens.motion, value: configuration.isPressed)
    }
}

struct NoorTodayRouteLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        HStack(spacing: NoorChromeTokens.Space.medium) {
            Image(systemName: symbol).font(.title3).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.tiny) {
                Text(title).font(.headline)
                if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(tokens.secondary) }
            }
            Spacer(minLength: NoorChromeTokens.Space.small)
            Image(systemName: "chevron.left").font(.footnote).accessibilityHidden(true)
        }
        .foregroundStyle(tokens.primary)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, NoorChromeTokens.Space.small)
        .contentShape(Rectangle())
    }
}
