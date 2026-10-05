import SwiftUI

/// Motion belongs to decoration and controls; Quran glyphs are never animated.
struct NoorMotionSurface: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var ink = Theme.gold
    private var still: Bool { reduced || store.data.lowMotion || lowPower }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: still || !visible || phase != .active)) { timeline in
            Canvas { context, size in
                let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let drift = CGFloat(sin(t / 8)) * 5
                for index in 0..<4 {
                    let inset = CGFloat(index) * 20
                    var arch = Path()
                    let x = size.width * 0.80 + drift
                    arch.move(to: CGPoint(x: x - 65 - inset, y: size.height + 30))
                    arch.addLine(to: CGPoint(x: x - 65 - inset, y: size.height * 0.54))
                    arch.addQuadCurve(to: CGPoint(x: x, y: 12 - inset), control: CGPoint(x: x - 65 - inset, y: 25 - inset))
                    arch.addQuadCurve(to: CGPoint(x: x + 65 + inset, y: size.height * 0.54), control: CGPoint(x: x + 65 + inset, y: 25 - inset))
                    arch.addLine(to: CGPoint(x: x + 65 + inset, y: size.height + 30))
                    context.stroke(arch, with: .color(ink.opacity(0.10 - Double(index) * 0.015)), lineWidth: 1)
                }
            }
        }.onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NoorAnimatedSymbol: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var arrival = 0
    let name: String
    var body: some View {
        Image(systemName: name).symbolEffect(.bounce, options: .speed(0.8), value: arrival)
            .onAppear { if !reduced && !store.data.lowMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled { arrival += 1 } }
    }
}

struct NoorProgressDial: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var drawn = 0.0
    let value: Double
    private var progress: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Theme.gold.opacity(0.12), lineWidth: 5)
            Circle().trim(from: 0, to: drawn)
                .stroke(AngularGradient(colors: [Theme.gold.opacity(0.5), Theme.gold], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.task(id: progress) {
            withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.7)) { drawn = progress }
        }.accessibilityHidden(true)
    }
}
