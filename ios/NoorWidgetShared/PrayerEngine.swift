import Foundation
import Adhan

struct PrayerLocation: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
}
struct PrayerInputs: Codable {
    let city: PrayerLocation
    let method: String
    let hanafi: Bool
}

struct PrayerRow: Identifiable {
    let id: String
    let name: String
    let date: Date
    let sunrise: Bool
}

enum PrayerCalculator {
    static func isSameSaudiDay(_ left: Date, _ right: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar.isDate(left, inSameDayAs: right)
    }
    static func isSameDay(_ left: Date, _ right: Date, city: PrayerLocation) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: city.timeZone) ?? .current
        return calendar.isDate(left, inSameDayAs: right)
    }
    static func rows(data: PrayerInputs, date: Date = Date()) -> [PrayerRow] {
        guard data.city.latitude.isFinite, data.city.longitude.isFinite,
              (-90...90).contains(data.city.latitude), (-180...180).contains(data.city.longitude),
              let timeZone = TimeZone(identifier: data.city.timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var params: CalculationParameters
        switch data.method {
        case "Dubai": params = CalculationMethod.dubai.params
        case "Qatar": params = CalculationMethod.qatar.params
        case "Kuwait": params = CalculationMethod.kuwait.params
        case "Egyptian": params = CalculationMethod.egyptian.params
        case "Karachi": params = CalculationMethod.karachi.params
        case "Singapore": params = CalculationMethod.singapore.params
        case "Turkey": params = CalculationMethod.turkey.params
        case "Moonsighting": params = CalculationMethod.moonsightingCommittee.params
        case "MuslimWorldLeague": params = CalculationMethod.muslimWorldLeague.params
        default:
            params = CalculationMethod.ummAlQura.params
            var hijri = Calendar(identifier: .islamicUmmAlQura)
            hijri.timeZone = calendar.timeZone
            params.ishaInterval = hijri.component(.month, from: date) == 9 ? 120 : 90
        }
        params.madhab = data.hanafi ? .hanafi : .shafi
        params.highLatitudeRule = abs(data.city.latitude) > 48 ? .seventhOfTheNight : .middleOfTheNight
        let coordinates = Coordinates(latitude: data.city.latitude, longitude: data.city.longitude)
        guard let times = PrayerTimes(coordinates: coordinates, date: day, calculationParameters: params) else { return [] }
        return [
            .init(id: "fajr", name: "الفجر", date: times.fajr, sunrise: false),
            .init(id: "sunrise", name: "الشروق", date: times.sunrise, sunrise: true),
            .init(id: "dhuhr", name: "الظهر", date: times.dhuhr, sunrise: false),
            .init(id: "asr", name: "العصر", date: times.asr, sunrise: false),
            .init(id: "maghrib", name: "المغرب", date: times.maghrib, sunrise: false),
            .init(id: "isha", name: "العشاء", date: times.isha, sunrise: false)
        ]
    }
    static func time(_ date: Date, city: PrayerLocation) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.timeZone = TimeZone(identifier: city.timeZone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static func next(data: PrayerInputs, now: Date) -> PrayerRow? {
        if let next = rows(data: data, date: now).first(where: { !$0.sunrise && $0.date > now }) { return next }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: data.city.timeZone) ?? .current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return rows(data: data, date: tomorrow).first(where: { !$0.sunrise && $0.date > now })
    }
}


// Versioned regional defaults, shared by the application and WidgetKit.
// Unknown regions use a general astronomical preset, not a claim of official times.
enum AutomaticPrayerProfile {
    static let version = 1
    static func resolve(countryCode: String?) -> (method: String, lateAsr: Bool) {
        switch countryCode?.uppercased() {
        case "SA": return ("UmmAlQura", false)
        case "AE": return ("Dubai", false)
        case "QA": return ("Qatar", false)
        case "KW": return ("Kuwait", false)
        case "EG": return ("Egyptian", false)
        case "PK", "BD", "AF": return ("Karachi", true)
        case "SG", "MY", "ID": return ("Singapore", false)
        case "TR": return ("Turkey", false)
        case "US", "CA", "GB": return ("Moonsighting", false)
        default: return ("MuslimWorldLeague", false)
        }
    }
}
