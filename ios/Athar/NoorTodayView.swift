import SwiftUI

struct NoorTodayView: View {
    @EnvironmentObject private var notifications: PrayerNotifications
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var khatmah: KhatmahStore
    @EnvironmentObject private var account: NoorAccountStore
    @StateObject private var focus = NoorFocusController.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.scenePhase) private var phase
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    @State private var toolsExpanded = false
    @State private var readingWard: KhatmahReadingScope?
    @State private var today = Date()
    /// Visibility of this screen; the sanctuary scene animates only while true.
    @State private var onScreen = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36

    /// Readable measure on iPad and in wide windows; iPhone uses the full width.
    private let contentWidth: CGFloat = 680
    private let gutter: CGFloat = 20

    // MARK: Existing home data logic (unchanged)

    private var ward: KhatmahReadingScope? { khatmah.active?.readingScope(on: today) }
    private var page: Int { max(1, min(lastPage, 604)) }
    private var reduced: Bool { systemReduce || store.data.lowMotion }
    private var city: PrayerLocation { PrayerCalculator.location(store.data.city) }
    private var headerCity: PrayerLocation {
        PrayerLocation(name: city.name, latitude: city.latitude, longitude: city.longitude,
            timeZone: notifications.locationIsTrusted ? city.timeZone : TimeZone.current.identifier)
    }
    private var calendar: Calendar { PrayerDisplay.calendar(city: headerCity) }
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

    // MARK: Copy derived from that logic

    private var readingTitle: String {
        if ward != nil { return "وردك اليوم" }
        if finishedDailyWard { return "أتممت ورد اليوم" }
        return resumeTitle
    }
    private var readingDetail: String {
        if let ward {
            let range = ward.count == 1
                ? "الصفحة \(ArabicSearch.digits(ward.first))"
                : "من الصفحة \(ArabicSearch.digits(ward.first)) إلى \(ArabicSearch.digits(ward.last))"
            return "\(pageCount(ward.count)) · \(range)"
        }
        if finishedDailyWard, let next = khatmah.active?.nextPage, next <= 604 {
            return "وردك القادم يبدأ من الصفحة \(ArabicSearch.digits(next))."
        }
        return hasSavedPosition ? "توقفت عند الصفحة \(ArabicSearch.digits(page))" : "ابدأ من أول المصحف، على مهل."
    }
    private var sceneActive: Bool { onScreen && phase == .active && readingWard == nil }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                masthead
                    .padding(.horizontal, gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                    .frame(maxWidth: contentWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 30) {
                    readingCard
                    // Restrict the prayer clock to its own surface; the reader card
                    // and its saved-page lookup are not part of this 30-second tick.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        prayerRow(at: context.date)
                    }
                    duaSection
                    journeySection
                    toolsSection
                    Label("بياناتك على جهازك، والمزامنة اختيارية", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, NoorChromeTokens.Space.small)
                        .accessibilityIdentifier("home.footer")
                }
                .padding(.horizontal, gutter)
                .padding(.bottom, 32)
                .frame(maxWidth: contentWidth)
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .top) { sanctuary }
        }
        .background(Theme.background)
        .navigationTitle("اليوم").navigationBarTitleDisplayMode(.inline)
        .onAppear { today = Date(); onScreen = true }
        .onDisappear { onScreen = false }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { today = $0 }
        .fullScreenCover(item: $readingWard) { scope in
            let stop = khatmah.active?.stoppedAt
            let resume = scope.resumePage(stop)
            InteractiveMushafReader(chapter: stop?.page == resume ? stop?.chapter ?? 1 : 1,
                ayah: stop?.page == resume ? stop?.ayah ?? 1 : 1, initialPage: resume, readingScope: scope)
        }
    }

    /// Decorative scene behind the masthead only. It bleeds above the content
    /// (visible on pull-down), fades into the page, and pauses whenever this
    /// screen is covered, pushed away or backgrounded.
    private var sanctuary: some View {
        NoorSanctuaryScene(active: sceneActive)
            .frame(height: 560)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.62),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .padding(.top, -160)
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: NoorChromeTokens.Space.medium) {
                    brand
                    Spacer(minLength: NoorChromeTokens.Space.small)
                    accountAction
                }
                VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
                    brand
                    accountAction
                }
            }
            Text(greeting(today))
                .font(NoorChromeTokens.TypeStyle.reading).bold()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoorChromeTokens.Space.medium)
            ViewThatFits(in: .horizontal) {
                Text("\(PrayerDisplay.gregorian(today, city: headerCity)) · \(PrayerDisplay.hijri(today, city: headerCity))")
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PrayerDisplay.gregorian(today, city: headerCity))
                    Text(PrayerDisplay.hijri(today, city: headerCity))
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var brand: some View {
        Text("نور الروح")
            .font(.headline)
            .foregroundStyle(Theme.gold)
            .accessibilityAddTraits(.isHeader)
    }

    /// Optional account: a quiet chip, never a full-width panel.
    private var accountAction: some View {
        NavigationLink { NoorAccountView() } label: {
            Label(account.signedIn ? (account.name.isEmpty ? "حسابي" : account.name) : "الدخول",
                  systemImage: account.signedIn ? "person.crop.circle.fill" : NoorChromeTokens.Symbol.account)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.panel.opacity(0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
        }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.account")
            .accessibilityLabel("حسابي")
            .accessibilityValue(account.signedIn ? account.syncStatus : "لم تسجّل الدخول")
            .accessibilityHint("اختياري؛ القراءة والأذكار متاحة دون حساب")
    }

    // MARK: Reading (primary)

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("موعدك مع القرآن", systemImage: NoorChromeTokens.Symbol.reading).font(.subheadline.weight(.semibold))
                    Spacer()
                    hafsTag
                }
                VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
                    Label("موعدك مع القرآن", systemImage: NoorChromeTokens.Symbol.reading).font(.subheadline.weight(.semibold))
                    hafsTag
                }
            }
            Text(readingTitle)
                .font(NoorChromeTokens.TypeStyle.reading).bold()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoorChromeTokens.Space.tiny)
            Text(readingDetail)
                .font(.body)
                .opacity(0.88)
                .fixedSize(horizontal: false, vertical: true)
            if let plan = khatmah.active, plan.finished == nil {
                khatmahProgress(plan)
            }
            // When today's ward is complete the title says so, and there is no action,
            // matching the existing behavior.
            if !finishedDailyWard {
                readingAction.padding(.top, NoorChromeTokens.Space.small)
            }
        }
        .padding(24)
        .foregroundStyle(Theme.buttonInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.gold.gradient)
                .overlay(alignment: .bottomTrailing) {
                    // Static engraving; decoration only.
                    ZStack {
                        NoorArch().stroke(Theme.buttonInk.opacity(0.14), lineWidth: 1)
                            .frame(width: 120, height: 160)
                        NoorArch().stroke(Theme.buttonInk.opacity(0.09), lineWidth: 1)
                            .frame(width: 84, height: 124)
                            .offset(y: 18)
                    }
                    .offset(x: 18, y: 40)
                    .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.originalReadingCard")
    }

    private var hafsTag: some View {
        Text("رواية حفص").font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.buttonInk.opacity(0.14), in: Capsule())
    }

    private func khatmahProgress(_ plan: KhatmahPlan) -> some View {
        let total = 605 - plan.firstPage
        let value = plan.progress.isFinite ? min(1, max(0, plan.progress)) : 0
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: value).tint(Theme.buttonInk)
            Text("قرأت \(ArabicSearch.digits(plan.completed.count)) من \(ArabicSearch.digits(total)) صفحة في ختمتك")
                .font(.footnote).opacity(0.88)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, NoorChromeTokens.Space.tiny)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("تقدّم الختمة")
        .accessibilityValue("\(plan.completed.count) من \(total) صفحة")
    }

    @ViewBuilder private var readingAction: some View {
        if let ward {
            Button { readingWard = ward } label: { actionLabel("أكمل ختمتك") }
                .buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.continueKhatmah")
        } else if !finishedDailyWard {
            NavigationLink { MushafReader(chapter: 1, page: page) } label: {
                actionLabel(hasSavedPosition ? "متابعة القراءة" : "ابدأ القراءة")
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.resume")
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer(minLength: NoorChromeTokens.Space.small)
            Image(systemName: NoorChromeTokens.Symbol.direction).font(.headline).accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(Theme.gold)
        .background(Theme.buttonInk, in: Capsule())
        .contentShape(Capsule())
    }

    // MARK: Prayer strip

    private func prayerRow(at date: Date) -> some View {
        NavigationLink { PrayerView() } label: {
            Group {
                if notifications.locationIsTrusted, let next = PrayerCalculator.next(data: store.data, now: date) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            prayerIcon
                            prayerName(next)
                            Spacer(minLength: NoorChromeTokens.Space.medium)
                            countdown(from: date, to: next.date)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) { prayerIcon; prayerName(next) }
                            countdown(from: date, to: next.date)
                        }
                    }
                } else {
                    homeRoute("مواقيت الصلاة", subtitle: "اختر مدينتك لنعرض المواقيت الصحيحة", symbol: "location")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.gold.opacity(0.16), lineWidth: 1))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.prayers")
    }

    private var prayerIcon: some View {
        Image(systemName: NoorChromeTokens.Symbol.prayer)
            .font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
            .frame(width: iconSize, height: iconSize)
            .background(Theme.gold.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }

    private func prayerName(_ next: PrayerRow) -> some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.tiny) {
            Text("\(next.name) · \(PrayerDisplay.isolatedClock(next.date, city: city))").font(.headline)
            Text(store.data.city.name).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func countdown(from start: Date, to end: Date) -> some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.tiny) {
            Text("متبقي").font(.footnote).foregroundStyle(.secondary)
            Text(timerInterval: start...end, countsDown: true).font(.subheadline.monospacedDigit())
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    // MARK: Dua

    private var duaSection: some View {
        let dua = NoorDuaTimeline.selection(at: today, family: .home, timeZone: .current)
        return VStack(alignment: .leading, spacing: NoorChromeTokens.Space.medium) {
            sectionTitle("دعاء")
            NavigationLink { NoorWidgetDuaReader(duaID: dua.id) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Capsule().fill(Theme.gold.opacity(0.55)).frame(width: 3)
                        .accessibilityHidden(true)
                    Text(dua.text).font(.system(.title3, design: .serif)).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.dua")
                .accessibilityHint("يفتح الدعاء كاملًا")
            NavigationLink { NoorWidgetGuide() } label: {
                Label("أضف الدعاء إلى شاشتك الرئيسية", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.widgets")
        }
    }

    // MARK: Journey

    private var journeySection: some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.medium) {
            sectionTitle("رحلتك")
            VStack(spacing: 0) {
                NavigationLink { AdhkarView() } label: {
                    homeRoute("الأذكار", subtitle: "الصباح والمساء وأذكار اليوم", symbol: "sparkles")
                }.accessibilityIdentifier("home.adhkar")
                insetRule
                NavigationLink { KhatmahJourneyView(currentPage: page) } label: {
                    homeRoute(khatmah.active == nil ? "ابدأ ختمة" : "إعدادات الختمة",
                        subtitle: khatmah.active == nil ? "اختر مقدار وردك وأيام قراءتك" : "عدّل مقدار الورد وأيام القراءة",
                        symbol: "book.closed")
                }.accessibilityIdentifier("home.startKhatmah")
                insetRule
                NavigationLink { NoorFocusView() } label: {
                    homeRoute("حماية وقت الورد",
                        subtitle: focus.enabled ? "الحماية مفعّلة" : "احجب التطبيقات المشتّتة حتى إكمال وردك",
                        symbol: "lock.shield")
                }.accessibilityIdentifier("khatmah.protection")
            }
            .buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion))
            .padding(.horizontal, 16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: NoorChromeTokens.Space.small) {
            Button {
                withAnimation(reduced ? nil : NoorChromeTokens.motion) { toolsExpanded.toggle() }
            } label: {
                HStack {
                    Text("خطتي وأدواتي").font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: toolsExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.gold)
                        .accessibilityHidden(true)
                }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion)).accessibilityIdentifier("home.tools")
                .accessibilityValue(toolsExpanded ? "مفتوح" : "مغلق")
            if toolsExpanded {
                VStack(spacing: 0) {
                    NavigationLink { KhatmahJourneyView() } label: {
                        homeRoute("رحلة الختمة",
                            subtitle: khatmah.active.map { "قرأت \(ArabicSearch.digits($0.completed.count)) من \(ArabicSearch.digits(605 - $0.firstPage)) صفحة" } ?? "خطتك ووردك اليومي",
                            symbol: "book.closed")
                    }.accessibilityIdentifier("home.khatmah")
                    insetRule
                    NavigationLink { NoorSalawatView() } label: {
                        homeRoute("الصلاة على النبي ﷺ", subtitle: "عدّاد اليوم وهدفك الشخصي", symbol: "plus.circle")
                    }.accessibilityIdentifier("home.salawat")
                    insetRule
                    NavigationLink { LibraryView() } label: {
                        homeRoute("علاماتك", subtitle: bookmarkCount(store.data.bookmarks.count), symbol: "bookmark")
                    }.accessibilityIdentifier("home.library")
                    insetRule
                    NavigationLink { NoorMyJourneyView() } label: {
                        homeRoute("رحلتي", subtitle: "ما قرأته وما أتممته", symbol: "chart.bar")
                    }.accessibilityIdentifier("home.myJourney")
                }
                .buttonStyle(NoorChromePressStyle(lowMotion: store.data.lowMotion))
                .padding(.horizontal, 16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.opacity)
            }
        }
    }

    // MARK: Shared pieces

    private func homeRoute(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.gold)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.gold.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.left").font(.footnote.weight(.semibold)).foregroundStyle(Theme.gold.opacity(0.7))
                .accessibilityHidden(true)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.vertical, 6).contentShape(Rectangle())
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private var rule: some View { Rectangle().fill(Theme.gold.opacity(0.18)).frame(height: 1).accessibilityHidden(true) }
    private var insetRule: some View { rule.padding(.leading, iconSize + 14) }

    private func pageCount(_ n: Int) -> String {
        switch n {
        case 1: "صفحة واحدة"
        case 2: "صفحتان"
        case 3...10: "\(ArabicSearch.digits(n)) صفحات"
        default: "\(ArabicSearch.digits(n)) صفحة"
        }
    }

    private func bookmarkCount(_ n: Int) -> String {
        switch n {
        case 0: "لا علامات محفوظة بعد"
        case 1: "علامة واحدة محفوظة"
        case 2: "علامتان محفوظتان"
        case 3...10: "\(ArabicSearch.digits(n)) علامات محفوظة"
        default: "\(ArabicSearch.digits(n)) علامة محفوظة"
        }
    }

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
