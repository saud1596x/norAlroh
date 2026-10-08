import SwiftUI

struct KhatmahJourneyView: View {
    @EnvironmentObject private var store: AtharStore
    @ObservedObject private var journey = KhatmahStore.shared
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    @Environment(\.dismiss) private var dismiss
    var currentPage: Int? = nil
    @State private var editing = false
    @State private var readerPage: Int?
    @State private var confirmation = false
    @State private var confirmedLast = 1
    @State private var recoveryPreview: KhatmahPlan?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("رحلة الختمة").font(.largeTitle.bold())
                Text("ورد واضح يناسب أيامك، وتقدم تحفظه بعد القراءة.").foregroundStyle(.secondary)
                if let plan = journey.active {
                    Card {
                        Label(plan.finished != nil ? "اكتملت رحلتك" : plan.paused ? "الرحلة متوقفة مؤقتًا" : "خطوتك القادمة", systemImage: "book.closed")
                        Text(verbatim: "\(plan.completed.count) من \(605 - plan.firstPage) صفحة").font(.title2.bold())
                            .accessibilityIdentifier("khatmah.completedPages")
                            .accessibilityValue(String(plan.completed.count))
                        NoorProgressBar(value: plan.progress, label: "تقدم الختمة")
                        if let finish = plan.expectedFinish { Text("الإتمام \(date(finish, plan: plan))").font(.subheadline).foregroundStyle(.secondary) }
                        if let due = plan.due(on: .now) {
                            Text("الصفحات \(due.first)–\(due.last)").font(.title3.bold())
                            Text(chapters(first: due.first, last: due.last)).foregroundStyle(.secondary)
                            Text("نحو \(due.count * 2)–\(due.count * 3) دقيقة؛ تقدير يتغير حسب سرعة قراءتك").font(.caption).foregroundStyle(.secondary)
                            PrimaryButton(title: "ابدأ ورد اليوم", icon: "book") { readerPage = due.first }.accessibilityIdentifier("khatmah.read")
                            Button("تأكيد الصفحات التي أتممت قراءتها") { confirmedLast = min(604, max(plan.nextPage, currentPage ?? due.last)); confirmation = true }
                                .frame(minHeight: 44).accessibilityIdentifier("khatmah.confirm")
                            Text("فتح المصحف لا يضيف تقدمًا؛ التأكيد وحده يحفظ القراءة.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if plan.missedDay(on: .now) {
                        Card {
                            Text("اختر ما يناسب يومك").font(.headline)
                            Text("بقي ورد من يوم سابق. خطتك لم تتغير تلقائيًا.").foregroundStyle(.secondary)
                            if plan.deadline != nil {
                                Button("وزّع المتبقي حتى موعد الإتمام") { recover(plan, extend: false) }.frame(minHeight: 44)
                            } else {
                                Button("حدد موعدًا جديدًا لتوزيع المتبقي") { editing = true }.frame(minHeight: 44)
                            }
                            Button("مدّد الموعد بنفس مقدار القراءة") { recover(plan, extend: true) }.frame(minHeight: 44)
                        }
                    }
                    if plan.finished == nil {
                        HStack {
                            Button("تعديل الخطة") { editing = true }.frame(minHeight: 44).accessibilityIdentifier("khatmah.edit")
                            Spacer()
                            Button(plan.paused ? "استئناف" : "إيقاف مؤقت") { _ = journey.setPaused(!plan.paused) }.frame(minHeight: 44).accessibilityIdentifier("khatmah.pause")
                        }
                    } else {
                        Button("ابدأ ختمة جديدة") { editing = true }.frame(minHeight: 44)
                    }
                    Text(journey.notificationStatus).font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("بداية صغيرة كل يوم", systemImage: "book.closed", description: Text("اختر بداية رحلتك وأيام القراءة، ثم راجع الورد قبل البدء."))
                    PrimaryButton(title: "إعداد رحلة الختمة", icon: "plus") { editing = true }.accessibilityIdentifier("khatmah.setup")
                }
                if let error = journey.error { Text(error).foregroundStyle(.red) }
            }.padding(20)
        }.background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .task { await journey.refreshReminders() }
            .sheet(isPresented: $editing) {
                NavigationStack { KhatmahSetupView(existing: journey.active?.finished == nil ? journey.active : nil, currentPage: currentPage ?? lastPage) }
            }
            .sheet(isPresented: $confirmation) {
                if let plan = journey.active, let due = plan.due(on: .now) {
                    NavigationStack {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("ما آخر صفحة أتممتها؟").font(.title2.bold())
                            Text("سنحفظ الصفحات من \(plan.nextPage) حتى اختيارك؛ لا تختَر إلا الصفحات التي قرأتها كاملة.").foregroundStyle(.secondary)
                            Stepper("الصفحة \(confirmedLast)", value: $confirmedLast, in: plan.nextPage...604).accessibilityIdentifier("khatmah.lastRead")
                            Button("تأكيد ورد اليوم حتى الصفحة \(due.last)") { if journey.confirm(first: plan.nextPage, last: due.last) { confirmation = false } }.frame(minHeight: 44)
                            PrimaryButton(title: "حفظ قراءتي", icon: "checkmark") { if journey.confirm(first: plan.nextPage, last: confirmedLast) { confirmation = false } }.accessibilityIdentifier("khatmah.saveReading")
                            Spacer()
                        }.padding(24).navigationTitle("تأكيد القراءة").toolbar { Button("إلغاء") { confirmation = false } }
                    }.presentationDetents([.medium, .large])
                }
            }
            .sheet(item: $recoveryPreview) { plan in
                NavigationStack {
                    KhatmahPlanPreview(plan: plan) {
                        if journey.adopt(plan) { recoveryPreview = nil }
                    }.toolbar { Button("إلغاء") { recoveryPreview = nil } }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { readerPage != nil }, set: { if !$0 { readerPage = nil } })) {
                InteractiveMushafReader(chapter: 1, ayah: 1, initialPage: readerPage)
            }
    }
    private func date(_ date: Date, plan: KhatmahPlan) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_SA"); f.calendar = plan.calendar; f.timeZone = plan.calendar.timeZone; f.dateStyle = .medium
        return f.string(from: date)
    }
    private func chapters(first: Int, last: Int) -> String {
        let numbers = Set(MushafDatabase.shared?.pages.filter { (first...last).contains($0.page) }.flatMap { $0.words.compactMap { Int($0.key.split(separator: ":")[0]) } } ?? [])
        return store.quran.filter { numbers.contains($0.number) }.map(\.name).joined(separator: " · ")
    }
    private func recover(_ plan: KhatmahPlan, extend: Bool) {
        do {
            let amount = plan.dailyPages ?? max(1, plan.days.first?.count ?? 1)
            recoveryPreview = try KhatmahCalculator.revised(plan, date: .now, weekdays: plan.weekdays, daily: extend ? amount : nil, deadline: extend ? nil : plan.deadline, reminder: plan.reminderMinutes)
        } catch { journey.error = error.localizedDescription }
    }
}

struct KhatmahSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var journey = KhatmahStore.shared
    let existing: KhatmahPlan?
    let currentPage: Int
    @State private var fromCurrent = false
    @State private var byDate = false
    @State private var daily = 20
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 29, to: .now)!
    @State private var weekdays = Set(1...7)
    @State private var reminder = false
    @State private var time = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
    @State private var preview: KhatmahPlan?
    @State private var error: String?
    private let names = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    var body: some View {
        Form {
            if existing == nil {
                Section("بداية الرحلة") {
                    Picker("البداية", selection: $fromCurrent) {
                        Text("بداية القرآن").tag(false)
                        Text("موضعي الحالي · \(max(1, min(604, currentPage)))").tag(true)
                    }.accessibilityIdentifier("khatmah.start")
                }
            } else { Section { Text("سيبقى كل تقدمك وسجل القراءة محفوظين.") } }
            Section("هدفك") {
                Picker("نوع الهدف", selection: $byDate) { Text("صفحات يومية").tag(false); Text("تاريخ الإتمام").tag(true) }.pickerStyle(.segmented)
                if byDate { DatePicker("موعد الإتمام", selection: $deadline, in: Date.now..., displayedComponents: .date).accessibilityIdentifier("khatmah.deadline") }
                else { Stepper("\(daily) صفحة في اليوم", value: $daily, in: 1...604).accessibilityIdentifier("khatmah.daily") }
            }
            Section("أيام القراءة") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(names[day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                }
            }
            Section("تذكير اختياري") {
                Toggle("ذكّرني بالورد", isOn: $reminder)
                if reminder {
                    DatePicker("الوقت", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .environment(\.timeZone, existing?.calendar.timeZone ?? .current)
                }
                Text("يمكنك القراءة دون حساب أو تذكيرات. يُجدّد التذكير عند فتح التطبيق، ضمن حدود iOS.").font(.caption)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section { Button("معاينة الخطة") { prepare() }.accessibilityIdentifier("khatmah.preview") }
        }.navigationTitle(existing == nil ? "إعداد الختمة" : "تعديل الختمة")
            .toolbar { Button("إلغاء") { dismiss() } }
            .onAppear {
                guard let existing else { return }
                weekdays = existing.weekdays; byDate = existing.deadline != nil; deadline = max(.now, existing.deadline ?? .now); daily = existing.dailyPages ?? 20
                reminder = existing.reminderMinutes != nil
                if let minutes = existing.reminderMinutes { time = existing.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now }
            }
            .sheet(item: $preview) { plan in
                NavigationStack {
                    KhatmahPlanPreview(plan: plan) {
                        if journey.adopt(plan) {
                            if plan.reminderMinutes != nil { Task { await journey.enableReminderPermission() } }
                            preview = nil; dismiss()
                        }
                    }.toolbar { Button("عودة للتعديل") { preview = nil } }
                }
            }
    }
    private func prepare() {
        do {
            let c = existing?.calendar ?? Calendar.current
            let minutes = reminder ? c.component(.hour, from: time) * 60 + c.component(.minute, from: time) : nil
            if let existing {
                preview = try KhatmahCalculator.revised(existing, date: .now, weekdays: weekdays, daily: byDate ? nil : daily, deadline: byDate ? deadline : nil, reminder: minutes)
            } else {
                preview = try KhatmahCalculator.make(first: fromCurrent ? max(1, min(604, currentPage)) : 1, date: .now, weekdays: weekdays, daily: byDate ? nil : daily, deadline: byDate ? deadline : nil, reminder: minutes, calendar: c)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
struct KhatmahPlanPreview: View {
    @EnvironmentObject private var store: AtharStore
    let plan: KhatmahPlan
    let accept: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("خطتك قبل البدء").font(.largeTitle.bold())
                Text("البداية: الصفحة \(plan.nextPage)")
                if let finish = plan.expectedFinish {
                    Text("الإتمام المتوقع: \(formatDate(finish))")
                }
                Text("\(plan.days.count) يوم قراءة · \(605 - plan.nextPage) صفحة متبقية")
                ForEach(Array(plan.days.prefix(7))) { day in
                    Card {
                        Text(formatDate(day.date)).font(.headline)
                        Text("الصفحات \(day.first)–\(day.last) · \(day.count) صفحة")
                        Text("نحو \(day.count * 2)–\(day.count * 3) دقيقة").font(.caption).foregroundStyle(.secondary)
                        Text(chapters(day)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if plan.days.count > 7 { Text("تستمر الخطة بالتوزيع نفسه؛ آخر يوم ينتهي عند الصفحة 604.").font(.caption).foregroundStyle(.secondary) }
                PrimaryButton(title: "اعتماد الخطة", icon: "checkmark") { accept() }.accessibilityIdentifier("khatmah.adopt")
            }.padding(20)
        }.background(Theme.background).navigationTitle("معاينة الختمة")
    }
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA"); formatter.calendar = plan.calendar; formatter.timeZone = plan.calendar.timeZone; formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    private func chapters(_ day: KhatmahDay) -> String {
        let values = Set(MushafDatabase.shared?.pages.filter { (day.first...day.last).contains($0.page) }.flatMap { $0.words.compactMap { Int($0.key.split(separator: ":")[0]) } } ?? [])
        return store.quran.filter { values.contains($0.number) }.map(\.name).joined(separator: " · ")
    }
}
