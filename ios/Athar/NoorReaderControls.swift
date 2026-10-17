import SwiftUI

struct NoorReaderUtilityLabel: View {
    let title: String
    let symbol: String
    var selected = false
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium))
            Text(title).font(.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.gold)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Theme.gold.opacity(selected ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// The ring follows measured input, never a decorative/random waveform.
struct NoorReaderMicrophoneFace: View {
    var symbol = "mic.fill"
    var listening = false
    var level: Double = 0
    var busy = false
    var title = "تسميع"
    @Environment(\.accessibilityReduceMotion) private var reduced
    @EnvironmentObject private var store: AtharStore
    private var amount: Double { listening && level.isFinite ? min(1, max(0, level)) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Theme.gold.opacity(0.16 + amount * 0.22), lineWidth: 2)
                .scaleEffect(1 + (reduced || store.data.lowMotion ? 0 : amount * 0.10))
            Circle().fill(Theme.gold.opacity(listening ? 0.18 : 0.10)).padding(5)
            Circle().stroke(Theme.gold.opacity(0.45), lineWidth: 1).padding(5)
            VStack(spacing: 4) {
                if busy { ProgressView().tint(Theme.gold) }
                else { Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.gold) }
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.gold)
            }
        }
        .frame(width: 70, height: 70)
        .animation(reduced || store.data.lowMotion ? nil : .easeOut(duration: 0.12), value: amount)
        .accessibilityHidden(true)
    }
}

struct NoorReaderControlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @EnvironmentObject private var store: AtharStore
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced && !store.data.lowMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduced || store.data.lowMotion ? nil : .spring(duration: 0.22, bounce: 0.12), value: configuration.isPressed)
    }
}
