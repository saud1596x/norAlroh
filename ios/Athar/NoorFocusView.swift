import SwiftUI
#if NOOR_FOCUS_ENABLED
import FamilyControls
import DeviceActivity
import ManagedSettings
#endif

extension NoorKhatmahWardContract {
    init(plan: KhatmahPlan) {
        self.init(planID: plan.id, firstPage: plan.days.first?.first ?? plan.firstPage,
            timeZone: plan.timeZone, days: plan.days.map { .init(date: $0.date, first: $0.first, last: $0.last) }, nextPage: plan.nextPage)
    }
}

@MainActor final class NoorFocusController: ObservableObject {
    static let shared = NoorFocusController()
    @Published private(set) var enabled = false
    @Published var message: String?
    #if NOOR_FOCUS_ENABLED
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorizing = false
    @Published private(set) var authorized = false
    private var state = NoorFocusState.load() ?? NoorFocusState()
    var contract: NoorKhatmahWardContract? { state.khatmahContract }
    private init() {
        selection = state.selection; enabled = state.enabled; refreshAuthorization()
        if enabled && state.khatmahContract == nil {
            disable(); message = "أوقفنا حماية الحفظ السابقة. اربط الحماية بختمتك من هذه الصفحة."
        }
        // Reconcile this app's store even when a saved state is unreadable or
        // disabled; an old shield must not outlive the contract that owns it.
        NoorFocusState.apply()
    }
    func refreshAuthorization() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if !authorized && enabled { disable() }
    }
    func authorize() async {
        guard !authorizing else { return }; authorizing = true; defer { authorizing = false }
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); refreshAuthorization() }
        catch { message = "لم يُمنح إذن حماية الورد. يمكنك المحاولة مجددًا من هذه الصفحة." }
    }
    func enable(plan: KhatmahPlan?) {
        guard !enabled else { return }
        refreshAuthorization()
        guard authorized else { message = "امنح إذن مدة استخدام الجهاز أولًا."; return }
        guard selection.categoryTokens.isEmpty, !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty else {
            message = "اختر تطبيقات التواصل أو مواقعها بشكل منفرد، دون تحديد فئات كاملة."; return
        }
        guard let plan, plan.valid, !plan.paused, plan.finished == nil else {
            message = "أعدّ خطة ختمة نشطة أولًا، ثم اختر تطبيقاتك وفعّل الحماية."; return
        }
        var next = state
        next.selection = selection
        next.contract = nil
        next.khatmahContract = NoorKhatmahWardContract(plan: plan)
        guard let contract = next.khatmahContract, contract.valid else { message = "اختر خطة ختمة صالحة أولًا."; return }
        next.enabled = true; next.completedDay = nil
        do {
            // Register the background callback before making any restriction active.
            try DeviceActivityCenter().startMonitoring(NoorFocusState.activity, during: DeviceActivitySchedule(
                intervalStart: contract.monitoringStart, intervalEnd: contract.monitoringEnd, repeats: true))
            try next.save(); state = next; enabled = true; NoorFocusState.apply()
        } catch {
            DeviceActivityCenter().stopMonitoring([NoorFocusState.activity])
            ManagedSettingsStore(named: NoorFocusState.storeName).clearAllSettings()
            message = "تعذّر تفعيل حماية الورد. لم نُبقِ التطبيقات محجوبة. حاول مجددًا."
        }
    }
    func sync(plan: KhatmahPlan?) {
        refreshAuthorization(); guard enabled else { return }
        var next = state
        if let plan, plan.valid { next.khatmahContract?.confirm(planID: plan.id, nextPage: plan.nextPage) }
        do { try next.save(); state = next; NoorFocusState.apply(); objectWillChange.send() }
        catch { message = "تعذّر تحديث إنجاز الورد. أوقف الحماية من هذه الصفحة ثم أعد تفعيلها." }
    }
    @discardableResult func erase() -> Bool {
        DeviceActivityCenter().stopMonitoring([NoorFocusState.activity])
        ManagedSettingsStore(named: NoorFocusState.storeName).clearAllSettings()
        enabled = false
        guard NoorFocusPersistence.erase() else {
            message = "أزلنا الحجب، لكن تعذّر مسح إعدادات الحماية. حاول مجددًا."; return false
        }
        state = NoorFocusState(); selection = FamilyActivitySelection(); message = nil
        return true
    }
    // Hifz results do not unlock a protected khatmah.
    func sync(progress: MemorizationProgress) {}
    func disable() {
        DeviceActivityCenter().stopMonitoring([NoorFocusState.activity])
        ManagedSettingsStore(named: NoorFocusState.storeName).clearAllSettings()
        state.enabled = false; state.completedDay = nil; state.khatmahContract = nil; state.contract = nil
        do { try state.save(); enabled = false }
        catch { enabled = false; message = "أزلنا الحجب، لكن تعذّر حفظ الإعدادات. راجع إذن مدة استخدام الجهاز." }
    }
    #else
    private init() {}
    var contract: NoorKhatmahWardContract? { nil }
    @discardableResult func erase() -> Bool { NoorFocusPersistence.erase() }
    func sync(plan: KhatmahPlan?) {}
    func sync(progress: MemorizationProgress) {}
    func disable() {}
    #endif
}

struct NoorFocusView: View {
    @EnvironmentObject private var journey: KhatmahStore
    @StateObject private var focus = NoorFocusController.shared
    @Environment(\.scenePhase) private var phase
    #if NOOR_FOCUS_ENABLED
    @State private var choosing = false
    #endif
    var body: some View {
        Form {
            Section {
                Label("وردك قبل التواصل", systemImage: "lock.shield").font(.title2.bold())
                Text("اربط حماية التطبيقات بختمتك. تُحجب التطبيقات التي تختارها حتى تؤكد قراءة صفحات الورد المستحقة، ثم يُرفع الحجب تلقائيًا.")
                Text("فتح المصحف وحده لا يفتح التطبيقات. التأكيد يحفظ قراءتك، ولا يقيّم الحفظ أو التجويد.").font(.caption).foregroundStyle(.secondary)
            }
            Section("١ · خطة الختمة والورد المحمي") {
                if let plan = journey.active {
                    Text("قرأت \(plan.completed.count) صفحة · المتابعة من الصفحة \(min(plan.nextPage, 604))")
                    if !focus.enabled, let due = plan.due(on: .now) {
                        let future = plan.calendar.startOfDay(for: due.date) > plan.calendar.startOfDay(for: .now)
                        Text("\(future ? "ورد الختمة القادم" : "الورد المستحق"): الصفحات \(due.first)–\(due.last)").font(.headline)
                        if future { Text("تكون التطبيقات متاحة حتى يوم هذا الورد؛ يمكنك القراءة مبكرًا وتأكيدها.").font(.caption) }
                    }
                    if plan.paused { Text("الختمة متوقفة مؤقتًا؛ أوقف الحماية بشكل مستقل إذا أردت استراحة.") }
                } else { Text("ابدأ خطة ختمة لتحديد صفحات وردك وأيام القراءة.") }
                if let contract = focus.contract {
                    if let ward = contract.ward(at: .now) {
                        Text("الورد المحمي: الصفحات \(ward.first)–\(ward.last)").font(.headline)
                    } else { Text(contract.finished ? "أتممت الختمة؛ التطبيقات متاحة" : "لا توجد صفحات مستحقة الآن؛ التطبيقات متاحة") }
                }
                NavigationLink("فتح رحلة الختمة") { KhatmahJourneyView() }.accessibilityIdentifier("focus.khatmah")
            }
            #if NOOR_FOCUS_ENABLED
            Section("٢ · الإذن واختيار التطبيقات") {
                if !focus.authorized {
                    Button("السماح بحماية وقت الورد") { Task { await focus.authorize() } }.disabled(focus.authorizing)
                } else {
                    Button("اختيار تطبيقات التواصل") { choosing = true }.disabled(focus.enabled)
                    Text("\(focus.selection.applicationTokens.count) تطبيقات · \(focus.selection.webDomainTokens.count) مواقع مختارة")
                    if focus.enabled {
                        Label("الحماية مفعلة", systemImage: "checkmark.shield")
                        Button("إيقاف الحماية", role: .destructive) { focus.disable() }
                    } else {
                        Button("٣ · تفعيل حماية ورد الختمة") { focus.enable(plan: journey.active) }
                    }
                }
                Text("جدول الصفحات ثابت أثناء الحماية؛ تعديل الخطة أو إيقافها مؤقتًا لا يلغي الصفحات المحمية. أوقف الحماية لتغيير الجدول. في الأيام دون ورد مستحق تكون التطبيقات متاحة، ويبدأ الحجب مجددًا مع الورد التالي.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section {
                Text("حماية التطبيقات غير متاحة في هذه النسخة. نجهّز النسخة التي تحتاج إذن مدة استخدام الجهاز قبل إتاحتها.")
            }
            #endif
            Section("أنت تتحكم") {
                Text("هذه حماية اختيارية، ويمكنك إيقافها هنا أو سحب الإذن من إعدادات الجهاز. اختر تطبيقات التواصل التي تشتتك فقط، واترك نور الروح وتطبيقات الهاتف والطوارئ خارج اختياراتك.")
            }
        }.navigationTitle("حماية وقت الورد")
        #if NOOR_FOCUS_ENABLED
            .familyActivityPicker(isPresented: $choosing, selection: $focus.selection)
            .onAppear { focus.sync(plan: journey.active) }
            .onChange(of: phase) { _, new in if new == .active { focus.sync(plan: journey.active) } }
        #endif
            .alert("حماية الورد", isPresented: Binding(get: { focus.message != nil }, set: { if !$0 { focus.message = nil } })) {
                Button("تم") { focus.message = nil }
            } message: { Text(focus.message ?? "") }
    }
}

struct NoorKhatmahProtectionCard: View {
    @StateObject private var focus = NoorFocusController.shared
    @EnvironmentObject private var journey: KhatmahStore
    var body: some View {
        NavigationLink { NoorFocusView() } label: {
            Card {
                Label("حماية وقت الورد", systemImage: "lock.shield").font(.headline)
                Text(focus.enabled ? "الحماية مفعّلة ومرتبطة بختمتك" : "أكمل ورد ختمتك قبل تطبيقات التواصل").font(.subheadline)
                if let ward = focus.contract?.ward(at: .now) {
                    Text("الصفحات \(ward.first)–\(ward.last) · التأكيد يفتح التطبيقات").font(.caption)
                } else {
                    Text(focus.enabled ? "التطبيقات متاحة حتى الورد المستحق التالي" : journey.active == nil ? "ابدأ ختمة، ثم اختر التطبيقات وفعّل الحماية" : "اختر التطبيقات التي تشتتك وفعّل الحماية").font(.caption)
                }
                Text("إدارة الحماية").font(.subheadline.bold()).foregroundStyle(Theme.gold)
            }.foregroundStyle(.primary)
        }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("khatmah.protection")
    }
}
