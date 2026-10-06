import Foundation

struct NoorWidgetSnapshot: Codable {
    let version: Int
    let updated: Date
    let prayer: PrayerInputs
    let page: Int
    let dailyTarget: Int
    let practiced: [String: Int]
    let reviewDates: [Date]
    let dua: String
    let duaTitle: String
    static let group = "group.com.saud1596x.nooralruh"
    static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("noor-widget-v1.json")
    }
    static func load() -> Self? {
        guard let file = file(), let bytes = try? Data(contentsOf: file), bytes.count < 2_000_000,
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.version == 1,
              (1...604).contains(value.page), (0...50).contains(value.dailyTarget),
              TimeZone(identifier: value.prayer.city.timeZone) != nil,
              (-90...90).contains(value.prayer.city.latitude), (-180...180).contains(value.prayer.city.longitude) else { return nil }
        return value
    }
    func completed(at date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return practiced["\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"] ?? 0
    }
    func due(at date: Date) -> Int { reviewDates.filter { $0 <= Calendar.current.startOfDay(for: date) }.count }
}
