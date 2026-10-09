import Foundation

struct NoorWardContract: Codable, Equatable {
    let chapter: Int
    let from: Int
    let to: Int
    let target: Int
    var valid: Bool { (1...114).contains(chapter) && from > 0 && to >= from && target > 0 && target <= min(50, to - from + 1) }
    func completed(in keys: Set<String>) -> Bool {
        guard valid else { return false }
        let ayahs = keys.compactMap { key -> Int? in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 && parts[0] == chapter && (from...to).contains(parts[1]) else { return nil }
            return parts[1]
        }
        return Set(ayahs).count >= target
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

// A protected khatmah keeps its original schedule while enabled. Editing a plan
// cannot reduce the protected pages; only confirmed forward progress can do so.
struct NoorKhatmahWardContract: Codable, Equatable {
    struct Day: Codable, Equatable { let date: Date; let first: Int; let last: Int }
    let planID: UUID
    let firstPage: Int
    let timeZone: String
    let days: [Day]
    var nextPage: Int
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZone) ?? .current
        return value
    }
    var valid: Bool {
        guard (1...604).contains(firstPage), (firstPage...605).contains(nextPage),
              TimeZone(identifier: timeZone) != nil, !days.isEmpty,
              days.first?.first == firstPage, days.last?.last == 604 else { return false }
        return days.allSatisfy { $0.date.timeIntervalSince1970.isFinite && $0.first >= firstPage && $0.last <= 604 && $0.first <= $0.last }
            && zip(days, days.dropFirst()).allSatisfy { $0.date < $1.date && $0.last + 1 == $1.first }
    }
    func ward(at date: Date) -> Day? {
        guard valid, nextPage <= 604 else { return nil }
        let today = calendar.startOfDay(for: date)
        guard let day = days.last(where: { calendar.startOfDay(for: $0.date) <= today && $0.last >= nextPage }) else { return nil }
        return Day(date: day.date, first: nextPage, last: day.last)
    }
    var finished: Bool { valid && nextPage == 605 }
    mutating func confirm(planID: UUID, nextPage: Int) {
        guard valid, self.planID == planID, nextPage >= self.nextPage, nextPage <= 605 else { return }
        self.nextPage = nextPage
    }
}

enum NoorFocusPersistence {
    static let group = "group.com.saud1596x.nooralruh"
    static let key = "noor.focus.state.v1"
    @discardableResult static func erase(defaults: UserDefaults? = UserDefaults(suiteName: NoorFocusPersistence.group)) -> Bool {
        guard let defaults else { return false }
        defaults.removeObject(forKey: key)
        return defaults.object(forKey: key) == nil
    }
}

#if NOOR_FOCUS_ENABLED
import FamilyControls
import ManagedSettings
import DeviceActivity

struct NoorFocusState: Codable {
    static let group = NoorFocusPersistence.group
    static let key = NoorFocusPersistence.key
    static let storeName = ManagedSettingsStore.Name("noor.dailyWard")
    static let activity = DeviceActivityName("noor.dailyWard")
    var enabled = false
    var selection = FamilyActivitySelection()
    var contract: NoorWardContract?
    var khatmahContract: NoorKhatmahWardContract?
    var completedDay: String?

    static func load() -> NoorFocusState? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.enabled || value.khatmahContract?.valid == true || value.contract?.valid == true else { return nil }
        return value
    }
    func save() throws {
        guard let defaults = UserDefaults(suiteName: Self.group) else { throw CocoaError(.fileWriteNoPermission) }
        defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
    }
    static func apply(at date: Date = Date()) {
        let store = ManagedSettingsStore(named: storeName)
        guard let state = load(), state.enabled, state.khatmahContract?.ward(at: date) != nil else { store.clearAllSettings(); return }
        // Only explicitly chosen applications and domains; never shield entire categories.
        store.shield.applications = state.selection.applicationTokens.isEmpty ? nil : state.selection.applicationTokens
        store.shield.webDomains = state.selection.webDomainTokens.isEmpty ? nil : state.selection.webDomainTokens
    }
}
#endif
