import SwiftUI

struct NoorLaunchGate: View {
    @EnvironmentObject private var store: AtharStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var finished = false
    private var still: Bool { reduced || store.data.lowMotion || ProcessInfo.processInfo.isLowPowerModeEnabled }
    var body: some View {
        ZStack {
            if finished { RootView().transition(.opacity) }
            else { NoorLaunchView { finish() }.transition(.opacity) }
        }.background(Theme.background)
            .task(id: phase) {
                guard !finished, phase == .active else { return }
                if still { finish(); return }
                do { try await Task.sleep(for: .milliseconds(1250)) }
                catch { return }
                if !Task.isCancelled { finish() }
            }
            .onChange(of: still) { _, value in if value { finish() } }
    }
    private func finish() {
        guard !finished else { return }
        withAnimation(still ? nil : .easeOut(duration: 0.25)) { finished = true }
    }
}

struct NoorLaunchView: View {
    let skip: () -> Void
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @EnvironmentObject private var store: AtharStore
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                NoorMotionSurface().frame(width: 280, height: 280).clipped()
                Circle().fill(RadialGradient(colors: [Theme.gold.opacity(0.12), .clear], center: .center, startRadius: 10, endRadius: 130))
                    .frame(width: 260, height: 260).accessibilityHidden(true)
                NoorArch().trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Theme.gold.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 170, height: 205).accessibilityHidden(true)
                NoorRosette().stroke(Theme.gold.opacity(0.22), lineWidth: 1)
                    .frame(width: 94, height: 94).rotationEffect(.degrees(drawn ? 0 : -8))
                    .scaleEffect(drawn ? 1 : 0.92).accessibilityHidden(true)
                Text("نور").font(.system(size: 38, weight: .medium, design: .serif)).foregroundStyle(Theme.gold)
                    .opacity(drawn ? 1 : 0).accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                Text("نور الروح").font(.largeTitle.bold()).foregroundStyle(.primary)
                Text("قرآنٌ، وذكرٌ، وسكينة").font(.subheadline).foregroundStyle(.secondary)
            }.opacity(drawn ? 1 : 0).offset(y: drawn ? 0 : 6)
            Spacer()
            Button("تجاوز الدخولية", action: skip).font(.subheadline).frame(minWidth: 120, minHeight: 44)
                .accessibilityIdentifier("launch.skip")
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .accessibilityIdentifier("launch.intro")
            .onAppear {
                withAnimation(reduced || store.data.lowMotion ? nil : .easeInOut(duration: 0.85)) { drawn = true }
            }
    }
}

/// A vector arch; no image, 3D model or religious text is used in the animation.
struct NoorArch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
