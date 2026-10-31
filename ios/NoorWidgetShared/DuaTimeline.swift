import Foundation

enum NoorDuaFamily: CaseIterable {
    case home, small, lockRectangular, lockInline
    var content: [NoorDua] {
        switch self {
        case .home: return NoorDuaCatalog.home
        case .small: return NoorDuaCatalog.home.filter { NoorDuaCatalog.smallIDs.contains($0.id) }
        case .lockRectangular: return NoorDuaCatalog.lock
        case .lockInline: return Array(NoorDuaCatalog.lock.prefix(3))
        }
    }
}

struct NoorDuaTimelineEntry: Equatable, Codable {
    let date: Date
    let dua: NoorDua
}

enum NoorDuaTimeline {
    static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    static func selection(at date: Date, family: NoorDuaFamily, timeZone: TimeZone) -> NoorDua {
        let calendar = calendar(timeZone: timeZone)
        let start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let slot: Int64
        switch family {
        case .home, .small:
            // Number the actual Calendar hour intervals since local midnight.
            // Both fall-back occurrences have separate ordinals, a skipped hour
            // has none, and a 30-minute transition still has its own interval.
            // A 29-slot daily stride avoids repeating across 23/24/25-hour day
            // boundaries for either home pool (53 or 31), with no daily repeats.
            let day = calendar.startOfDay(for: start)
            var cursor = day, ordinal: Int64 = 0
            while cursor < start, ordinal < 30 {
                guard let next = calendar.dateInterval(of: .hour, for: cursor)?.end, next > cursor else { break }
                cursor = next; ordinal += 1
            }
            slot = Int64(calendar.ordinality(of: .day, in: .era, for: day) ?? 0) * 29 + ordinal
        case .lockRectangular, .lockInline:
            // Prime short pools (7/3) and absolute quarter-hour slots avoid an
            // adjacent repeat through both one-hour and half-hour DST shifts.
            slot = Int64(floor(start.timeIntervalSince1970 / 900))
        }
        // Versions change provenance/text only; never reorder a released pool.
        let pool = family.content
        let index = Int((slot % Int64(pool.count) + Int64(pool.count)) % Int64(pool.count))
        return pool[index]
    }
    static func entries(now: Date, family: NoorDuaFamily, timeZone: TimeZone) -> [NoorDuaTimelineEntry] {
        let calendar = calendar(timeZone: timeZone)
        let horizon = calendar.date(byAdding: .hour, value: 48, to: now) ?? now.addingTimeInterval(172_800)
        var result = [NoorDuaTimelineEntry(date: now, dua: selection(at: now, family: family, timeZone: timeZone))]
        var cursor = now
        // Includes the first boundary at/after 48 elapsed hours so atEnd does
        // not request another timeline before the promised coverage window.
        while cursor < horizon, result.count < 100 {
            guard let next = calendar.dateInterval(of: .hour, for: cursor)?.end, next > cursor else { break }
            result.append(.init(date: next, dua: selection(at: next, family: family, timeZone: timeZone)))
            cursor = next
        }
        return result
    }
}

enum NoorWidgetLink {
    struct Destination: Equatable {
        let host: String
        var page: Int? = nil
        var duaID: String? = nil
        var wardID: String? = nil
    }
    static func dua(_ value: NoorDua) -> URL {
        var parts = URLComponents()
        parts.scheme = "nooralruh"; parts.host = "dua"
        parts.queryItems = [.init(name: "duaID", value: value.id)]
        return parts.url!
    }
    static func reading(page: Int) -> URL? {
        guard (1...604).contains(page) else { return nil }
        return URL(string: "nooralruh://reading/\(page)")
    }
    static func ward(id: String, page: Int? = nil) -> URL? {
        guard validWardID(id), page.map({ (1...604).contains($0) }) ?? true else { return nil }
        if khatmahPlanID(from: id) != nil, page == nil { return nil }
        var parts = URLComponents(); parts.scheme = "nooralruh"; parts.host = "ward"
        parts.queryItems = [.init(name: "wardID", value: id)]
        if let page { parts.queryItems?.append(.init(name: "pageID", value: String(page))) }
        return parts.url
    }
    static func validWardID(_ id: String) -> Bool {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        if khatmahPlanID(from: id) != nil { return true }
        guard parts.count == 4, parts[0] == "memorization", let chapter = Int(parts[1]),
              let first = Int(parts[2]), let last = Int(parts[3]), (1...114).contains(chapter),
              (1...286).contains(first), (first...286).contains(last) else { return false }
        return "memorization:\(chapter):\(first):\(last)" == id
    }
    static func khatmahPlanID(from id: String) -> UUID? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "khatmah" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
    static func parse(_ url: URL) -> Destination? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "nooralruh",
              let host = parts.host, parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return nil }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { return nil }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        switch host {
        case "dua":
            guard parts.path.isEmpty, query.count == 1, let id = query["duaID"], NoorDuaCatalog.find(id) != nil else { return nil }
            return .init(host: host, duaID: id)
        case "reading":
            let segments = parts.path.split(separator: "/", omittingEmptySubsequences: false)
            guard query.isEmpty, segments.count == 2, segments[0].isEmpty,
                  let page = Int(segments[1]), (1...604).contains(page), String(page) == segments[1] else { return nil }
            return .init(host: host, page: page)
        case "ward":
            if parts.path.isEmpty, query.isEmpty { return .init(host: host) } // Existing installed v1 widgets.
            guard parts.path.isEmpty, Set(query.keys).isSubset(of: ["wardID", "pageID"]),
                  let id = query["wardID"], validWardID(id) else { return nil }
            let page = query["pageID"].flatMap(Int.init)
            if let raw = query["pageID"], page == nil || !(1...604).contains(page!) || String(page!) != raw { return nil }
            if khatmahPlanID(from: id) != nil, page == nil { return nil }
            return .init(host: host, page: page, wardID: id)
        default:
            guard ["prayers", "dhikr", "review", "khatmah", "salawat", "morning", "evening"].contains(host),
                  parts.path.isEmpty, query.isEmpty else { return nil }
            return .init(host: host)
        }
    }
}
