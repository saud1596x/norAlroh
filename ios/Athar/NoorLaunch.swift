import SwiftUI

struct NoorLaunchGate: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var account: NoorAccountStore
    @EnvironmentObject private var notifications: PrayerNotifications
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var finished = false
    @AppStorage("noor.welcome.completed") private var welcomeCompleted = false
    #if DEBUG || NOOR_ACCEPTANCE_TESTING
    @State private var preparedAcceptanceWelcome = false
    #endif
    private var still: Bool { reduced || store.data.lowMotion || ProcessInfo.processInfo.isLowPowerModeEnabled }
    @ViewBuilder var body: some View {
        #if NOOR_ACCEPTANCE_TESTING
        if let request = NoorAcceptanceDesignRequest.current {
            NoorAcceptanceDesignHost(request: request)
        } else { launchContent }
        #else
        launchContent
        #endif
    }
    private var launchContent: some View {
        ZStack {
            if finished {
                if welcomeCompleted || account.signedIn {
                    RootView().transition(.opacity)
                        .task { await notifications.configureFirstUse(store: store) }
                }
                else { NoorWelcomeView { welcomeCompleted = true }.transition(.opacity) }
            }
            else { NoorLaunchView { finish() }.transition(.opacity) }
        }.background(Theme.background)
            .task(id: phase) {
                guard phase == .active else { return }
                #if DEBUG || NOOR_ACCEPTANCE_TESTING
                if !preparedAcceptanceWelcome {
                    preparedAcceptanceWelcome = true
                    if ProcessInfo.processInfo.arguments.contains("-NoorAcceptanceShowWelcome") {
                        // Reset only this test's first-use flag, never personal data.
                        welcomeCompleted = false
                    }
                }
                #endif
                guard !finished else { return }
                if still { finish(); return }
                do { try await Task.sleep(for: .milliseconds(1250)) }
                catch { return }
                if !Task.isCancelled { finish() }
            }
            .onChange(of: still) { _, value in if value { finish() } }
            .onChange(of: account.signedIn) { _, value in if value { welcomeCompleted = true } }
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
                NoorSanctuaryScene(compact: false)
                Text("نور").font(.system(size: 38, weight: .medium, design: .serif)).foregroundStyle(Theme.gold)
                    .opacity(drawn ? 1 : 0).accessibilityHidden(true)
            }
            .frame(maxWidth: 400).frame(height: 270).clipped()
            VStack(spacing: 12) {
                Text("نور الروح").font(.largeTitle.bold()).foregroundStyle(.primary)
                Text("قرآنٌ، وذكرٌ، وسكينة").font(.subheadline).foregroundStyle(.secondary)
            }.opacity(drawn ? 1 : 0).offset(y: drawn ? 0 : 6)
            Spacer()
            Button("تجاوز الدخولية", action: skip).font(.subheadline).frame(minWidth: 120, minHeight: 44)
                .accessibilityIdentifier("launch.skip")
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
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
