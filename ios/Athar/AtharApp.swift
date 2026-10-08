import SwiftUI
import UIKit

@main
struct AtharApp: App {
    @StateObject private var khatmah = KhatmahStore.shared
    @StateObject private var store = AtharStore()
    @StateObject private var notifications = PrayerNotifications()
    @StateObject private var prayerLocation = PrayerLocationController()
    @StateObject private var dhikrCounters = DhikrCounterStore()
    @StateObject private var memorization = MemorizationStore()
    @StateObject private var recitation = LocalRecitationRecorder()
    @StateObject private var speech = LegacySpeechArchive()
    @StateObject private var retiredFriday = NoorRetiredFridayCleanup()
    @StateObject private var account = NoorAccountStore()
    @StateObject private var widgetRouter = NoorWidgetRouter.shared
    @AppStorage("noor.mushaf.lastPage") private var widgetPage = 1
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some Scene {
        WindowGroup {
            NoorLaunchGate()
                .environmentObject(store)
                .task { await retiredFriday.cleanup(); await khatmah.refreshReminders() }
                .environmentObject(notifications)
                .environmentObject(prayerLocation)
                .environmentObject(dhikrCounters)
                .environmentObject(memorization)
                .environmentObject(recitation)
                .environmentObject(speech)
                .environmentObject(retiredFriday)
                .environmentObject(account)
                .environmentObject(widgetRouter)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .preferredColorScheme(nil)
                .onOpenURL { if !widgetRouter.open($0) { account.handle($0) } }
                .onReceive(store.$data) { data in
                    NoorWidgetBridge.publish(data: data, memorization: memorization, page: widgetPage)
                    Task { @MainActor in account.captureLocalChanges() }
                }
                .onChange(of: account.uid) { _, _ in account.authenticationChanged() }
                .onReceive(memorization.$session.dropFirst()) { value in if value == nil { Task { @MainActor in account.captureLocalChanges() } } }
                .onReceive(memorization.$practice.dropFirst()) { value in if value == nil { Task { @MainActor in account.captureLocalChanges() } } }
                .onReceive(memorization.$progress.dropFirst()) { _ in
                    Task { @MainActor in
                        NoorWidgetBridge.publish(data: store.data, memorization: memorization, page: widgetPage)
                        account.captureLocalChanges(memoryChanged: true)
                    }
                }
                .onReceive(memorization.$plan.dropFirst()) { _ in
                    Task { @MainActor in NoorWidgetBridge.publish(data: store.data, memorization: memorization, page: widgetPage); account.captureLocalChanges(planChanged: true) }
                }
                .onChange(of: widgetPage) { _, page in NoorWidgetBridge.publish(data: store.data, memorization: memorization, page: page); account.captureLocalChanges() }
                .tint(Theme.mint)
                .transaction { if reducedMotion || store.data.lowMotion { $0.disablesAnimations = true } }
                .onChange(of: store.data.prayerScheduleKey, initial: true) { _, _ in
                    Task {
                        await notifications.refresh(store: store)
                        PrayerBackgroundRefresh.submit()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await notifications.refresh(store: store) }
                }
                .task { account.attach(store: store, memorization: memorization); prayerLocation.activate(store: store); dhikrCounters.refreshDay(); NoorFocusController.shared.sync(progress: memorization.progress); await notifications.refresh(store: store); await retiredFriday.cleanup(); await account.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await khatmah.refreshReminders() }
                        account.attach(store: store, memorization: memorization)
                        prayerLocation.activate(store: store)
                        PrayerBackgroundRefresh.submit()
                        NoorFocusController.shared.sync(progress: memorization.progress)
                        dhikrCounters.refreshDay()
                        Task { await notifications.refresh(store: store); await retiredFriday.cleanup(); await account.refresh() }
                    } else {
                        if phase == .background { account.enterBackground(); recitation.stop(); prayerLocation.deactivate(); PrayerBackgroundRefresh.submit() }
                    }
                }
        }
        .backgroundTask(.appRefresh(PrayerBackgroundRefresh.identifier)) {
            await notifications.refresh(store: store)
            await retiredFriday.cleanup()
            PrayerBackgroundRefresh.submit()
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
    @EnvironmentObject private var widgetRouter: NoorWidgetRouter
    @State private var widgetDestination: NoorWidgetRouter.Destination?
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
        .onChange(of: widgetRouter.destination?.id, initial: true) { _, _ in
            guard let destination = widgetRouter.destination else { return }
            settings = false
            switch destination.host {
            case "prayers": selectedTab = 2
            case "dhikr": selectedTab = 3
            case "reading": selectedTab = 1; widgetDestination = destination
            case "review": selectedTab = 4; widgetDestination = destination
            default: selectedTab = 4
            }
            widgetRouter.destination = nil
        }
        .fullScreenCover(item: $widgetDestination) { destination in
            if destination.host == "reading" {
                InteractiveMushafReader(chapter: 1, ayah: 1, initialPage: destination.page)
            } else {
                NavigationStack {
                    MemorizationTestView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { widgetDestination = nil } } }
                }
            }
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
