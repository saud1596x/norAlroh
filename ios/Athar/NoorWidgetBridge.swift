import SwiftUI
import WidgetKit

@MainActor enum NoorWidgetBridge {
    private static let chapterStarts: [Int] = {
        struct Index: Decodable { let chapterStartPages: [Int] }
        return QuranResources.data("king-fahd-chapter-pages").flatMap { try? JSONDecoder().decode(Index.self, from: $0) }?.chapterStartPages ?? []
    }()
    static func journeySnapshot(_ plan: KhatmahPlan, now: Date) -> NoorKhatmahWidgetState {
        let visibleDays = Set((-1...2).compactMap { plan.calendar.date(byAdding: .day, value: $0, to: now) }
            .map { NoorSalawatCounts.dayKey($0, timeZone: plan.calendar.timeZone) })
        let completedByDay = plan.sessions.reduce(into: [String: Int]()) { totals, session in
            let key = NoorSalawatCounts.dayKey(session.date, timeZone: plan.calendar.timeZone)
            if visibleDays.contains(key) { totals[key, default: 0] += session.newlyCompleted }
        }
        return NoorKhatmahWidgetState(firstPage: plan.firstPage, nextPage: plan.nextPage, completed: plan.completed.count,
            paused: plan.paused, timeZone: plan.timeZone, days: plan.days.map { .init(date: $0.date, first: $0.first, last: $0.last) },
            planID: plan.id, dailyPages: plan.dailyPages, completedByDay: completedByDay,
            stoppedPage: plan.stoppedAt?.page, finished: plan.finished != nil)
    }
    static func publish(data: DeviceData, memorization: MemorizationStore, page: Int, khatmah: KhatmahStore, salawat: NoorSalawatStore) {
        guard let file = NoorWidgetSnapshot.file() else { return }
        let plan = memorization.plan
        let practiced = memorization.progress.practiceDays.mapValues { keys in
            keys.filter { key in
                let parts = key.split(separator: ":").compactMap { Int($0) }
                return parts.count == 2 && parts[0] == plan.chapter && (plan.from...plan.to).contains(parts[1])
            }.count
        }
        let dates = memorization.progress.verses.compactMap { key, value -> Date? in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, parts[0] == plan.chapter, (plan.from...plan.to).contains(parts[1]) else { return nil }
            return value.nextReview
        }
        let now = Date()
        let journey = khatmah.active.map { journeySnapshot($0, now: now) }
        let recentKeys = Set((-1...2).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }.map { NoorSalawatCounts.dayKey($0) })
        let startingChapters = Self.chapterStarts.enumerated().filter { $0.element == page }.map { $0.offset + 1 }
        let chapters = startingChapters.isEmpty ? Self.chapterStarts.lastIndex(where: { $0 <= page }).map { [$0 + 1] } ?? [] : startingChapters
        let chapterNames = chapters.compactMap { number in QuranResources.corpus?.first(where: { $0.number == number })?.name }
        let chapterName = chapterNames.isEmpty ? nil : chapterNames.joined(separator: " · ")
        let compact = NoorWidgetSnapshot(version: 2, updated: now, prayer: PrayerCalculator.inputs(data),
            page: min(604, max(1, page)), dailyTarget: memorization.dailyTarget, practiced: practiced.filter { recentKeys.contains($0.key) },
            reviewDates: dates, dua: "", duaTitle: "", khatmah: journey,
            salawat: NoorSalawatCounts(days: salawat.counts.days.filter { recentKeys.contains($0.key) }, goal: salawat.counts.goal), salawatTimeZone: TimeZone.current.identifier,
            hasReadingPosition: UserDefaults.standard.object(forKey: "noor.mushaf.lastPage") != nil,
            readingChapterName: chapterName,
            wardID: "memorization:\(plan.chapter):\(plan.from):\(plan.to)", duaCatalogVersion: NoorDuaCatalog.version,
            prayerTrusted: PrayerNotifications.hasTrustedLocation(data))
        let affected = compact.changedKinds(from: NoorWidgetSnapshot.load())
        guard !affected.isEmpty else { return }
        do {
            try compact.write(to: file)
            for kind in affected { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        } catch { /* Keep the last complete snapshot; never replace it with a partial write. */ }
    }
}

@MainActor final class NoorWidgetRouter: ObservableObject {
    static let shared = NoorWidgetRouter()
    private let defaults: UserDefaults
    private static let retiredHosts: Set<String> = ["compare", "compare-verses", "similarities", "reflection", "daily-verse", "friday", "friday-settings"]
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var savedPage: Int { max(1, min(604, defaults.integer(forKey: "noor.mushaf.lastPage"))) }
    struct Destination: Identifiable {
        let id = UUID(); let host: String; let page: Int?
        var duaID: String? = nil
        var wardID: String? = nil
    }
    @Published var destination: Destination?
    @discardableResult func openNotification(destination host: String) -> Bool {
        if Self.retiredHosts.contains(host) {
            destination = .init(host: "reading", page: savedPage); return true
        }
        guard ["prayers", "dhikr", "dua", "morning", "evening", "review", "salawat"].contains(host) else { return false }
        destination = .init(host: host, page: nil)
        return true
    }
    @discardableResult func open(_ url: URL) -> Bool {
        guard url.scheme == "nooralruh", let host = url.host,
              url.user == nil, url.password == nil else { return false }
        // Old shortcuts open the saved Quran page; never resurrect retired UI
        // or erase its independently stored personal notes.
        if Self.retiredHosts.contains(host) {
            destination = .init(host: "reading", page: savedPage); return true
        }
        guard let route = NoorWidgetLink.parse(url) else { return false }
        destination = .init(host: route.host, page: route.page, duaID: route.duaID, wardID: route.wardID); return true
    }
}

struct NoorWidgetGuide: View {
    var body: some View {
        List {
            Section("أضف نور الروح إلى شاشتك") {
                Text("اضغط مطولًا على مساحة فارغة في الشاشة الرئيسية، ثم اختر تعديل وإضافة أداة. ابحث عن نور الروح واختر الأداة والحجم.")
                Text("لشاشة القفل: اضغط مطولًا عليها، ثم تخصيص، ثم أضف أداة نور الروح أسفل الساعة.")
            }
            Section("دعاء من شاشتك") {
                NoorDuaWidgetComposition(dua: NoorDuaCatalog.home[0], family: .systemMedium)
                    .padding(16).frame(height: 170)
                    .background(NoorWidgetPalette.ivory, in: RoundedRectangle(cornerRadius: 20))
                    .environment(\.colorScheme, .light)
                    .accessibilityLabel("معاينة أداة الدعاء المتوسطة")
                Text("دعاء كامل للشاشة الرئيسية: صغير، متوسط، كبير. يتغير المحتوى وفق جدول ساعي محلي، ويحدد iOS وقت عرضه.")
                Text("ذكر قصير لشاشة القفل: مستطيل أو سطر. الضغط يفتح النص نفسه للقراءة والمشاركة.")
            }
            Section("اختر ما تحتاجه") {
                Label("الصلاة القادمة", systemImage: "sun.horizon")
                Label("مواقيت اليوم", systemImage: "clock")
                Label("دعاء قصير كامل", systemImage: "hands.sparkles")
                Label("آخر صفحة قرأتها", systemImage: "book")
                Label("ورد اليوم", systemImage: "checkmark.circle")
                Label("المراجعة المستحقة", systemImage: "arrow.clockwise")
                Label("تقدم الختمة ووردها القادم", systemImage: "book.closed")
                Label("عداد الصلاة على النبي", systemImage: "plus.circle")
                Label("ذكر قصير لشاشة القفل", systemImage: "sparkle")
            }
            Section("الأحجام والإجراءات") {
                Text("الصلاة القادمة ووردي: صغير ومتوسط، أو مستطيل وسطر ودائرة على شاشة القفل. افتح وردك لاستئنافه؛ لا تُسجل القراءة بمجرد الضغط على الأداة.")
                Text("أكمل القراءة: صغير ومتوسط، أو مستطيل وسطر على شاشة القفل. يفتح آخر صفحة محفوظة، أو يبدأ المصحف إذا لم تحفظ موضعًا بعد.")
                Text("اختر إضافة الأداة من واجهة النظام. المعاينة هنا لا تضيفها تلقائيًا.")
            }
            Section {
                Text("تتبع المواقيت آخر موقع صالح أو المدينة المختارة، وبمحرك الحساب نفسه المستخدم في التطبيق. يحدد النظام توقيت تحديث الأدوات؛ افتح التطبيق بعد السفر لتحديث الموقع.")
            }
        }.navigationTitle("أدوات الشاشة")
    }
}
