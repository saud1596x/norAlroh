import SwiftUI

struct NoorProgressBar: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    let value: Double
    var label = "التقدم"
    var height: CGFloat = 8
    private var progress: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.gold.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [Theme.gold.opacity(0.7), Theme.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }.frame(height: height)
            .animation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.35, bounce: 0.05), value: progress)
            .accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue("\(Int(progress * 100)) بالمئة")
    }
}

struct NoorCompletionMark: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var shown = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.gold.opacity(0.08))
            Circle().trim(from: 0, to: shown ? 1 : 0)
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(Theme.gold)
                .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.7)
        }.frame(width: 64, height: 64).accessibilityHidden(true)
            .onAppear { withAnimation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.55, bounce: 0.12)) { shown = true } }
    }
}

struct NoorPrimaryStyle: ButtonStyle {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Theme.buttonInk)
            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.buttonInk.opacity(configuration.isPressed ? 0.3 : 0.1), lineWidth: 1) }
            .opacity(enabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduced && !store.data.lowMotion ? 0.97 : 1)
            .animation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.25, bounce: 0.1), value: configuration.isPressed)
    }
}
