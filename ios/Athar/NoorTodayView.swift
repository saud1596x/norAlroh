import SwiftUI

struct NoorTodayView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var khatmah: KhatmahStore
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("noor.mushaf.lastPage") private var lastPage = 1
    private var page: Int { max(1, min(lastPage, 604)) }
    private var reduced: Bool { systemReduce || store.data.lowMotion }
    private var city: PrayerLocation { PrayerCalculator.location(store.data.city) }
    private var calendar: Calendar { PrayerDisplay.calendar(city: city) }
    private var reviewed: Int {
        memorization.completedToday()
    }
    private var resumeTitle: String {
        guard let p = MushafDatabase.shared?.pages.first(where: { $0.page == page }),
              let n = p.words.first?.key.split(separator: ":").first.flatMap({ Int($0) }),
              let chapter = store.quran.first(where: { $0.number == n }) else { return "القرآن الكريم" }
        return chapter.name
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("نور الروح").font(.largeTitle.bold()).foregroundStyle(Theme.gold)
                                Text(greeting(context.date)).font(.headline)
                                Text(PrayerDisplay.gregorian(context.date, city: city)).font(.caption).foregroundStyle(.secondary)
                                Text(PrayerDisplay.hijri(context.date, city: city)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            NoorAmbientOrnament().frame(width: 64, height: 64)
                        }.noorEntrance()
                        if let next = PrayerCalculator.next(data: store.data, now: context.date) {
                            NavigationLink { PrayerView() } label: {
                                HStack(spacing: 12) {
                                    NoorAnimatedSymbol(name: "sun.horizon").font(.title2).foregroundStyle(Theme.gold)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(next.name) · \(PrayerDisplay.isolatedClock(next.date, city: city))").font(.headline)
                                        Text(store.data.city.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("متبقي").font(.caption).foregroundStyle(.secondary)
                                        Text(timerInterval: context.date...next.date, countsDown: true).font(.subheadline.monospacedDigit())
                                            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                                            .environment(\.layoutDirection, .leftToRight)
                                    }.frame(maxWidth: 95)
                                }.padding(18).foregroundStyle(.primary).background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(NoorPressStyle()).noorEntrance(delay: 0.04)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("موعدك مع القرآن", systemImage: "book.closed").font(.subheadline)
                        Spacer()
                        Text("حفص").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.buttonInk.opacity(0.12), in: Capsule())
                    }
                    Text(resumeTitle).font(.largeTitle.bold())
                    HStack {
                        Text("آخر قراءة · الصفحة \(ArabicSearch.digits(page))").font(.subheadline)
                        Spacer()
                        Image(systemName: "bookmark.fill").font(.caption)
                    }
                    NavigationLink { MushafReader(chapter: 1, page: page) } label: {
                        HStack { Text("متابعة القراءة"); Spacer(); Image(systemName: "arrow.left") }
                            .font(.headline).padding(16).foregroundStyle(Theme.gold)
                            .background(Theme.buttonInk, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.resume")
                }.padding(24).foregroundStyle(Theme.buttonInk)
                    .background {
                        ZStack {
                            LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.92)], startPoint: .topTrailing, endPoint: .bottomLeading)
                            NoorMotionSurface(ink: Theme.buttonInk)
                        }.clipShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .overlay { RoundedRectangle(cornerRadius: 28).stroke(Theme.buttonInk.opacity(0.15), lineWidth: 1).allowsHitTesting(false) }
                    .noorEntrance(delay: 0.08)
                NavigationLink { KhatmahJourneyView() } label: {
                    Card {
                        Label("رحلة الختمة", systemImage: "book.closed")
                        if let plan = khatmah.active {
                            Text("\(plan.completed.count) من \(605 - plan.firstPage) صفحة").font(.headline)
                            Text(plan.finished != nil ? "اكتملت رحلتك" : plan.paused ? "الرحلة متوقفة مؤقتًا" : "تابع من الصفحة \(plan.nextPage)").font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("خطتك ووردك اليومي").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.khatmah")
                NavigationLink { NoorSalawatView() } label: {
                    Card { Label("الصلاة على النبي ﷺ", systemImage: "plus.circle"); Text("عدادك اليومي وهدفك الشخصي").font(.subheadline).foregroundStyle(.secondary) }
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.salawat")
                HStack {
                    Text("خطواتك اليوم").font(.title3.bold())
                    Spacer()
                    NavigationLink { MemorizationPlanView() } label: { Label("هدفك", systemImage: "slider.horizontal.3").font(.caption).frame(minHeight: 44) }
                }
                Card {
                    HStack(spacing: 16) {
                        ZStack {
                            NoorProgressDial(value: Double(reviewed) / Double(max(1, memorization.dailyTarget)))
                            Text("\(reviewed)").font(.title2.monospacedDigit()).contentTransition(.numericText())
                        }.frame(width: 62, height: 62).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(reviewed) من \(memorization.dailyTarget) آيات").font(.headline)
                            Text("مراجعتك الفعلية، خطوة بعد خطوة").font(.caption).foregroundStyle(.secondary)
                            NavigationLink("ابدأ المراجعة") { MemorizationView() }.font(.subheadline).frame(minHeight: 44)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Text("مساحاتك").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 14) {
                    NavigationLink { AdhkarView() } label: { tile("أذكارك", "حصن المسلم كاملًا", "sparkles") }
                    NavigationLink { LibraryView() } label: { tile("علاماتك", "\(store.data.bookmarks.count) علامات محفوظة", "bookmark") }.accessibilityIdentifier("home.library")
                    NavigationLink { NoorMyJourneyView() } label: { tile("رحلتي", "قراءتك وحفظك ومراجعتك", "chart.bar") }.accessibilityIdentifier("home.myJourney")
                }.buttonStyle(NoorPressStyle())
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("مساحة لك. بياناتك محفوظة على جهازك.")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8).accessibilityIdentifier("home.footer")
            }.padding(20)
        }.background(Theme.background).navigationTitle("اليوم").navigationBarTitleDisplayMode(.inline)
            .animation(reduced ? nil : .spring(duration: 0.4, bounce: 0.1), value: reviewed)
    }
    private func tile(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NoorAnimatedSymbol(name: symbol).font(.title2).foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44).background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(18)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(Theme.gold.opacity(0.12), lineWidth: 1) }
            .noorEntrance(delay: 0.16)
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
