import SwiftUI
import UIKit

@main
struct AtharApp: App {
    @StateObject private var store = AtharStore()
    @StateObject private var notifications = PrayerNotifications()
    @StateObject private var dhikrCounters = DhikrCounterStore()
    @StateObject private var memorization = MemorizationStore()
    @StateObject private var recitation = LocalRecitationRecorder()
    @StateObject private var speech = LocalSpeechRecitation()
    @StateObject private var friday = FridayStore()
    @StateObject private var fridayAlarms = FridayAlarms()
    @StateObject private var account = NoorAccountStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some Scene {
        WindowGroup {
            NoorLaunchGate()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(dhikrCounters)
                .environmentObject(memorization)
                .environmentObject(recitation)
                .environmentObject(speech)
                .environmentObject(friday)
                .environmentObject(fridayAlarms)
                .environmentObject(account)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .preferredColorScheme(nil)
                .onOpenURL { account.handle($0) }
                .tint(Theme.mint)
                .transaction { if reducedMotion || store.data.lowMotion { $0.disablesAnimations = true } }
                .task { dhikrCounters.refreshDay(); NoorFocusController.shared.sync(progress: memorization.progress); await notifications.refresh(store: store); await friday.refresh(data: store.data); await fridayAlarms.schedule(data: store.data, preferences: friday.preferences); await account.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        NoorFocusController.shared.sync(progress: memorization.progress)
                        dhikrCounters.refreshDay()
                        Task { await notifications.refresh(store: store); await friday.refresh(data: store.data); await fridayAlarms.schedule(data: store.data, preferences: friday.preferences); await account.refresh() }
                    } else {
                        if speech.listening || phase == .background { speech.stop() }
                        if phase == .background { recitation.stop() }
                    }
                }
        }
    }
}

enum Theme {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.10, blue: 0.07, alpha: 1) : UIColor(red: 0.945, green: 0.886, blue: 0.776, alpha: 1) })
    static let panel = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.22, green: 0.16, blue: 0.10, alpha: 1) : UIColor(red: 1, green: 0.969, blue: 0.914, alpha: 1) })
    static let gold = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.92, green: 0.76, blue: 0.52, alpha: 1) : UIColor(red: 0.45, green: 0.267, blue: 0.078, alpha: 1) })
    static let mint = gold
    static let buttonInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.10, blue: 0.07, alpha: 1) : UIColor(red: 1, green: 0.973, blue: 0.914, alpha: 1) })
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
            .noorEntrance()
    }
}

struct PrimaryButton: View {
    let title: String
    var icon = "sparkles"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(NoorPrimaryStyle())
        .tint(Theme.mint)
        .foregroundStyle(Theme.buttonInk)
    }
}

struct RootView: View {
    @EnvironmentObject var store: AtharStore
    @State private var settings = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { NoorTodayView().settingsAccess { settings = true } }
                .tabItem { Label("اليوم", systemImage: "house") }
                .tag(0)
            NavigationStack { QuranView().settingsAccess { settings = true } }
                .tabItem { Label("المصحف", systemImage: "book") }
                .tag(1)
            NavigationStack { PrayerView().settingsAccess { settings = true } }
                .tabItem { Label("الصلاة", systemImage: "sun.horizon") }
                .tag(2)
            NavigationStack { AdhkarView().settingsAccess { settings = true } }
                .tabItem { Label("الأذكار", systemImage: "sun.max") }
                .tag(3)
            NavigationStack { MemorizationView().settingsAccess { settings = true } }
                .tabItem { Label("الحفظ", systemImage: "sparkles") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
        .alert("تعذر حفظ بياناتك", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } }
        )) { Button("حسنًا") { store.error = nil } } message: {
            Text(store.error ?? "")
        }
    }
}

extension View {
    func settingsAccess(action: @escaping () -> Void) -> some View {
        // Keep account-free settings reachable on each tab root after a child
        // navigation screen is popped, independently of toolbar restoration.
        safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button(action: action) {
                    Label("الإعدادات والخصوصية", systemImage: "gearshape")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .accessibilityIdentifier("app.settings")
            }
            .padding(.horizontal, 20)
            .background(Theme.background)
        }
    }
}
