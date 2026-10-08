import Foundation
import WhisperKit

struct ProbeFixture: Codable {
    let name: String
    let file: String
    let kind: String
}

struct ProbeWindow: Codable {
    let fixture: String
    let kind: String
    let audioStart: Double
    let audioEnd: Double
    let inferenceSeconds: Double
    let text: String
    let words: [WordTiming]
    let noSpeechProbabilities: [Float]
}

struct ProbeReport: Codable {
    let modelRevision: String
    let runtimeRevision: String
    let platform: String
    let scope: String
    let windows: [ProbeWindow]
}

@main struct RecitationEngineProbe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            throw ProbeFailure("Usage: probe MODEL_FOLDER TOKENIZER_FOLDER FIXTURES_FOLDER REPORT_JSON")
        }
        let fixtureFolder = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let fixtures = try JSONDecoder().decode([ProbeFixture].self,
            from: Data(contentsOf: fixtureFolder.appendingPathComponent("fixtures.json")))
        guard !fixtures.isEmpty else { throw ProbeFailure("No real audio fixtures supplied") }
        let engine = try await WhisperKit(WhisperKitConfig(
            modelFolder: arguments[1],
            tokenizerFolder: URL(fileURLWithPath: arguments[2], isDirectory: true),
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false))
        let options = DecodingOptions(language: "ar", temperatureFallbackCount: 0,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true,
            suppressBlank: true, concurrentWorkerCount: 1)
        var windows: [ProbeWindow] = []
        for fixture in fixtures {
            // Loading, resampling and inference are the real Apple runtime APIs.
            let samples = try AudioProcessor.loadAudioAsFloatArray(
                fromPath: fixtureFolder.appendingPathComponent(fixture.file).path)
            guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else {
                throw ProbeFailure("Unreadable audio: \(fixture.name)")
            }
            let count = samples.count
            // Never submit unbounded live history: overlapping eight-second
            // windows retain audible returns/repetitions that long ASR deduplicates.
            let endpoints: [Int]
            if fixture.kind == "repeat" || fixture.kind == "return" {
                endpoints = Array(stride(from: min(64_000, count), to: count, by: 32_000)) + [count]
            } else { endpoints = [count] }
            for end in endpoints {
                let start = max(0, end - 128_000)
                let began = Date()
                let output = try await engine.transcribe(audioArray: Array(samples[start..<end]),
                                                        decodeOptions: options)
                let elapsed = Date().timeIntervalSince(began)
                let words = output.flatMap(\.allWords)
                let duration = Float(end - start) / 16_000
                guard words.allSatisfy({ word in
                    word.start.isFinite && word.end.isFinite && word.probability.isFinite
                        && word.start >= 0 && word.end >= word.start
                        && word.end <= duration + 0.1 && (0...1).contains(word.probability)
                }) else { throw ProbeFailure("Invalid real word timing in \(fixture.name)") }
                windows.append(.init(fixture: fixture.name, kind: fixture.kind,
                    audioStart: Double(start) / 16_000, audioEnd: Double(end) / 16_000,
                    inferenceSeconds: elapsed, text: output.map(\.text).joined(separator: " "),
                    words: words, noSpeechProbabilities: output.flatMap(\.segments).map(\.noSpeechProb)))
            }
        }
        let report = ProbeReport(modelRevision: "0338074ac8d662f6f52c5d66b433cac74202158e",
            runtimeRevision: "1e2a163736dfa5a198e637ae44c114e1c6d5cc2d",
            platform: "macOS Core ML; not a live iPhone session",
            scope: "Professional reference clips plus explicitly assembled repetitions, returns, silence and noise. Raw recognition diagnostics only; no pronunciation, Tajweed or reader grade.",
            windows: windows)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: arguments[4]), options: .atomic)
        await engine.unloadModels()
        print("Saved \(windows.count) actual Core ML decoding windows. Accuracy requires reviewing the report; execution success is not feature acceptance.")
    }
}

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
