import XCTest
@testable import Athar

final class AdhkarCounterTests: XCTestCase {
    @MainActor func testCounterClampingSaudiDayRolloverAndFavoritePersistence() throws {
        let suite = "NoorDhikrTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let content = try XCTUnwrap(AdhkarContent.shared)
        let group = try XCTUnwrap(content.groups.first { $0.id == "hisn-27" })
        let entry = try XCTUnwrap(content.entries(in: group).first)
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-04T20:59:00Z"))
        let after = before.addingTimeInterval(120)
        let counters = DhikrCounterStore(defaults: defaults)
        counters.toggleFavorite(group.id)
        counters.update(999, entry: entry, group: group, city: .defaultCity, date: before)
        XCTAssertEqual(counters.count(entry: entry, group: group, city: .defaultCity, date: before), entry.target)
        XCTAssertEqual(counters.count(entry: entry, group: group, city: .defaultCity, date: after), 0)
        counters.refreshDay(date: after)
        XCTAssertTrue(counters.counts.isEmpty)
        let reopened = DhikrCounterStore(defaults: defaults)
        XCTAssertTrue(reopened.favorites.contains(group.id))
        reopened.update(-1, entry: entry, group: group, city: .defaultCity, date: after)
        XCTAssertEqual(reopened.count(entry: entry, group: group, city: .defaultCity, date: after), 0)
        reopened.erase()
        XCTAssertTrue(DhikrCounterStore(defaults: defaults).favorites.isEmpty)
    }
}
