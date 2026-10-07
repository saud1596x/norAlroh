import XCTest
import CoreLocation
@testable import Athar

final class AutomaticPrayerTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z")!
    func testPrayerClockAlwaysUsesTwentyFourHoursAndDestinationTimeZone() {
        let midnight = ISO8601DateFormatter().date(from: "2026-10-04T21:05:00Z")!
        let afternoon = ISO8601DateFormatter().date(from: "2026-10-04T12:07:00Z")!
        let riyadh = PrayerLocation(name: "الرياض", latitude: 24.7, longitude: 46.7, timeZone: "Asia/Riyadh")
        let dubai = PrayerLocation(name: "دبي", latitude: 25.2, longitude: 55.3, timeZone: "Asia/Dubai")
        XCTAssertEqual(PrayerCalculator.time(midnight, city: riyadh), "٠٠:٠٥")
        XCTAssertEqual(PrayerCalculator.time(afternoon, city: riyadh), "١٥:٠٧")
        XCTAssertEqual(PrayerCalculator.time(afternoon, city: dubai), "١٦:٠٧")
    }
    func testRegionalDefaultsReplaceLegacyChoicesInApplicationAndWidgetInputs() {
        var data = DeviceData(); data.method = "UmmAlQuraRamadan"; data.hanafi = true
        let inputs = PrayerCalculator.inputs(data)
        XCTAssertEqual(inputs.method, "UmmAlQura"); XCTAssertFalse(inputs.hanafi)
        for (country, method) in [("AE", "Dubai"), ("QA", "Qatar"), ("KW", "Kuwait"), ("EG", "Egyptian"),
                                  ("PK", "Karachi"), ("SG", "Singapore"), ("TR", "Turkey"), ("GB", "Moonsighting")] {
            XCTAssertEqual(AutomaticPrayerProfile.resolve(countryCode: country).method, method)
        }
        XCTAssertEqual(AutomaticPrayerProfile.resolve(countryCode: nil).method, "MuslimWorldLeague")
    }
    func testRamadanIntervalIsAutomaticAndOrdinaryMonthReturnsToNinetyMinutes() {
        let ramadan = ISO8601DateFormatter().date(from: "2026-03-01T10:00:00Z")!
        let ordinary = date
        for (day, interval) in [(ramadan, 120.0), (ordinary, 90.0)] {
            let rows = PrayerCalculator.rows(data: DeviceData(), date: day)
            XCTAssertEqual(rows.first { $0.id == "isha" }!.date.timeIntervalSince(rows.first { $0.id == "maghrib" }!.date), interval * 60, accuracy: 1)
        }
    }
    func testDeviceLocationAcceptanceRejectsStaleInvalidAndVeryInaccurateReadings() {
        func fix(age: Double = 0, accuracy: Double = 1000, latitude: Double = 24.7) -> CLLocation {
            .init(coordinate: .init(latitude: latitude, longitude: 46.7), altitude: 0,
                  horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: date.addingTimeInterval(-age))
        }
        XCTAssertTrue(PrayerLocationController.usable(fix(), now: date))
        XCTAssertFalse(PrayerLocationController.usable(fix(age: 301), now: date))
        XCTAssertFalse(PrayerLocationController.usable(fix(accuracy: -1), now: date))
        XCTAssertFalse(PrayerLocationController.usable(fix(accuracy: 15000), now: date))
        XCTAssertFalse(PrayerLocationController.usable(fix(latitude: 91), now: date))
    }
    @MainActor func testLastResolvedLocationAndOtherUserDataSurviveRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AtharStore(directory: folder)
        let dubai = City(id: "location.current", name: "دبي", latitude: 25.2048, longitude: 55.2708,
            timeZone: "Asia/Dubai", region: "دبي", countryCode: "AE", sourceID: nil)
        XCTAssertTrue(store.update { $0.city = dubai; $0.locationUpdatedAt = date; $0.bookmarks = ["1:1"] })
        let restored = AtharStore(directory: folder)
        XCTAssertEqual(restored.data.city, dubai)
        XCTAssertEqual(restored.data.locationUpdatedAt, date)
        XCTAssertEqual(restored.data.bookmarks, ["1:1"])
        XCTAssertEqual(PrayerCalculator.inputs(restored.data).method, "Dubai")
        XCTAssertEqual(PrayerCalculator.rows(data: restored.data, date: date).count, 6)
    }
    func testLegacyArchiveAndSoundPreferencesDecodeWithoutLosingSelections() throws {
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceData())) as? [String: Any])
        data.removeValue(forKey: "locationUpdatedAt")
        XCTAssertNil(try JSONDecoder().decode(DeviceData.self, from: JSONSerialization.data(withJSONObject: data)).locationUpdatedAt)
        let legacy = Data(#"{"prayers":{"fajr":false,"isha":true},"advanceMinutes":10,"soundEnabled":false}"#.utf8)
        let preferences = try JSONDecoder().decode(PrayerNotificationPreferences.self, from: legacy)
        XCTAssertEqual(preferences.prayers["fajr"], false)
        XCTAssertEqual(preferences.advanceMinutes, 10); XCTAssertFalse(preferences.soundEnabled)
        XCTAssertNil(preferences.soundStyle)
    }
    func testSalawatIsQuietBoundedAndIndependentOfPrayerPreferences() {
        XCTAssertTrue(SalawatNotificationPlan.slots(.init()).isEmpty)
        for hours in [2, 4, 6, 12] {
            let slots = SalawatNotificationPlan.slots(.init(enabled: true, intervalHours: hours))
            XCTAssertFalse(slots.isEmpty); XCTAssertLessThanOrEqual(slots.count, 7)
            XCTAssertEqual(Set(slots.map(\.id)).count, slots.count)
            XCTAssertTrue(slots.allSatisfy { (9...21).contains($0.hour) && !$0.body.isEmpty })
        }
        XCTAssertEqual(SalawatNotificationPlan.slots(.init(enabled: true, intervalHours: 12)).count, 1)
        XCTAssertTrue(SalawatNotificationPlan.slots(.init(enabled: true, intervalHours: 1)).isEmpty)
    }
    func testBundledAlertIsValidAndSoundOffIsRespected() {
        XCTAssertTrue(PrayerAlertSound.isValid())
        XCTAssertFalse(PrayerAlertSound.isValid(in: Bundle(for: Self.self)))
        var preferences = PrayerNotificationPreferences(); preferences.soundEnabled = false
        XCTAssertNil(PrayerAlertSound.sound(preferences: preferences))
        preferences.soundEnabled = true; preferences.soundStyle = "adhan"
        XCTAssertNotNil(PrayerAlertSound.sound(preferences: preferences))
    }
    func testCalendarUsesDestinationDateAcrossInternationalDayBoundary() {
        let boundary = date.addingTimeInterval(8 * 3600) // Oct 4 UTC, Oct 5 in Auckland.
        let location = PrayerLocation(name: "أوكلاند", latitude: -36.8485, longitude: 174.7633, timeZone: "Pacific/Auckland")
        let input = PrayerInputs(city: location, method: "MuslimWorldLeague", hanafi: false)
        let rows = PrayerCalculator.rows(data: input, date: boundary)
        XCTAssertEqual(rows.count, 6)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: location.timeZone)!
        XCTAssertEqual(calendar.component(.day, from: boundary), 5)
        XCTAssertTrue(rows.allSatisfy { calendar.isDate($0.date, inSameDayAs: boundary) })
        XCTAssertEqual(rows.map(\.date), rows.map(\.date).sorted())
    }
}
