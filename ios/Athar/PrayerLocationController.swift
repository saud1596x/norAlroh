import Foundation
import CoreLocation
import Combine

@MainActor final class PrayerLocationController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var automatic: Bool
    @Published private(set) var locating = false
    @Published private(set) var message: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    private let reverseGeocode: (@MainActor (CLLocation) async throws -> City)?
    private let geocodeTimeoutSeconds: Double
    private let managesLocationUpdates: Bool
    private weak var store: AtharStore?
    private var active = false
    private var generation = 0
    private var resolving = false
    private var lastResolved: CLLocation?
    private var timeout: Task<Void, Never>?
    private let key = "noor.prayer.automaticLocation"

    init(defaults: UserDefaults = .standard,
         geocodeTimeoutSeconds: Double = 20,
         managesLocationUpdates: Bool = true,
         reverseGeocode: (@MainActor (CLLocation) async throws -> City)? = nil) {
        self.defaults = defaults
        self.geocodeTimeoutSeconds = geocodeTimeoutSeconds; self.reverseGeocode = reverseGeocode
        self.managesLocationUpdates = managesLocationUpdates
        automatic = defaults.bool(forKey: key)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1_000
        manager.pausesLocationUpdatesAutomatically = true
    }
    func activate(store: AtharStore) {
        self.store = store; active = true
        guard automatic else { return }
        startIfAllowed()
    }
    func deactivate() {
        active = false; generation += 1; manager.stopUpdatingLocation()
        geocoder.cancelGeocode(); timeout?.cancel(); locating = false; resolving = false
    }
    func enable(store: AtharStore) {
        self.store = store; active = true
        automatic = true; defaults.set(true, forKey: key)
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { startIfAllowed() }
    }
    func useManualCity() {
        automatic = false; defaults.set(false, forKey: key)
        deactivate(); lastResolved = nil; message = nil
    }
    func erase() { useManualCity(); defaults.removeObject(forKey: key); lastResolved = nil }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard automatic, active else { return }
        startIfAllowed()
    }
    private func startIfAllowed() {
        // Unit lifecycle tests feed location callbacks explicitly without
        // requesting permission or starting physical location updates.
        guard managesLocationUpdates else { locating = true; message = nil; return }
        guard CLLocationManager.locationServicesEnabled() else {
            message = "خدمات الموقع متوقفة. نستخدم آخر موقع محفوظ أو المدينة المختارة."; return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locating = true; message = nil; manager.startUpdatingLocation()
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, self.locating else { return }
                self.locating = false
                self.message = "تعذر تحديث الموقع الآن. أبقينا آخر موقع صالح؛ حاول مجددًا."
            }
        case .denied, .restricted:
            locating = false
            message = "إذن الموقع غير متاح. نستخدم الموقع المحفوظ؛ يمكنك تغيير الإذن من إعدادات iPhone."
        default: break // Never prompt without the user's explicit button tap.
        }
    }
    nonisolated static func usable(_ location: CLLocation, now: Date = Date()) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate) && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 10_000
            && abs(location.timestamp.timeIntervalSince(now)) <= 300
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, automatic, !resolving, let location = locations.last, Self.usable(location) else { return }
        if let previous = lastResolved, location.distance(from: previous) < 1_000,
           Date().timeIntervalSince(previous.timestamp) < 1_800 {
            locating = false; timeout?.cancel(); return
        }
        resolving = true; let revision = generation
        Task { [weak self] in
            guard let self else { return }
            defer { if revision == self.generation { self.resolving = false; self.locating = false; self.timeout?.cancel() } }
            do {
                let city = try await NoorOperationDeadline.run(seconds: self.geocodeTimeoutSeconds) {
                    try await self.resolveCity(location)
                }
                guard revision == self.generation, self.active, self.automatic else { return }
                guard City.normalized(city) == city else { return }
                guard self.store?.update({ $0.city = city; $0.locationUpdatedAt = location.timestamp }) == true else {
                    self.message = "تعذر حفظ الموقع الجديد. لم نغيّر المواقيت السابقة."; return
                }
                self.lastResolved = location; self.message = nil
            } catch {
                guard revision == self.generation else { return }
                self.generation += 1; self.geocoder.cancelGeocode()
                self.resolving = false; self.locating = false; self.timeout?.cancel()
                self.message = "تعذر تحديد البلد أو المنطقة. نستخدم آخر موقع صالح؛ أعد المحاولة عند توفر الاتصال."
            }
        }
    }
    private func resolveCity(_ location: CLLocation) async throws -> City {
        if let reverseGeocode { return try await reverseGeocode(location) }
        let places = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ar"))
        guard let place = places.first, let code = place.isoCountryCode?.uppercased(), code.count == 2,
              let zone = place.timeZone else { throw CocoaError(.coderInvalidValue) }
        return City(id: "location.current", name: place.locality ?? place.administrativeArea ?? place.country ?? "الموقع الحالي",
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    timeZone: zone.identifier, region: place.administrativeArea, countryCode: code, sourceID: nil)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard active, automatic else { return }
        locating = false; timeout?.cancel()
        message = "تعذر تحديث الموقع. نستخدم آخر موقع محفوظ أو المدينة المختارة."
    }
}
