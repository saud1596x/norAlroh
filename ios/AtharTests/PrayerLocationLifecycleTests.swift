import XCTest
import CoreLocation
@testable import Athar

final class PrayerLocationLifecycleTests: XCTestCase {
    @MainActor func testHungGeocoderTimesOutAllowsRetryAndCannotApplyItsLateCity() async throws {
        let name = "NoorLocationTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        defaults.set(true, forKey: "noor.prayer.automaticLocation")
        let store = AtharStore(directory: folder)
        XCTAssertTrue(store.update { $0.bookmarks = ["1:1"] })
        let oldCity = store.data.city
        var late: CheckedContinuation<City, Never>?
        var calls = 0
        let retryCity = City(id: "location.current", name: "دبي", latitude: 25.2048, longitude: 55.2708,
            timeZone: "Asia/Dubai", region: "دبي", countryCode: "AE", sourceID: nil)
        let controller = PrayerLocationController(defaults: defaults, geocodeTimeoutSeconds: 0.05, managesLocationUpdates: false) { _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { late = $0 } }
            return retryCity
        }
        controller.activate(store: store)
        defer { controller.deactivate() }
        let manager = CLLocationManager()
        controller.locationManager(manager, didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        let deadline = Date().addingTimeInterval(3)
        while controller.message == nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(controller.message)
        XCTAssertFalse(controller.locating)
        XCTAssertEqual(store.data.city, oldCity)
        controller.locationManager(manager, didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        while calls < 2 && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        while store.data.city != retryCity && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(store.data.city, retryCity)
        try XCTUnwrap(late).resume(returning: oldCity)
        await Task.yield()
        XCTAssertEqual(store.data.city, retryCity)
        XCTAssertEqual(store.data.bookmarks, ["1:1"])
    }
}
