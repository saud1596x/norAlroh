import SwiftUI
import WidgetKit

@MainActor enum NoorWidgetBridge {
    private static let dua: String = {
        struct Collection: Decodable { struct Entry: Decodable { let id: String; let text: String }; let entries: [Entry] }
        let entries = QuranResources.data("adhkar").flatMap { try? JSONDecoder().decode(Collection.self, from: $0) }
        return entries?.entries.first { $0.id == "hisn-9-14" }?.text ?? ""
    }()
    static func publish(data: DeviceData, memorization: MemorizationStore, page: Int) {
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
        let snapshot = NoorWidgetSnapshot(version: 1, updated: Date(), prayer: PrayerCalculator.inputs(data),
            page: min(604, max(1, page)), dailyTarget: memorization.dailyTarget, practiced: practiced,
            reviewDates: dates, dua: dua, duaTitle: "دعاء بعد الوضوء")
        do {
            try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadAllTimelines()
        } catch { /* Keep the last complete snapshot; never replace it with a partial write. */ }
    }
}

@MainActor final class NoorWidgetRouter: ObservableObject {
    static let shared = NoorWidgetRouter()
    private let defaults: UserDefaults
    private static let retiredHosts: Set<String> = ["compare", "compare-verses", "similarities", "reflection", "daily-verse"]
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var savedPage: Int { max(1, min(604, defaults.integer(forKey: "noor.mushaf.lastPage"))) }
    struct Destination: Identifiable { let id = UUID(); let host: String; let page: Int? }
    @Published var destination: Destination?
    @discardableResult func openNotification(destination host: String) -> Bool {
        if Self.retiredHosts.contains(host) {
            destination = .init(host: "reading", page: savedPage); return true
        }
        guard ["prayers", "dhikr"].contains(host) else { return false }
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
        guard ["reading", "prayers", "dhikr", "ward", "review"].contains(host) else { return false }
        let page = Int(url.lastPathComponent)
        if host == "reading", let page, !(1...604).contains(page) { return false }
        destination = .init(host: host, page: page); return true
    }
}

struct NoorWidgetGuide: View {
    var body: some View {
        List {
            Section("أضف نور الروح إلى شاشتك") {
                Text("اضغط مطولًا على مساحة فارغة في الشاشة الرئيسية، ثم اختر تعديل وإضافة أداة. ابحث عن نور الروح واختر الأداة والحجم.")
                Text("لشاشة القفل: اضغط مطولًا عليها، ثم تخصيص، ثم أضف أداة نور الروح أسفل الساعة.")
            }
            Section("اختر ما تحتاجه") {
                Label("الصلاة القادمة", systemImage: "sun.horizon")
                Label("مواقيت اليوم", systemImage: "clock")
                Label("دعاء قصير كامل", systemImage: "hands.sparkles")
                Label("آخر صفحة قرأتها", systemImage: "book")
                Label("ورد اليوم", systemImage: "checkmark.circle")
                Label("المراجعة المستحقة", systemImage: "arrow.clockwise")
            }
            Section {
                Text("تتبع المواقيت آخر موقع صالح أو المدينة المختارة، وبمحرك الحساب نفسه المستخدم في التطبيق. يحدد النظام توقيت تحديث الأدوات؛ افتح التطبيق بعد السفر لتحديث الموقع.")
            }
        }.navigationTitle("أدوات الشاشة")
    }
}
