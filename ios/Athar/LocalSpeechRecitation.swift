import Foundation
import Combine

/// Recovery access to pre-upgrade data, without an unverified speech grader.
/// Opening this adapter never downloads a model or changes existing bytes.
@MainActor final class LegacySpeechArchive: ObservableObject {
    @Published private(set) var savedPosition: SpeechSessionPosition?
    @Published private(set) var deleting = false
    @Published var message: String?
    private let positions: SpeechPositionStore
    private let defaults: UserDefaults
    private let modelFolder: URL?
    var unreadablePosition: Data? { positions.unreadable }
    var previousPosition: Data? { defaults.data(forKey: "noor.speech.previousPosition.v1") }
    init(defaults: UserDefaults = .standard, modelFolder: URL? = nil) {
        self.defaults = defaults
        positions = SpeechPositionStore(defaults: defaults)
        savedPosition = positions.value
        self.modelFolder = modelFolder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("NoorSpeech", isDirectory: true)
    }
    func readerPosition(corpus: [Surah], plan: MemorizationPlan, pending: MushafStudySession?) -> (chapter: Int, ayah: Int) {
        if let key = pending?.currentKey ?? pending?.keys.last {
            let parts = key.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, corpus.indices.contains(parts[0] - 1), corpus[parts[0] - 1].ayahs.indices.contains(parts[1] - 1) { return (parts[0], parts[1]) }
        }
        if let savedPosition, savedPosition.valid(corpus: corpus) {
            let words = RecitationComparison.words(chapter: corpus[savedPosition.chapter - 1], from: savedPosition.from, to: savedPosition.to)
            if !words.isEmpty { return (savedPosition.chapter, words[min(savedPosition.nextWord, words.count - 1)].ayah) }
        }
        if corpus.indices.contains(plan.chapter - 1), corpus[plan.chapter - 1].ayahs.indices.contains(plan.from - 1) { return (plan.chapter, plan.from) }
        return (1, 1)
    }
    func eraseSavedPosition() { positions.erase(); savedPosition = nil }
    /// Invoked only by the user's explicit local-data erasure action.
    @discardableResult func eraseModel() async -> Bool {
        guard !deleting else { return false }
        deleting = true; defer { deleting = false }
        do {
            if let modelFolder, FileManager.default.fileExists(atPath: modelFolder.path) { try FileManager.default.removeItem(at: modelFolder) }
            defaults.removeObject(forKey: "noor.speechModelFolder.v1"); return true
        } catch { message = "تعذّر حذف ملفات النموذج القديم. حاول مجددًا؛ بقيت بيانات التسميع محفوظة."; return false }
    }
}
