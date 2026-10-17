import Foundation

/// Backend capabilities are distinct from ready assets and measured product quality.
struct QuranRecognitionCapabilities: Equatable, Sendable {
    enum Delivery: String, Sendable { case overlappingAudioWindows, revisionedStreaming }
    let backendID: String
    let modelID: String
    let modelRevision: String
    let configuredLanguage: String
    let delivery: Delivery
    let processesLocally: Bool
    let wordTimestamps: Bool
    let wordConfidence: Bool
    let phonemeEvidence: Bool
    let calibratedWordingAssessment: Bool
    let validatedTajweedAssessment: Bool
}

protocol QuranSpeechRecognitionProvider: Sendable {
    var capabilities: QuranRecognitionCapabilities { get }
    func prepare() async throws
    func recognize(_ window: QuranAudioWindow) async throws -> QuranRecognitionWorker.Result
}

extension QuranRecognitionWorker: QuranSpeechRecognitionProvider {
    nonisolated var capabilities: QuranRecognitionCapabilities {
        let descriptor = QuranRecognitionModelDescriptor.bundled
        return .init(backendID: "whisperkit-bundled",
              modelID: descriptor?.model ?? "unavailable",
              modelRevision: descriptor?.revision ?? "unavailable", configuredLanguage: "ar",
              delivery: .overlappingAudioWindows, processesLocally: true,
              wordTimestamps: true, wordConfidence: true, phonemeEvidence: false,
              calibratedWordingAssessment: false, validatedTajweedAssessment: false)
    }
}

struct QuranRecognitionModelDescriptor: Decodable {
    let schema: Int
    let model: String
    let revision: String
    let configuration: String
    static var bundled: Self? {
        guard let root = Bundle.main.url(forResource: "RecitationModel", withExtension: nil),
              let bytes = try? Data(contentsOf: root.appendingPathComponent("verified-model.json")),
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.schema == 1,
              !value.model.isEmpty, !value.revision.isEmpty else { return nil }
        return value
    }
}
