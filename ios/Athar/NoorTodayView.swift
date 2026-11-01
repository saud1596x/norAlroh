import SwiftUI

struct NoorTodayView: View {
    @EnvironmentObject private var notifications: PrayerNotifications
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var khatmah: KhatmahStore
    @EnvironmentObject private var account: NoorAccountStore
    @StateObject private var focus = NoorFocusController.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    @State private var toolsExpanded = false
    @State private var readingWard: KhatmahReadingScope?
    @State private var today = Date()
    private var tokens: NoorChromeTokens { .init(scheme: scheme) }
    private var ward: KhatmahReadingScope? { khatmah.active?.readingScope(on: today) }
    private var page: Int { max(1, min(lastPage, 604)) }
    private var reduced: Bool { systemReduce || store.data.lowMotion }
    private var city: PrayerLocation { PrayerCalculator.location(store.data.city) }
    private var headerCity: PrayerLocation {
        PrayerLocation(name: city.name, latitude: city.latitude, longitude: city.longitude,
            timeZone: notifications.locationIsTrusted ? city.timeZone : TimeZone.current.identifier)
    }
    private var calendar: Calendar { PrayerDisplay.calendar(city: headerCity) }
    private var reviewed: Int { memorization.completedToday() }
    private var hasSavedPosition: Bool { UserDefaults.standard.object(forKey: "noor.mushaf.lastPage") != nil }
    private var finishedDailyWard: Bool {
        guard let plan = khatmah.active else { return false }
        return !plan.paused && plan.finished == nil && ward == nil
    }
    private var resumeTitle: String {
        guard let p = MushafDatabase.shared?.pages.first(where: { $0.page == page }),
              let n = p.words.first?.key.split(separator: ":").first.flatMap({ Int($0) }),
              let chapter = store.quran.first(where: { $0.number == n }) else { return "القرآن الكريم" }
        return chapter.name
    }
    private var readingTitle: String { ward != nil ? "وردك اليوم" : finishedDailyWard ? "موعدك مع القرآن" : resumeTitle }
    private var readingDetail: String {
        if let ward { return "\(ArabicSearch.digits(ward.last - ward.first + 1)) صفحة · \(ArabicSearch.digits(ward.first))–\(ArabicSearch.digits(ward.last))" }
        return hasSavedPosition ? "آخر قراءة · الصفحة \(ArabicSearch.digits(page))" : "ابدأ من أول المصحف، على مهل"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.section) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    NoorTodayComposition(greeting: greeting(context.date), dateText: PrayerDisplay.hijri(context.date, city: headerCity),
                        readingTitle: readingTitle, readingDetail: readingDetail,
                        readingStatus: finishedDailyWard ? "أتممت ورد اليوم" : nil, composition: .najdi) {
                            readingAction
                        } accountAction: {
                            accountAction
                        } prayerAction: {
                            prayerRow(at: context.date)
                        }
                }
                duaSection
                VStack(spacing: 0) {
                    NavigationLink { AdhkarView() } label: {
                        NoorTodayRouteLabel(title: "الأذكار", subtitle: "صباحك ومساءك وما بينهما", symbol: "sparkles")
                    }.accessibilityIdentifier("home.adhkar")
                    rule
                    NavigationLink { KhatmahJourneyView(currentPage: page) } label: {
                        NoorTodayRouteLabel(title: khatmah.active == nil ? "ابدأ ختمة" : "إعدادات الختمة",
                            subtitle: "خطتك ومقدار وردك اليومي", symbol: "book.closed")
                    }.accessibilityIdentifier("home.startKhatmah")
                    rule
                    NavigationLink { NoorFocusView() } label: {
                        NoorTodayRouteLabel(title: "حماية وقت الورد", subtitle: focus.enabled ? "الحماية مفعّلة" : "اختر التطبيقات التي تشتتك أثناء الورد", symbol: "lock.shield")
                    }.accessibilityIdentifier("khatmah.protection")
                }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion))
                toolsSection
                Label("بياناتك على جهازك · المزامنة اختيارية", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(tokens.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, NoorChromeTokens.Space.small)
                    .accessibilityIdentifier("home.footer")
            }.padding(NoorChromeTokens.Space.large)
        }
        .background(tokens.background)
        .navigationTitle("اليوم").navigationBarTitleDisplayMode(.inline)
        .onAppear { today = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { today = $0 }
        .fullScreenCover(item: $readingWard) { scope in
            let stop = khatmah.active?.stoppedAt
            let resume = scope.resumePage(stop)
            InteractiveMushafReader(chapter: stop?.page == resume ? stop?.chapter ?? 1 : 1,
                ayah: stop?.page == resume ? stop?.ayah ?? 1 : 1, initialPage: resume, readingScope: scope)
        }
    }
    @ViewBuilder private var readingAction: some View {
        if let ward {
            Button { readingWard = ward } label: {
                HStack { Text("أكمل ختمتك"); Spacer(); Image(systemName: NoorChromeTokens.Symbol.direction).accessibilityHidden(true) }
                    .frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.continueKhatmah")
        } else if !finishedDailyWard {
            NavigationLink { MushafReader(chapter: 1, page: page) } label: {
                HStack { Text(hasSavedPosition ? "متابعة القراءة" : "ابدأ القراءة"); Spacer(); Image(systemName: NoorChromeTokens.Symbol.direction).accessibilityHidden(true) }
                    .frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.resume")
        }
    }
    private var accountAction: some View {
        NavigationLink { NoorAccountView() } label: {
            Label("حسابي", systemImage: account.signedIn ? "person.crop.circle.fill" : NoorChromeTokens.Symbol.account)
                .font(.subheadline).foregroundStyle(tokens.primary).frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.account")
            .accessibilityLabel("حسابي")
            .accessibilityHint("اختياري؛ القراءة والأذكار متاحة دون حساب")
    }
    private func prayerRow(at date: Date) -> some View {
        NavigationLink { PrayerView() } label: {
            VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
                if notifications.locationIsTrusted, let next = PrayerCalculator.next(data: store.data, now: date) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NoorChromeTokens.Space.medium) {
                            prayerName(next)
                            Spacer(minLength: NoorChromeTokens.Space.medium)
                            countdown(from: date, to: next.date)
                        }
                        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
                            prayerName(next)
                            countdown(from: date, to: next.date)
                        }
                    }
                } else {
                    NoorTodayRouteLabel(title: "مواقيت الصلاة", subtitle: "اختر مدينتك لعرض الوقت الصحيح", symbol: "location")
                }
            }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .foregroundStyle(tokens.primary).contentShape(Rectangle())
        }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.prayers")
    }
    private func prayerName(_ next: PrayerRow) -> some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.tiny) {
            Label("\(next.name) · \(PrayerDisplay.isolatedClock(next.date, city: city))", systemImage: NoorChromeTokens.Symbol.prayer).font(.headline)
            Text(store.data.city.name).font(.subheadline).foregroundStyle(tokens.secondary)
        }
    }
    private func countdown(from start: Date, to end: Date) -> some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.tiny) {
            Text("متبقي").font(.footnote).foregroundStyle(tokens.secondary)
            Text(timerInterval: start...end, countsDown: true).font(.subheadline.monospacedDigit())
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
    private var duaSection: some View {
        let dua = NoorDuaTimeline.selection(at: today, family: .home, timeZone: .current)
        return VStack(alignment: .leading, spacing: NoorChromeTokens.Space.medium) {
            rule
            Text("دعاء").font(.subheadline).foregroundStyle(tokens.secondary)
            NavigationLink { NoorWidgetDuaReader(duaID: dua.id) } label: {
                Text(dua.text).font(.system(.title3, design: .serif)).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(tokens.primary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.dua")
            NavigationLink { NoorWidgetGuide() } label: {
                Label("اجعل الدعاء على شاشتك", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline).foregroundStyle(tokens.secondary).frame(minHeight: 44)
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.widgets")
        }
    }
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.medium) {
            Button {
                withAnimation(reduced ? nil : NoorChromeTokens.motion) { toolsExpanded.toggle() }
            } label: {
                HStack {
                    Text("خطتي وأدواتي").font(.headline)
                    Spacer()
                    Image(systemName: toolsExpanded ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }.foregroundStyle(tokens.primary).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.tools")
                .accessibilityValue(toolsExpanded ? "مفتوح" : "مغلق")
            if toolsExpanded {
                VStack(spacing: 0) {
                    NavigationLink { KhatmahJourneyView() } label: {
                        NoorTodayRouteLabel(title: "رحلة الختمة", subtitle: khatmah.active.map { "\($0.completed.count) من \(605 - $0.firstPage) صفحة" } ?? "خطتك ووردك اليومي", symbol: "book.closed")
                    }.accessibilityIdentifier("home.khatmah")
                    rule
                    NavigationLink { NoorSalawatView() } label: {
                        NoorTodayRouteLabel(title: "الصلاة على النبي ﷺ", subtitle: "عدادك اليومي وهدفك الشخصي", symbol: "plus.circle")
                    }.accessibilityIdentifier("home.salawat")
                    rule
                    NavigationLink { MemorizationPlanView() } label: {
                        NoorTodayRouteLabel(title: "هدفك", subtitle: "\(reviewed) من \(memorization.dailyTarget) آيات · مراجعتك المسجلة اليوم", symbol: "slider.horizontal.3")
                    }.accessibilityIdentifier("home.goal")
                    rule
                    NavigationLink { LibraryView() } label: {
                        NoorTodayRouteLabel(title: "علاماتك", subtitle: "\(store.data.bookmarks.count) علامات محفوظة", symbol: "bookmark")
                    }.accessibilityIdentifier("home.library")
                    rule
                    NavigationLink { NoorMyJourneyView() } label: {
                        NoorTodayRouteLabel(title: "رحلتي", subtitle: "قراءتك وختمتك", symbol: "chart.bar")
                    }.accessibilityIdentifier("home.myJourney")
                }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion))
            }
        }
    }
    private var rule: some View { Rectangle().fill(tokens.rule).frame(height: 1).accessibilityHidden(true) }
    private func greeting(_ date: Date) -> String {
        switch calendar.component(.hour, from: date) { case 5..<12: "صباحك نور وسكينة"; case 12..<18: "السلام عليكم، حيّاك الله"; default: "مساؤك ذكر وطمأنينة" }
    }
}

struct NoorRosette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<16 {
            let angle = Double(i) * .pi / 8 - .pi / 2
            let radius = min(rect.width, rect.height) * (i.isMultiple(of: 2) ? 0.5 : 0.29)
            let point = CGPoint(x: rect.midX + CGFloat(cos(angle)) * radius, y: rect.midY + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath(); return path
    }
}
