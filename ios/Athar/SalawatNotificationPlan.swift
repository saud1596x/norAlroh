import Foundation

struct SalawatPreferences: Codable, Equatable {
    var enabled = false
    var intervalHours = 4
    var valid: Bool { [2, 4, 6, 12].contains(intervalHours) }
}
struct SalawatSlot: Identifiable {
    let hour: Int
    let body: String
    var id: String { SalawatNotificationPlan.prefix + String(hour) }
}
enum SalawatNotificationPlan {
    static let prefix = "noor.salawat."
    static let messages = [
        "اللهم صل وسلم على نبينا محمد ﷺ",
        "اللهم صل على محمد وعلى آل محمد",
        "صلّ وسلم على نبينا محمد ﷺ",
        "اللهم صل وسلم وبارك على نبينا محمد ﷺ"
    ]
    // Seven maximum, daytime only. Daily repeating requests survive closure;
    // unlike prayer times these do not need a different astronomical time each day.
    static func slots(_ preferences: SalawatPreferences) -> [SalawatSlot] {
        guard preferences.enabled, preferences.valid else { return [] }
        return stride(from: 9, through: preferences.intervalHours == 12 ? 9 : 21, by: preferences.intervalHours).enumerated().map {
            .init(hour: $0.element, body: messages[$0.offset % messages.count])
        }
    }
}
