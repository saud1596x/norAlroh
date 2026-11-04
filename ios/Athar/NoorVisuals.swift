import SwiftUI

/// Motion belongs to decoration and controls; Quran glyphs are never animated.
struct NoorMotionSurface: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var ink: Color
    var starfield: Bool
    init(ink: Color = Theme.gold, starfield: Bool = false) {
        self.ink = ink
        self.starfield = starfield
    }
    private var still: Bool { reduced || store.data.lowMotion || lowPower }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: still || !visible || phase != .active)) { timeline in
            Canvas { context, size in
                let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                if starfield {
                    drawStars(context, size: size, time: t)
                    return
                }
                let drift = CGFloat(sin(t / 12)) * 4
                for index in 0..<4 {
                    let inset = CGFloat(index) * 20
                    var arch = Path()
                    let x = size.width * 0.80 + drift
                    arch.move(to: CGPoint(x: x - 65 - inset, y: size.height + 30))
                    arch.addLine(to: CGPoint(x: x - 65 - inset, y: size.height * 0.54))
                    arch.addQuadCurve(to: CGPoint(x: x, y: 12 - inset), control: CGPoint(x: x - 65 - inset, y: 25 - inset))
                    arch.addQuadCurve(to: CGPoint(x: x + 65 + inset, y: size.height * 0.54), control: CGPoint(x: x + 65 + inset, y: 25 - inset))
                    arch.addLine(to: CGPoint(x: x + 65 + inset, y: size.height + 30))
                    context.stroke(arch, with: .color(ink.opacity(0.06 - Double(index) * 0.01)), lineWidth: 1)
                }
            }
        }.onAppear { visible = true }.onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func drawStars(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<44 {
            let x = CGFloat((index * 71 + 13) % 101) / 101
            let y = CGFloat((index * 47 + 19) % 109) / 109
            let phase = Double(index) * 0.87
            let shimmer = (1 + sin(time * 0.65 + phase)) / 2
            let drift = CGFloat(sin(time * 0.12 + phase)) * 4
            let radius: CGFloat = index.isMultiple(of: 9) ? 1.35 : 0.7
            let rect = CGRect(x: x * size.width + drift, y: y * size.height - drift,
                              width: radius * 2, height: radius * 2)
            let color = ink.opacity(0.22 + 0.34 * shimmer)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

/// Decorative only. Its timeline is owned by the backdrop, outside content state.
struct NoorNightBackdrop: View {
    let base: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            dark ? Color.black : base
            RadialGradient(colors: [Theme.mint.opacity(dark ? 0.20 : 0.09), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 420)
            NoorMotionSurface(ink: dark ? Color(red: 0.66, green: 0.99, blue: 0.92) : Theme.gold,
                              starfield: true)
                .opacity(dark ? 0.75 : 0.40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
