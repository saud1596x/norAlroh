import SwiftUI

struct NoorTodayReadingPanel<Action: View>: View {
    let title: String
    let detail: String
    let status: String?
    let composition: NoorDuaComposition
    @ViewBuilder let action: Action
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    private var textColor: Color { composition == .najdi ? tokens.readingText : tokens.primary }
    var body: some View {
        HStack(alignment: .top, spacing: NoorChromeTokens.Space.medium) {
            if composition == .najdi {
                NoorNajdiEdge().stroke(textColor.opacity(0.28), lineWidth: 1)
                    .frame(width: 8).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.medium) {
                Label("موعدك مع القرآن", systemImage: NoorChromeTokens.Symbol.reading)
                    .font(.subheadline).foregroundStyle(textColor.opacity(0.8))
                if composition == .editorial { Text("اقرأ").font(.system(.largeTitle, design: .serif)).bold() }
                Text(title).font(NoorChromeTokens.TypeStyle.reading).bold()
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.body).foregroundStyle(textColor.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let status { Label(status, systemImage: "checkmark.circle").font(.headline) }
                if status == nil {
                    action
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(textColor)
        .padding(composition == .linear ? NoorChromeTokens.Space.small : NoorChromeTokens.Space.large)
        .background {
            if composition == .najdi { tokens.readingBackground.clipShape(RoundedRectangle(cornerRadius: 12)) }
            else if composition == .editorial { tokens.surface }
        }
        .overlay(alignment: .top) {
            if composition == .linear { Rectangle().fill(tokens.rule).frame(height: 1).accessibilityHidden(true) }
        }
    }
}

// Compositions differ in hierarchy and placement, not only color. This is the
// production Today masthead/reading/prayer composition, also used by previews.
struct NoorTodayComposition<ReadingAction: View, AccountAction: View, PrayerAction: View>: View {
    let greeting: String
    let dateText: String
    let readingTitle: String
    let readingDetail: String
    let readingStatus: String?
    var composition: NoorDuaComposition = .najdi
    @ViewBuilder let readingAction: ReadingAction
    @ViewBuilder let accountAction: AccountAction
    @ViewBuilder let prayerAction: PrayerAction
    @Environment(\.colorScheme) private var scheme
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.large) {
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
                HStack(alignment: .center, spacing: NoorChromeTokens.Space.medium) {
                    Text("نور الروح").font(.headline).foregroundStyle(tokens.primary)
                    Spacer(minLength: 8)
                    accountAction
                }
                Text(greeting).font(NoorChromeTokens.TypeStyle.greeting).foregroundStyle(tokens.primary)
                Text(dateText).font(.subheadline).foregroundStyle(tokens.secondary)
            }
            if composition == .editorial { prayerAction }
            NoorTodayReadingPanel(title: readingTitle, detail: readingDetail, status: readingStatus,
                composition: composition) { readingAction }
            if composition != .editorial { prayerAction }
        }.environment(\.layoutDirection, .rightToLeft)
    }
}
