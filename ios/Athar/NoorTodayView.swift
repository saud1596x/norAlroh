import SwiftUI

struct NoorTodayView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var khatmah: KhatmahStore
    @EnvironmentObject private var account: NoorAccountStore
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
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("السَّلام عليكم").font(.subheadline).foregroundStyle(.secondary)
                    Text("قليلٌ دائم، وأثرٌ باقٍ")
                        .font(.custom(QuranTypography.postScriptName, size: 26, relativeTo: .title2))
                        .foregroundStyle(Theme.gold)
                }

                NavigationLink { MushafReader(chapter: 1, page: page) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("متابعة القراءة").font(.subheadline)
                        Text(resumeTitle)
                            .font(.custom(QuranTypography.postScriptName, size: 30, relativeTo: .largeTitle))
                        Text("آخر قراءة · الصفحة \(ArabicSearch.digits(page))").font(.subheadline)
                        HStack {
                            Text("افتح المصحف").font(.headline)
                            Spacer()
                            Image(systemName: "arrow.left")
                        }.padding(.top, 12)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22).foregroundStyle(.white)
                        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.resume")

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("رحلتك مع القرآن").font(.headline)
                        Spacer()
                        NavigationLink { MemorizationPlanView() } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.accessibilityLabel("هدفك").accessibilityIdentifier("home.goal")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { dailyWard; reviewProgress }
                        VStack(spacing: 12) { dailyWard; reviewProgress }
                    }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                    NavigationLink {
                        MushafReader(chapter: memorization.plan.chapter, ayah: memorization.plan.from, opensStudyScope: true)
                    } label: {
                        Text("ابدأ جلسة تسميع").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.buttonInk)
                            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.review")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("مساحة للسكينة").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { calmLinks }
                        VStack(spacing: 12) { calmLinks }
                    }.padding(16).background(Theme.soft, in: RoundedRectangle(cornerRadius: 20))
                }
                Text("خطوة صغيرة اليوم، حفظٌ أثبت غدًا.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)

                accountCard
                NavigationLink { NoorMyJourneyView() } label: {
                    HStack {
                        Label("رحلتي", systemImage: "chart.bar")
                        Spacer()
                        Image(systemName: "chevron.left").font(.caption)
                    }.padding(18).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.myJourney")
                NoorKhatmahProtectionCard()
                NavigationLink { NoorSalawatView() } label: {
                    Card {
                        Label("الصلاة على النبي ﷺ", systemImage: "plus.circle")
                        Text("عدادك اليومي وهدفك الشخصي").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.salawat")
                NavigationLink { LibraryView() } label: {
                    Card { Label("علاماتك", systemImage: "bookmark"); Text("\(store.data.bookmarks.count) علامات محفوظة").font(.caption) }
                }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.library")
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("مساحة لك. المزامنة السحابية اختيارية من صفحة حسابك.")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home.footer")
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }.background(Theme.background).navigationTitle("النور").navigationBarTitleDisplayMode(.inline)
    }
    private var dailyWard: some View {
        NavigationLink { KhatmahJourneyView() } label: {
            VStack(spacing: 6) {
                Text("ورد اليوم").font(.caption).foregroundStyle(.secondary)
                Text(khatmah.active?.due(on: Date()).map { "\(ArabicSearch.digits($0.count)) صفحات" } ?? "ابدأ خطتك")
                    .font(.custom(QuranTypography.postScriptName, size: 23, relativeTo: .title3))
                    .foregroundStyle(Theme.gold)
            }.frame(maxWidth: .infinity, minHeight: 64)
        }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.khatmah")
    }
    private var reviewProgress: some View {
        VStack(spacing: 6) {
            Text("مراجعة الحفظ").font(.caption).foregroundStyle(.secondary)
            Text("\(ArabicSearch.digits(reviewed)) من \(ArabicSearch.digits(memorization.dailyTarget)) آيات")
                .font(.custom(QuranTypography.postScriptName, size: 23, relativeTo: .title3))
                .foregroundStyle(Theme.gold)
        }.frame(maxWidth: .infinity, minHeight: 64)
    }
    @ViewBuilder private var calmLinks: some View {
        NavigationLink { AdhkarView() } label: {
            Text("أذكارك").frame(maxWidth: .infinity, minHeight: 44)
        }
        NavigationLink { PrayerView() } label: {
            Text("مواقيت الصلاة").frame(maxWidth: .infinity, minHeight: 44)
        }
    }
    private var accountCard: some View {
        NavigationLink { NoorAccountView() } label: {
            HStack(spacing: 12) {
                Image(systemName: account.signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.title2).foregroundStyle(Theme.gold).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.signedIn ? (account.name.isEmpty ? "حسابي" : account.name) : "حسابي · الدخول بحساب Apple")
                        .font(.headline)
                    Text(account.signedIn ? account.syncStatus : account.available
                         ? "اختياري؛ القراءة والأذكار متاحة دون حساب."
                         : "الدخول قيد التجهيز في هذه النسخة؛ القراءة متاحة دون حساب.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(16).foregroundStyle(.primary)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(NoorPressStyle()).accessibilityIdentifier("home.account")
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
