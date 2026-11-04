import SwiftUI
import Combine

/// A decorative sanctuary: nested pointed arches receding toward a lit opening,
/// a faint lattice inside the innermost arch, and a few motes in the light.
///
/// Decoration only. It hosts no controls and no text (never Quran text), is
/// hidden from accessibility, and never blocks hit testing. Its presentation
/// animation is a short opening only; nothing is published to stores.
///
/// Motion runs only while all of these hold: the caller says `active`, the view
/// is on screen, the scene phase is `.active`, and neither system Reduce Motion,
/// the app's low-motion setting, nor Low Power Mode is on. Otherwise it renders
/// a complete, still frame.
public struct NoorSanctuaryScene: View {
    private let active: Bool
    private let compact: Bool

    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme

    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The arches are drawn in once per view lifetime; `choreograph` decides
    /// whether that happens with the opening animation or instantly.
    @State private var opened = false
    @State private var choreograph = false
    @State private var motionGeneration = 0

    public init(active: Bool = true, compact: Bool = false) {
        self.active = active
        self.compact = compact
    }

    private var still: Bool { systemReduce || store.data.lowMotion || lowPower }
    private var running: Bool { active && visible && phase == .active && !still }
    private var palette: SanctuaryPalette { SanctuaryPalette(dark: scheme == .dark) }
    private var archCount: Int { compact ? 3 : 5 }
    private var innermost: Int { archCount - 1 }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [palette.vault, Theme.background], startPoint: .top, endPoint: .bottom)

            // Receding planes: each nested arch adds a little light, so depth reads
            // as brightness toward the opening rather than as heavy shading.
            ForEach(0..<archCount, id: \.self) { index in
                arch(index, closed: true)
                    .fill(palette.glow.opacity(palette.dark ? 0.030 : 0.050))
                    .opacity(opened ? 1 : 0)
                    .animation(stepAnimation(index, duration: 0.7), value: opened)
            }

            SanctuaryLattice(color: palette.line.opacity(palette.dark ? 0.11 : 0.09))
                .mask { arch(innermost, closed: true) }
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                }
                .opacity(opened ? 1 : 0)
                .animation(stepAnimation(innermost, duration: 0.9), value: opened)

            SanctuaryLight(palette: palette, compact: compact, progress: opened ? 1 : 0)
                .opacity(opened ? 1 : 0)
                .animation(choreograph && running ? .easeOut(duration: 2.8) : nil, value: opened)

            ForEach(0..<archCount, id: \.self) { index in
                archStroke(index)
            }
        }
        .id(motionGeneration)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            visible = true
            open()
        }
        .onDisappear { visible = false }
        .onChange(of: running) { _, isRunning in
            guard !isRunning else { return }
            // Recreate the decoration at its final value to cancel an in-flight
            // opening on background, coverage, reduced motion or low power.
            choreograph = false
            motionGeneration += 1
        }
        .onReceive(NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: Arches

    private func arch(_ index: Int, closed: Bool, side: SanctuaryArch.Side = .both) -> SanctuaryArch {
        let step = CGFloat(index)
        return SanctuaryArch(
            widthFraction: 0.94 - step * (compact ? 0.20 : 0.13),
            apexFraction: 0.05 + step * (compact ? 0.09 : 0.065),
            side: side,
            closed: closed)
    }

    /// Two halves rise from the floor and meet at the apex, outer arch first.
    private func archStroke(_ index: Int) -> some View {
        let depth = Double(index) / Double(max(1, innermost))
        let color = palette.line.opacity((palette.dark ? 0.16 : 0.13) + 0.16 * depth)
        let width: CGFloat = index == 0 ? 1.4 : 1
        return ZStack {
            arch(index, closed: false, side: .leading)
                .trim(from: 0, to: opened ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            arch(index, closed: false, side: .trailing)
                .trim(from: 0, to: opened ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        .animation(stepAnimation(index, duration: 0.9), value: opened)
    }

    private func stepAnimation(_ index: Int, duration: Double) -> Animation? {
        choreograph && running ? .easeOut(duration: duration).delay(Double(index) * 0.12) : nil
    }

    /// Opening choreography (about 1.4 s). It never gates content: the scene is a
    /// background, and when motion is not appropriate it appears fully drawn.
    private func open() {
        guard !opened else { return }
        choreograph = active && phase == .active && !still
        opened = true
    }
}

// MARK: - Finite opening light (no timer or perpetual rendering)

private struct SanctuaryLight: View, Animatable {
    let palette: SanctuaryPalette
    let compact: Bool
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let time = min(1, max(0, progress)) * 2.8
            drawShaft(context, size: size)
            drawGlow(context, size: size, time: time)
            if !compact { drawMotes(context, size: size, time: time) }
        }
    }

    private func drawShaft(_ context: GraphicsContext, size: CGSize) {
        let top = size.height * 0.12
        var shaft = Path()
        shaft.move(to: CGPoint(x: size.width * 0.44, y: top))
        shaft.addLine(to: CGPoint(x: size.width * 0.56, y: top))
        shaft.addLine(to: CGPoint(x: size.width * 0.74, y: size.height))
        shaft.addLine(to: CGPoint(x: size.width * 0.26, y: size.height))
        shaft.closeSubpath()
        context.fill(shaft, with: .linearGradient(
            Gradient(colors: [palette.glow.opacity(palette.dark ? 0.16 : 0.30), palette.glow.opacity(0)]),
            startPoint: CGPoint(x: size.width / 2, y: top),
            endPoint: CGPoint(x: size.width / 2, y: size.height)))
    }

    private func drawGlow(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let breath = 0.9 + 0.1 * sin(time / 7)
        let center = CGPoint(x: size.width / 2, y: size.height * (compact ? 0.30 : 0.26))
        let radius = min(size.width, size.height) * (compact ? 0.50 : 0.58)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [palette.glow.opacity((palette.dark ? 0.34 : 0.55) * breath), palette.glow.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius))
    }

    private func drawMotes(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.height > 0 else { return }
        for index in 0..<9 {
            let seed = Double(index) * 0.618_034
            let lane = (seed.truncatingRemainder(dividingBy: 1) - 0.5) * 0.30
            let speed = 7.0 + Double(index % 3) * 3.0            // points per second, rising
            let travel = (time * speed / Double(size.height) + seed).truncatingRemainder(dividingBy: 1)
            let y = size.height * (1 - travel)
            let sway = sin(time / 5 + seed * 6) * 6
            let x = size.width * (0.5 + lane) + sway
            let fade = sin(Double.pi * travel)                      // fade in and out at the ends
            let r: CGFloat = index.isMultiple(of: 4) ? 1.8 : 1.2
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(palette.mote.opacity(0.55 * fade)))
        }
    }
}

// MARK: - Geometry

/// A pointed arch whose rectangle is derived from the scene bounds, so nested
/// arches need no GeometryReader. Its legs run past the bottom edge.
private struct SanctuaryArch: Shape {
    enum Side { case both, leading, trailing }
    var widthFraction: CGFloat
    var apexFraction: CGFloat
    var side: Side = .both
    var closed = false

    func path(in rect: CGRect) -> Path {
        let width = rect.width * max(0.1, widthFraction)
        let minX = rect.midX - width / 2
        let maxX = rect.midX + width / 2
        let apex = CGPoint(x: rect.midX, y: rect.minY + rect.height * apexFraction)
        let spring = apex.y + width * 0.62
        let rise = spring - apex.y
        let bottom = rect.maxY + 4

        let leftUpper = (CGPoint(x: minX, y: spring - rise * 0.58), CGPoint(x: apex.x - width * 0.16, y: apex.y + rise * 0.16))
        let rightUpper = (CGPoint(x: maxX, y: spring - rise * 0.58), CGPoint(x: apex.x + width * 0.16, y: apex.y + rise * 0.16))

        var path = Path()
        switch side {
        case .leading:
            path.move(to: CGPoint(x: minX, y: bottom))
            path.addLine(to: CGPoint(x: minX, y: spring))
            path.addCurve(to: apex, control1: leftUpper.0, control2: leftUpper.1)
        case .trailing:
            path.move(to: CGPoint(x: maxX, y: bottom))
            path.addLine(to: CGPoint(x: maxX, y: spring))
            path.addCurve(to: apex, control1: rightUpper.0, control2: rightUpper.1)
        case .both:
            path.move(to: CGPoint(x: minX, y: bottom))
            path.addLine(to: CGPoint(x: minX, y: spring))
            path.addCurve(to: apex, control1: leftUpper.0, control2: leftUpper.1)
            path.addCurve(to: CGPoint(x: maxX, y: spring), control1: rightUpper.1, control2: rightUpper.0)
            path.addLine(to: CGPoint(x: maxX, y: bottom))
            if closed { path.closeSubpath() }
        }
        return path
    }
}

/// A static lattice of eight-point stars (two overlapping squares), drawn once.
private struct SanctuaryLattice: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 26
            let radius = step * 0.34
            var path = Path()
            var row = 0
            var y = step / 2
            while y < size.height + step {
                var x = row.isMultiple(of: 2) ? step / 2 : step
                while x < size.width + step {
                    for turn in 0..<2 {
                        let offset = Double(turn) * .pi / 4
                        for corner in 0..<4 {
                            let angle = offset + Double(corner) * .pi / 2
                            let point = CGPoint(x: x + CGFloat(cos(angle)) * radius, y: y + CGFloat(sin(angle)) * radius)
                            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        path.closeSubpath()
                    }
                    x += step
                }
                y += step * 0.87
                row += 1
            }
            context.stroke(path, with: .color(color), lineWidth: 0.6)
        }
    }
}

// MARK: - Palette

/// Scene-local colors. Lines reuse `Theme.gold` so the bronze identity follows
/// the app's existing light/dark values; nothing here replaces `Theme`.
private struct SanctuaryPalette {
    let dark: Bool
    var vault: Color { dark ? Color(red: 0.075, green: 0.052, blue: 0.035) : Color(red: 0.990, green: 0.962, blue: 0.905) }
    var line: Color { Theme.gold }
    var glow: Color { dark ? Color(red: 0.98, green: 0.82, blue: 0.56) : Color(red: 1.0, green: 0.975, blue: 0.91) }
    var mote: Color { dark ? Color(red: 1.0, green: 0.88, blue: 0.66) : Color(red: 0.62, green: 0.42, blue: 0.18) }
}
