import Foundation
import RecitationEvidence
import WhisperKit
import Darwin

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
    let gatedWords: [WordTiming]
    let gateRejections: [String]
    let rawValidationIssues: [String]
    let noSpeechProbabilities: [Float]
    let validationIssues: [String]
}

struct ProbeReport: Codable {
    let modelRevision: String
    let runtimeRevision: String
    let platform: String
    let scope: String
    let windows: [ProbeWindow]
}

@main struct RecitationEngineProbe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Native engine investigation failed: \(error)\n".utf8))
            // A thrown async-main error traps and loses buffered diagnostic
            // stdout. A regular failed exit retains all already-written evidence.
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
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
                let windowSamples = Array(samples[start..<end])
                var rawIssues: [String] = []
                for (index, word) in words.enumerated() {
                    if !word.start.isFinite || !word.end.isFinite || !word.probability.isFinite {
                        rawIssues.append("Word \(index): non-finite timing or confidence")
                    } else if word.start < 0 || word.end < word.start || word.end > duration + 0.1 {
                        rawIssues.append("Word \(index): \(word.start)...\(word.end) outside audio 0...\(duration)")
                    } else if !(0...1).contains(word.probability) {
                        rawIssues.append("Word \(index): confidence outside 0...1")
                    }
                }
                if fixture.kind == "silence" && !words.isEmpty {
                    rawIssues.append("Model emitted words for a digital-silence control")
                }
                var gatedWords: [WordTiming] = []
                var rejections: [String] = []
                for (index, word) in words.enumerated() {
                    let evidence = AudioEvidenceGate.Evidence(start: word.start, end: word.end,
                                                              probability: word.probability)
                    if let reason = AudioEvidenceGate.rejection(evidence, samples: windowSamples) {
                        rejections.append("Word \(index): \(reason.rawValue)")
                    } else { gatedWords.append(word) }
                }
                // Neither confidence nor acoustic energy proves that an Arabic
                // word is Quran text. Exact corpus alignment remains a separate
                // acceptance gate; these words cannot update reader progress.
                var issues: [String] = []
                if ["silence", "noise"].contains(fixture.kind), !gatedWords.isEmpty {
                    issues.append("Acoustic/timing gate accepted a no-speech control")
                }
                if fixture.kind == "professional-reference", gatedWords.isEmpty {
                    issues.append("Acoustic/timing gate rejected all reference words")
                }
                windows.append(.init(fixture: fixture.name, kind: fixture.kind,
                    audioStart: Double(start) / 16_000, audioEnd: Double(end) / 16_000,
                    inferenceSeconds: elapsed, text: output.map(\.text).joined(separator: " "),
                    words: words, gatedWords: gatedWords, gateRejections: rejections,
                    rawValidationIssues: rawIssues,
                    noSpeechProbabilities: output.flatMap(\.segments).map(\.noSpeechProb),
                    validationIssues: issues))
                // Keep every decoded window, including failures. A late control
                // failure must not destroy earlier real model evidence.
                try write(windows, to: arguments[4])
                print("\(fixture.name) [\(Double(start) / 16_000)...\(Double(end) / 16_000)] \(words.count) words, \(elapsed)s inference: \(output.map(\.text).joined(separator: " ").prefix(180))")
                print("ACOUSTIC GATE: \(gatedWords.count)/\(words.count) retained; not corpus-aligned")
                for issue in rawIssues { print("RAW MODEL DIAGNOSTIC: \(issue)") }
                for rejection in rejections { print("REJECTED RAW WORD: \(rejection)") }
                for issue in issues { print("REJECTED WINDOW: \(issue)") }
            }
        }
        await engine.unloadModels()
        let invalid = windows.filter { !$0.validationIssues.isEmpty }
        guard invalid.isEmpty else {
            throw ProbeFailure("Native model failed \(invalid.count) window controls; raw evidence saved. Do not connect raw output to reader progress.")
        }
        print("Saved \(windows.count) actual Core ML decoding windows. Acoustic controls passed; raw model failures remain in the report. Accuracy, exact alignment and live iPhone capture are not approved.")
    }

    private static func write(_ windows: [ProbeWindow], to path: String) throws {
        let report = ProbeReport(modelRevision: "0338074ac8d662f6f52c5d66b433cac74202158e",
            runtimeRevision: "1e2a163736dfa5a198e637ae44c114e1c6d5cc2d",
            platform: "macOS Core ML; not a live iPhone session",
            scope: "Professional reference clips plus explicitly assembled repetitions, returns, silence and noise. Raw recognition diagnostics only; no pronunciation, Tajweed or reader grade.",
            windows: windows)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        try encoder.encode(report).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
