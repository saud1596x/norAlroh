import SwiftUI
#if NOOR_FOCUS_ENABLED
import FamilyControls
import DeviceActivity
import ManagedSettings
#endif

@MainActor final class NoorFocusController: ObservableObject {
    static let shared = NoorFocusController()
    @Published private(set) var enabled = false
    @Published var message: String?
    #if NOOR_FOCUS_ENABLED
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorizing = false
    @Published private(set) var authorized = false
    private var state = NoorFocusState.load() ?? NoorFocusState()
    private init() { selection = state.selection; enabled = state.enabled; refreshAuthorization() }
    func refreshAuthorization() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if !authorized && enabled { disable() }
    }
    func authorize() async {
        guard !authorizing else { return }; authorizing = true; defer { authorizing = false }
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); refreshAuthorization() }
        catch { message = "لم يُمنح إذن حماية الورد. يمكنك المحاولة مجددًا من هذه الصفحة." }
    }
    func enable(plan: MemorizationPlan, progress: MemorizationProgress) {
        refreshAuthorization()
        guard authorized else { message = "امنح إذن مدة استخدام الجهاز أولًا."; return }
        guard selection.categoryTokens.isEmpty, !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty else {
            message = "اختر تطبيقات التواصل أو مواقعها بشكل منفرد، دون تحديد فئات كاملة."; return
        }
        var next = state
        next.selection = selection
        next.contract = NoorWardContract(chapter: plan.chapter, from: plan.from, to: plan.to, target: min(plan.daily, plan.to - plan.from + 1))
        guard next.contract?.valid == true else { message = "اختر خطة ورد صالحة أولًا."; return }
        next.enabled = true
        let day = NoorWardContract.dayKey(Date())
        next.completedDay = next.contract!.completed(in: progress.practiceDays[day] ?? []) ? day : nil
        do {
            // Register the background callback before making any restriction active.
            try DeviceActivityCenter().startMonitoring(NoorFocusState.activity, during: DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0), intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true))
            try next.save(); state = next; enabled = true; NoorFocusState.apply()
        } catch {
            DeviceActivityCenter().stopMonitoring([NoorFocusState.activity])
            ManagedSettingsStore(named: NoorFocusState.storeName).clearAllSettings()
            message = "تعذّر تفعيل حماية الورد. لم نُبقِ التطبيقات محجوبة. حاول مجددًا."
        }
    }
    func sync(progress: MemorizationProgress) {
        refreshAuthorization(); guard enabled else { return }
        let day = NoorWardContract.dayKey(Date())
        var next = state
        if next.contract?.completed(in: progress.practiceDays[day] ?? []) == true { next.completedDay = day }
        do { try next.save(); state = next; NoorFocusState.apply() }
        catch { message = "تعذّر تحديث إنجاز الورد. أوقف الحماية من هذه الصفحة ثم أعد تفعيلها." }
    }
    func disable() {
        DeviceActivityCenter().stopMonitoring([NoorFocusState.activity])
        ManagedSettingsStore(named: NoorFocusState.storeName).clearAllSettings()
        state.enabled = false; state.completedDay = nil
        do { try state.save(); enabled = false }
        catch { enabled = false; message = "أزلنا الحجب، لكن تعذّر حفظ الإعدادات. راجع إذن مدة استخدام الجهاز." }
    }
    #else
    private init() {}
    func sync(progress: MemorizationProgress) {}
    func disable() {}
    #endif
}

struct NoorFocusView: View {
    @EnvironmentObject private var memorization: MemorizationStore
    @StateObject private var focus = NoorFocusController.shared
    @Environment(\.scenePhase) private var phase
    #if NOOR_FOCUS_ENABLED
    @State private var choosing = false
    #endif
    var body: some View {
        Form {
            Section {
                Label("وردك قبل التواصل", systemImage: "lock.shield").font(.title2.bold())
                Text("اختر التطبيقات التي تشتتك. تظل محجوبة حتى تراجع آيات وردك وتحفظ نتيجة الجلسة، ويُرفع الحجب تلقائيًا عند الإكمال.")
                Text("التلميحات تساعدك على إكمال المراجعة؛ الإتقان يُقاس بصورة مستقلة. الآيات المتجاوزة لا تُحسب.").font(.caption).foregroundStyle(.secondary)
            }
            #if NOOR_FOCUS_ENABLED
            Section("حماية الورد") {
                if !focus.authorized {
                    Button("السماح بحماية وقت الورد") { Task { await focus.authorize() } }.disabled(focus.authorizing)
                } else {
                    Button("اختيار تطبيقات التواصل") { choosing = true }.disabled(focus.enabled)
                    Text("\(focus.selection.applicationTokens.count) تطبيقات · \(focus.selection.webDomainTokens.count) مواقع مختارة")
                    if focus.enabled {
                        Label("الحماية مفعلة", systemImage: "checkmark.shield")
                        Button("إيقاف الحماية", role: .destructive) { focus.disable() }
                    } else {
                        Button("تفعيل الورد قبل التواصل") { focus.enable(plan: memorization.plan, progress: memorization.progress) }
                    }
                }
                Text("نطاق الورد وهدفه ثابتان ما دامت الحماية مفعلة. تعديل خطة الحفظ لا يفتح التطبيقات؛ أوقف الحماية أولًا لتغيير هدفها.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section {
                Text("حماية التطبيقات غير متاحة في هذه النسخة. نجهّز النسخة التي تحتاج إذن مدة استخدام الجهاز قبل إتاحتها.")
            }
            #endif
            Section("أنت تتحكم") {
                Text("هذه حماية اختيارية، ويمكنك إيقافها هنا أو سحب الإذن من إعدادات الجهاز. لا تحجب الهاتف أو تطبيقات الطوارئ؛ اختر تطبيقات التواصل فقط.")
            }
        }.navigationTitle("حماية وقت الورد")
        #if NOOR_FOCUS_ENABLED
            .familyActivityPicker(isPresented: $choosing, selection: $focus.selection)
            .onAppear { focus.sync(progress: memorization.progress) }
            .onChange(of: phase) { _, new in if new == .active { focus.sync(progress: memorization.progress) } }
        #endif
            .alert("حماية الورد", isPresented: Binding(get: { focus.message != nil }, set: { if !$0 { focus.message = nil } })) {
                Button("تم") { focus.message = nil }
            } message: { Text(focus.message ?? "") }
    }
}
