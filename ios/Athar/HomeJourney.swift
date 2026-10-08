import SwiftUI
import Combine

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var remaining = 60
    @State private var running = false
    @State private var deadline = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Text("كن هنا، للحظة.").font(.largeTitle.bold())
            Text("استراحة عامة للهدوء. تنفّس بصورة طبيعية، دون ممارسة تعبدية مخصوصة.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("\(remaining)").font(.system(.largeTitle, design: .rounded).monospacedDigit())
                .frame(width: 160, height: 160)
                .background(Theme.mint.opacity(0.15), in: Circle())
                .accessibilityLabel("الوقت المتبقي \(remaining) ثانية")
            PrimaryButton(title: remaining == 0 ? "ابدأ مجددًا" : running ? "إيقاف مؤقت" : "ابدأ الدقيقة", icon: "timer") {
                if remaining == 0 { remaining = 60 }
                running.toggle()
                if running { deadline = Date().addingTimeInterval(TimeInterval(remaining)) }
            }
            Spacer()
        }.padding(24)
        .background(Theme.background)
        .navigationTitle("دقيقة حضور")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
        .onReceive(timer) { now in
            guard running else { return }
            remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            if remaining == 0 { running = false }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { running = false } }
    }
}
