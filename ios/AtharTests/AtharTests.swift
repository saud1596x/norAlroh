import XCTest
@testable import Athar

final class AtharTests: XCTestCase {
    @MainActor
    func testBundledQuranIsComplete() {
        let store = AtharStore()
        XCTAssertEqual(store.quran.count, 114)
        XCTAssertEqual(store.quran.reduce(0) { $0 + $1.ayahs.count }, 6236)
        XCTAssertEqual(store.quran.map(\.number), Array(1...114))
        for surah in store.quran {
            XCTAssertEqual(surah.ayahs.map(\.number), Array(1...surah.ayahs.count))
            XCTAssertTrue(surah.ayahs.allSatisfy { !$0.text.isEmpty })
        }
    }

    func testPrayerOrderAndNextPrayerAcrossMidnight() {
        var data = DeviceData()
        data.city = City.all[0]
        let date = ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z")!
        let rows = PrayerCalculator.rows(data: data, date: date)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.map(\.date), rows.map(\.date).sorted())
        let late = ISO8601DateFormatter().date(from: "2026-10-04T20:30:00Z")!
        let next = PrayerCalculator.next(data: data, now: late)
        XCTAssertEqual(next?.id, "fajr")
        XCTAssertTrue((next?.date ?? .distantPast) > late)
    }

    func testOnlySaudiCitiesAreSelectableAndLegacyCitiesMigrate() {
        XCTAssertEqual(City.all.count, 93)
        XCTAssertEqual(Set(City.all.compactMap(\.region)).count, 13)
        XCTAssertTrue(City.all.allSatisfy { $0.countryCode == "SA" && $0.timeZone == "Asia/Riyadh" })
        let unsupported = City(id: "london", name: "لندن", latitude: 51.5, longitude: -0.12,
            timeZone: "Europe/London", region: nil, countryCode: nil, sourceID: nil)
        XCTAssertEqual(City.normalized(unsupported), City.defaultCity)
    }
}
