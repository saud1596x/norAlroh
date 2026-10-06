import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Ayah: Codable, Identifiable {
    let number: Int
    let text: String
    var id: Int { number }
}

struct Surah: Codable, Identifiable {
    let number: Int
    let name: String
    let englishName: String
    let revelationType: String
    let ayahs: [Ayah]
    var id: Int { number }
}

enum Mood: String, Codable, CaseIterable, Identifiable {
    case calm, gratitude, begin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calm: "أحتاج سكينة"
        case .gratitude: "أشعر بالامتنان"
        case .begin: "أريد بداية"
        }
    }
    var name: String {
        switch self {
        case .calm: "رحلة السكينة"
        case .gratitude: "رحلة الامتنان"
        case .begin: "رحلة البداية"
        }
    }
    var symbol: String {
        switch self {
        case .calm: "leaf"
        case .gratitude: "sun.max"
        case .begin: "sparkles"
        }
    }
    var reference: (surah: Int, ayah: Int) {
        switch self {
        case .calm: (13, 28)
        case .gratitude: (14, 7)
        case .begin: (94, 5)
        }
    }
    var dhikr: String {
        switch self {
        case .calm: "سبحان الله"
        case .gratitude: "الحمد لله"
        case .begin: "أستغفر الله"
        }
    }
    var question: String {
        switch self {
        case .calm: "ما الذي يشغلك الآن؟ وما الخطوة الصغيرة التي تستطيع تركها أو اتخاذها بهدوء؟"
        case .gratitude: "اكتب نعمة صغيرة مرّت عليك اليوم، وشخصًا يمكنك شكره عليها."
        case .begin: "ما العمل الصغير الذي تريد البدء به؟ اكتبه بحيث تستطيع فعله اليوم."
        }
    }
    var action: String {
        switch self {
        case .calm: "أغلق إشعاراتك لبضع دقائق، وامنح من بجانبك حضورك الكامل."
        case .gratitude: "أرسل كلمة شكر صادقة لشخص قدّرته اليوم."
        case .begin: "اختر عمل خير بسيطًا تستطيع فعله اليوم: مساعدة، صلة، أو كلمة طيبة."
        }
    }
}

struct JourneyRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let mood: Mood
    let minutes: Int
}
struct JournalNote: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let text: String
}

struct City: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let region: String?
    let countryCode: String?
    let sourceID: Int?
    static let fallback = City(id: "makkah", name: "مكة المكرمة", latitude: 21.42664,
        longitude: 39.82563, timeZone: "Asia/Riyadh", region: "مكة المكرمة", countryCode: "SA", sourceID: 104515)
    static let all: [City] = {
        guard let data = QuranResources.data("saudi-cities"),
              let cities = try? JSONDecoder().decode([City].self, from: data), !cities.isEmpty,
              Set(cities.map(\.id)).count == cities.count,
              cities.allSatisfy({ $0.countryCode == "SA" && $0.timeZone == "Asia/Riyadh"
                  && (16...33).contains($0.latitude) && (34...56).contains($0.longitude) }) else { return [fallback] }
        return cities
    }()
    static var defaultCity: City { all.first(where: { $0.id == "makkah" }) ?? fallback }
    static func normalized(_ value: City) -> City {
        all.first(where: { $0.id == value.id }) ?? all.first(where: { $0.name == value.name }) ?? defaultCity
    }

}

struct DeviceData: Codable {
    var journeys: [JourneyRecord] = []
    var notes: [JournalNote] = []
    var bookmarks: [String] = []
    var city = City.defaultCity
    var method = "UmmAlQura"
    var hanafi = false
    var lowMotion = false
    var largeQuran = false
}

@MainActor
final class AtharStore: ObservableObject {
    @Published private(set) var data = DeviceData()
    @Published var error: String?
    @Published private(set) var unreadableDeviceData: Data?
    let quran: [Surah]
    private var fileURL: URL?

    init(directory: URL? = nil) {
        do {
            guard let decoded = QuranResources.corpus else {
                throw CocoaError(.fileReadCorruptFile)
            }
            quran = decoded
        } catch {
            quran = []
            self.error = "تعذر تحميل النص القرآني من ملفات التطبيق. أعد تثبيت نسخة موثوقة."
        }
        do {
            let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = base.appendingPathComponent("Athar", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            let file = folder.appendingPathComponent("device-data.json")
            fileURL = file
            if FileManager.default.fileExists(atPath: file.path) {
                let original = try Data(contentsOf: file)
                do { data = try JSONDecoder().decode(DeviceData.self, from: original) }
                catch {
                    unreadableDeviceData = original
                    self.error = "تعذر قراءة بياناتك السابقة. يمكنك حفظ نسخة منها بالتصدير، أو حذفها من الإعدادات للبدء من جديد."
                    return
                }
                data.city = City.normalized(data.city)
                if !["UmmAlQura", "UmmAlQuraRamadan"].contains(data.method) { data.method = "UmmAlQura" }
            }
        } catch {
            self.error = "تعذر فتح بياناتك المحلية. لن يستبدل التطبيق الملف السابق حتى تعالج المشكلة."
            fileURL = nil
        }
    }

    @discardableResult
    func update(_ mutation: (inout DeviceData) -> Void) -> Bool {
        var candidate = data
        mutation(&candidate)
        guard unreadableDeviceData == nil else {
            error = "البيانات السابقة تحتاج استعادة. صدّر نسخة منها أو احذفها من الإعدادات قبل حفظ تغييرات جديدة."
            return false
        }
        candidate.city = City.normalized(candidate.city)
        if !["UmmAlQura", "UmmAlQuraRamadan"].contains(candidate.method) { candidate.method = "UmmAlQura" }
        guard let fileURL else {
            error = "التخزين غير متاح. صدّر بياناتك قبل إغلاق التطبيق."
            return false
        }
        do {
            let bytes = try JSONEncoder().encode(candidate)
            try bytes.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = candidate
            return true
        } catch {
            self.error = "لم تُحفظ التغييرات. تأكد من توفر مساحة على جهازك، ثم حاول مجددًا."
            return false
        }
    }

    func finish(mood: Mood, minutes: Int, note: String) -> Bool {
        update { data in
            data.journeys.insert(JourneyRecord(mood: mood, minutes: minutes), at: 0)
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { data.notes.insert(JournalNote(text: String(trimmed.prefix(5000))), at: 0) }
        }
    }

    func toggleBookmark(surah: Int, ayah: Int) {
        guard quran.indices.contains(surah - 1), quran[surah - 1].ayahs.indices.contains(ayah - 1) else { return }
        let key = "\(surah):\(ayah)"
        update { data in
            if data.bookmarks.contains(key) { data.bookmarks.removeAll { $0 == key } }
            else { data.bookmarks.insert(key, at: 0) }
        }
    }

    func erase() -> Bool {
        guard let fileURL else { error = "تعذّر فتح مساحة البيانات لحذفها. حاول مجددًا."; return false }
        do {
            let empty = DeviceData()
            try JSONEncoder().encode(empty).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            unreadableDeviceData = nil; data = empty; error = nil; return true
        } catch { self.error = "تعذّر حذف البيانات. لم تُستبدل البيانات السابقة."; return false }
    }
    func export() throws -> Data { try JSONEncoder().encode(data) }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .mpeg4Audio] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        bytes = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

// Tanzil XML keeps the unnumbered opening basmala separate from every numbered aya.
// Return the exact imported string; display formatting must never remove Quran words.
enum QuranText {
    static let basmala: String = {
        guard let corpus = QuranResources.corpus else { return "" }
        return corpus.first?.ayahs.first?.text ?? ""
    }()
    static let separateBasmalas: [String: String] = {
        guard let data = QuranResources.data("quran-basmalas"),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              Set(values.keys) == Set((2...114).filter { $0 != 9 }.map { String($0) }),
              values.values.allSatisfy({ !$0.isEmpty }) else { return [:] }
        return values
    }()
    static func verse(chapter: Int, ayah: Ayah) -> String {
        ayah.text
    }
}

struct NoorPrivacyExport: Codable {
    var schemaVersion = 5
    var exportedAt = Date()
    let device: DeviceData
    let adhkarCounters: [String: Int]
    let adhkarFavorites: [String]
    let memorizationPlan: MemorizationPlan
    let memorizationHistory: [MemorizationResult]
    var memorizationSession: MemorizationSession? = nil
    let prayerPreferences: PrayerNotificationPreferences
    let localRecording: Data?
    let lastMushafPage: Int
    let unreadableDeviceData: Data?
    let unreadableMemorizationHistory: Data?
    var memorizationProgress: MemorizationProgress? = nil
}
