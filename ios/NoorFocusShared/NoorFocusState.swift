import Foundation

struct NoorWardContract: Codable, Equatable {
    let chapter: Int
    let from: Int
    let to: Int
    let target: Int
    var valid: Bool { (1...114).contains(chapter) && from > 0 && to >= from && target > 0 && target <= min(50, to - from + 1) }
    func completed(in keys: Set<String>) -> Bool {
        guard valid else { return false }
        return keys.filter { key in
            let parts = key.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] == chapter && (from...to).contains(parts[1])
        }.count >= target
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

#if NOOR_FOCUS_ENABLED
import FamilyControls
import ManagedSettings
import DeviceActivity

struct NoorFocusState: Codable {
    static let group = "group.com.saud1596x.nooralruh"
    static let key = "noor.focus.state.v1"
    static let storeName = ManagedSettingsStore.Name("noor.dailyWard")
    static let activity = DeviceActivityName("noor.dailyWard")
    var enabled = false
    var selection = FamilyActivitySelection()
    var contract: NoorWardContract?
    var completedDay: String?

    static func load() -> NoorFocusState? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.enabled || value.contract?.valid == true else { return nil }
        return value
    }
    func save() throws {
        guard let defaults = UserDefaults(suiteName: Self.group) else { throw CocoaError(.fileWriteNoPermission) }
        defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
    }
    static func apply(at date: Date = Date()) {
        let store = ManagedSettingsStore(named: storeName)
        guard let state = load(), state.enabled, state.contract?.valid == true,
              state.completedDay != NoorWardContract.dayKey(date) else { store.clearAllSettings(); return }
        // Only explicitly chosen applications and domains; never shield entire categories.
        store.shield.applications = state.selection.applicationTokens.isEmpty ? nil : state.selection.applicationTokens
        store.shield.webDomains = state.selection.webDomainTokens.isEmpty ? nil : state.selection.webDomainTokens
    }
}
#endif
