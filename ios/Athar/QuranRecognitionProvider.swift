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
        .init(backendID: "whisperkit-bundled",
              modelID: "fazalshaikh123/ultra-fast-tarteel-coreml",
              modelRevision: "0338074ac8d662f6f52c5d66b433cac74202158e", configuredLanguage: "ar",
              delivery: .overlappingAudioWindows, processesLocally: true,
              wordTimestamps: true, wordConfidence: true, phonemeEvidence: false,
              calibratedWordingAssessment: false, validatedTajweedAssessment: false)
    }
}
