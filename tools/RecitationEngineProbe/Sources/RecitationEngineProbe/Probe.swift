import Foundation
import RecitationEvidence
import RecitationAlignment
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
    let alignedEvidence: [QuranWordEvidence]
    let unresolvedNativeIDs: [Int]
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
        let bound = try await loadAuthoredWords()
        let engine = try await WhisperKit(WhisperKitConfig(
            modelFolder: arguments[1],
            tokenizerFolder: URL(fileURLWithPath: arguments[2], isDirectory: true),
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false))
        let options = DecodingOptions(language: "ar", temperatureFallbackCount: 0,
            skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: true,
            suppressBlank: true, concurrentWorkerCount: 1)
        var windows: [ProbeWindow] = []
        for fixture in fixtures {
            let keys: Set<String>
            switch fixture.kind {
            case "professional-reference": keys = [fixture.name]
            case "return": keys = ["114:1", "114:2", "114:3"]
            default: keys = ["112:1", "112:2", "112:3", "112:4"]
            }
            var tracker = QuranRecitationTracker(expected: bound.filter { keys.contains($0.verse) })
            let takeID = UUID()
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
                var runs: [[QuranHeardWord]] = [[]]
                var rejections: [String] = []
                for (index, word) in words.enumerated() {
                    let evidence = AudioEvidenceGate.Evidence(start: word.start, end: word.end,
                                                              probability: word.probability)
                    if let reason = AudioEvidenceGate.rejection(evidence, samples: windowSamples) {
                        rejections.append("Word \(index): \(reason.rawValue)")
                        runs.append([])
                    } else {
                        gatedWords.append(word)
                        // An ASR word containing multiple space-delimited tokens
                        // has no separate timings. Wait rather than fabricate them.
                        if QuranAlignedWord.tokens([word.word]).count == 1 {
                            runs[runs.count - 1].append(.init(text: word.word,
                                start: Double(word.start), end: Double(word.end), probability: Double(word.probability)))
                        } else { runs.append([]) }
                    }
                }
                var aligned: [QuranWordEvidence] = []
                for run in runs where !run.isEmpty {
                    aligned += try tracker.consume(run, takeID: takeID, offset: Double(start) / 16_000)
                }
                var issues: [String] = []
                if ["silence", "noise"].contains(fixture.kind), !gatedWords.isEmpty {
                    issues.append("Acoustic/timing gate accepted a no-speech control")
                }
                if fixture.kind == "professional-reference", gatedWords.isEmpty {
                    issues.append("Acoustic/timing gate rejected all reference words")
                }
                if ["silence", "noise"].contains(fixture.kind), !aligned.isEmpty {
                    issues.append("A no-speech control created authored word progress")
                }
                windows.append(.init(fixture: fixture.name, kind: fixture.kind,
                    audioStart: Double(start) / 16_000, audioEnd: Double(end) / 16_000,
                    inferenceSeconds: elapsed, text: output.map(\.text).joined(separator: " "),
                    words: words, gatedWords: gatedWords,
                    alignedEvidence: aligned,
                    unresolvedNativeIDs: tracker.expected.map(\.id).filter { !tracker.revealedIDs.contains($0) },
                    gateRejections: rejections,
                    rawValidationIssues: rawIssues,
                    noSpeechProbabilities: output.flatMap(\.segments).map(\.noSpeechProb),
                    validationIssues: issues))
                // Keep every decoded window, including failures. A late control
                // failure must not destroy earlier real model evidence.
                try write(windows, to: arguments[4])
                print("\(fixture.name) [\(Double(start) / 16_000)...\(Double(end) / 16_000)] \(words.count) words, \(elapsed)s inference: \(output.map(\.text).joined(separator: " ").prefix(180))")
                print("ACOUSTIC GATE: \(gatedWords.count)/\(words.count) retained")
                print("CORPUS ANCHOR: \(aligned.count) new timed events; \(tracker.revealedIDs.count)/\(tracker.expected.count) authored groups supported; unresolved groups are not reader errors")
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
        print("Saved \(windows.count) actual Core ML decoding windows and exact timed corpus anchors. Acoustic controls passed; raw model failures and unresolved positions remain in the report. Live iPhone accuracy and pronunciation grading are not approved.")
    }

    private static func loadAuthoredWords() async throws -> [QuranAlignedWord] {
        struct Chapter: Decodable { struct Verse: Decodable { let number: Int }; let number: Int; let ayahs: [Verse] }
        struct Snapshot: Decodable {
            struct Record: Decodable {
                let id: Int; let record_type: String; let char_type_name: String?
                let verse_id: Int?; let position_in_verse: Int?; let page_number: Int?; let text: String?
            }
            let resource_group: String; let resource_id: Int; let resource_content_id: Int
            let records: [Record]
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let corpus = try JSONDecoder().decode([Chapter].self, from: Data(contentsOf: root.appendingPathComponent("ios/Athar/quran.json")))
        let keys = corpus.flatMap { chapter in chapter.ayahs.map { "\(chapter.number):\($0.number)" } }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProbeFailure("Native word edition unavailable") }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.resource_group == "mushafs", snapshot.resource_id == 1,
              snapshot.resource_content_id == 382 else { throw QuranAlignmentFailure.invalidEdition }
        let native = try snapshot.records.filter { $0.record_type == "mushaf_word" && $0.char_type_name == "word" }.map { word -> QuranNativeWord in
            guard let verse = word.verse_id, keys.indices.contains(verse - 1),
                  let position = word.position_in_verse, let page = word.page_number, let glyph = word.text else {
                throw QuranAlignmentFailure.invalidEdition
            }
            return .init(id: word.id, verse: keys[verse - 1], position: position, page: page, glyph: glyph)
        }
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf: root.appendingPathComponent("content-sources/recitation-word-script.json")))
        return try script.bind(native: native, verseKeys: keys)
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
