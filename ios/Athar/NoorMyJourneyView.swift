import SwiftUI

struct NoorMyJourneyView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @ObservedObject private var journey = KhatmahStore.shared
    @State private var month = Date.now
    @State private var selectedDay: Date?
    @State private var selectedEvent: NoorReadingEvent?
    @State private var readerPage: Int?
    @State private var pendingReaderPage: Int?
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 1; return c }
    private var index: NoorJourneyIndex { NoorJourneyIndex(archive: journey.archive, calendar: calendar) }
    private var shownDays: [Date] { selectedDay.map { [$0] } ?? index.readingDays.sorted(by: >) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("رحلتي").font(.largeTitle.bold())
                Text("خطواتك محفوظة، وعلى مهل.").foregroundStyle(.secondary)
                planCard
                calendarCard
                HStack {
                    Text(selectedDay == nil ? "جلسات القراءة" : dateText(selectedDay!, format: "EEEE، d MMMM")).font(.title2.bold())
                    Spacer()
                    if selectedDay != nil { Button("كل الأيام") { selectedDay = nil }.frame(minHeight: 44).accessibilityIdentifier("journey.allDays") }
                }
                if shownDays.isEmpty || shownDays.allSatisfy({ index.events(on: $0).isEmpty }) {
                    ContentUnavailableView("خطوتك الأولى تنتظرك", systemImage: "book.closed", description: Text(selectedDay == nil ? "بعد تأكيد القراءة في رحلة الختمة، تظهر جلستك هنا." : "لا توجد قراءة مؤكدة في هذا اليوم."))
                } else {
                    ForEach(shownDays, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            if selectedDay == nil { Text(dateText(day, format: "EEEE، d MMMM yyyy")).font(.headline).foregroundStyle(.secondary) }
                            ForEach(index.events(on: day)) { event in eventRow(event) }
                        }
                    }
                }
                Card {
                    Text("أثر خطواتك").font(.headline)
                    Text(verbatim: "\(index.readingDays.count) أيام قراءة · \(index.newlyCompletedPages) صفحات جديدة في رحلات الختمة")
                        .font(.subheadline).accessibilityIdentifier("journey.summary")
                    NavigationLink { MemorizationHistoryView() } label: {
                        Label("الحفظ والمراجعة · \(memorization.history.count) جلسات محفوظة", systemImage: "arrow.clockwise")
                            .frame(minHeight: 44)
                    }
                }
                completedPlans
                if let error = journey.error { Text(error).foregroundStyle(.red) }
            }.padding(20)
        }.background(Theme.background).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedEvent, onDismiss: {
                if let pending = pendingReaderPage { pendingReaderPage = nil; readerPage = pending }
            }) { event in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(chapters(event.session.first...event.session.last)).font(.title2.bold())
                        Text(verbatim: "الصفحات \(event.session.first)–\(event.session.last)")
                        Text(dateText(event.session.date, format: "EEEE، d MMMM yyyy · HH:mm")).foregroundStyle(.secondary)
                        Text(verbatim: "\(event.session.newlyCompleted) صفحة أضيفت إلى تقدم الختمة")
                        if event.session.newlyCompleted < event.session.last - event.session.first + 1 {
                            Text("تتضمن هذه الجلسة إعادة قراءة؛ لم نحتسب الصفحات السابقة مرة أخرى.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        PrimaryButton(title: "افتح بداية المقطع", icon: "book") { pendingReaderPage = event.session.first; selectedEvent = nil }
                        Spacer()
                    }.padding(24).noorScreenChrome().navigationTitle("تفاصيل القراءة")
                        .toolbar { Button("إغلاق") { selectedEvent = nil } }
                }.presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: Binding(get: { readerPage != nil }, set: { if !$0 { readerPage = nil } })) {
                InteractiveMushafReader(chapter: 1, ayah: 1, initialPage: readerPage)
            }
    }
    private var planCard: some View {
        Card {
            if let plan = journey.active {
                Text(plan.finished != nil ? (plan.firstPage == 1 ? "اكتملت الختمة" : "اكتملت رحلتك") : plan.paused ? "رحلتك متوقفة مؤقتًا" : "رحلة الختمة").font(.headline)
                Text(verbatim: "\(plan.completed.count) من \(605 - plan.firstPage) صفحة").font(.title2.bold())
                NoorProgressBar(value: plan.progress, label: "تقدم الختمة")
                if let due = plan.due(on: .now) {
                    Text(verbatim: "وردك القادم · \(due.first)–\(due.last)")
                    Text(chapters(due.first...due.last)).font(.subheadline).foregroundStyle(.secondary)
                    PrimaryButton(title: "ابدأ ورد اليوم", icon: "book") { readerPage = due.first }.accessibilityIdentifier("journey.read")
                }
                if let finish = plan.expectedFinish { Text("الإتمام \(dateText(finish, format: "d MMMM yyyy", zone: plan.calendar.timeZone))").font(.subheadline).foregroundStyle(.secondary) }
                NavigationLink("إدارة رحلة الختمة") { KhatmahJourneyView() }.frame(minHeight: 44)
            } else {
                Text("ابدأ رحلة تناسب يومك").font(.title2.bold())
                Text("اختر وردًا صغيرًا أو موعدًا للإتمام. تُحفظ جلساتك بعد تأكيد القراءة.").foregroundStyle(.secondary)
                NavigationLink("إعداد رحلة الختمة") { KhatmahJourneyView() }.frame(minHeight: 44)
            }
        }
    }
    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("الشهر السابق").accessibilityIdentifier("journey.previousMonth")
                Spacer()
                Text(dateText(month, format: "MMMM yyyy")).font(.headline).accessibilityIdentifier("journey.month")
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("الشهر التالي").accessibilityIdentifier("journey.nextMonth")
            }
            ScrollView(.horizontal, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: 7), spacing: 6) {
                ForEach(["أحد", "إثن", "ثلا", "أرب", "خمي", "جمع", "سبت"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
                ForEach(0..<index.leadingDays(in: month), id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
                ForEach(index.days(in: month), id: \.self) { day in
                    Button { selectedDay = day } label: {
                        VStack(spacing: 3) {
                            Text(verbatim: String(calendar.component(.day, from: day))).font(.subheadline.monospacedDigit())
                            Circle().fill(index.readingDays.contains(day) ? Theme.gold : Color.clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .background(selectedDay == day ? Theme.gold.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(dateText(day, format: "EEEE، d MMMM yyyy") + (index.readingDays.contains(day) ? "، توجد قراءة مؤكدة" : "، دون قراءة مؤكدة"))
                        .accessibilityIdentifier("journey.day.\(calendar.component(.day, from: day))")
                        .accessibilityAddTraits(selectedDay == day ? .isSelected : [])
                }
            }.frame(minWidth: 308)
            }
        }.padding(.horizontal, 8).padding(.vertical, 16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
            .noorEntrance()
    }
    private func eventRow(_ event: NoorReadingEvent) -> some View {
        Button { selectedEvent = event } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    Circle().fill(Theme.gold).frame(width: 9, height: 9).padding(.top, 6)
                    Rectangle().fill(Theme.gold.opacity(0.2)).frame(width: 1).frame(minHeight: 44)
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapters(event.session.first...event.session.last)).font(.headline)
                    Text(verbatim: "الصفحات \(event.session.first)–\(event.session.last)").font(.subheadline)
                    Text(dateText(event.session.date, format: "HH:mm")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if event.session.newlyCompleted == 0 { Text("إعادة قراءة").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("journey.session.\(event.session.id)")
    }
    @ViewBuilder private var completedPlans: some View {
        let completed = journey.archive.plans.filter { $0.finished != nil }.sorted { $0.finished! > $1.finished! }
        if !completed.isEmpty {
            Text("ختماتك المكتملة").font(.title2.bold())
            ForEach(completed) { plan in
                Card {
                    Label(plan.firstPage == 1 ? "ختمة مكتملة" : "رحلة مكتملة من الصفحة \(plan.firstPage)", systemImage: "checkmark.seal")
                    Text("من \(dateText(plan.started, format: "d MMMM yyyy", zone: plan.calendar.timeZone)) إلى \(dateText(plan.finished!, format: "d MMMM yyyy", zone: plan.calendar.timeZone))").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func changeMonth(_ delta: Int) {
        guard let first = calendar.dateInterval(of: .month, for: month)?.start,
              let next = calendar.date(byAdding: .month, value: delta, to: first) else { return }
        month = next; selectedDay = nil
    }
    private func chapters(_ range: ClosedRange<Int>) -> String {
        let values = Set(MushafDatabase.shared?.pages.filter { range.contains($0.page) }.flatMap { $0.words.compactMap { Int($0.key.split(separator: ":")[0]) } } ?? [])
        let names = store.quran.filter { values.contains($0.number) }.map(\.name).joined(separator: " · ")
        return names.isEmpty ? "قراءة القرآن" : names
    }
    private func dateText(_ date: Date, format: String, zone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = zone; f.locale = Locale(identifier: "ar_SA@numbers=latn"); f.dateFormat = format
        return f.string(from: date)
    }
}
