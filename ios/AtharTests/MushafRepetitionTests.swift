import XCTest
import AVFoundation
import Combine
import Network
@testable import Athar

final class MushafRepetitionTests: XCTestCase {
    @MainActor func testNonRespondingStreamTimesOutAndCannotReviveStoppedPlayer() async throws {
        // Real AVPlayer with a local HTTP connection which accepts bytes but
        // never supplies media. No CDN delay or mock status callback is needed.
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "Local stalled media source is listening")
        let queue = DispatchQueue(label: "Noor.StalledMedia")
        var connections: [NWConnection] = []
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connections.append(connection); connection.start(queue: queue)
        }
        listener.start(queue: queue)
        defer { queue.sync { listener.cancel(); connections.forEach { $0.cancel() } } }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/stalled.mp3"))
        let sound = MushafVerseAudio(source: { _ in url }, loadTimeoutSeconds: 0.4)
        defer { sound.stop() }
        let failed = expectation(description: "Stalled stream produces a visible bounded error")
        let observation = sound.$error.compactMap { $0 }.prefix(1).sink { _ in failed.fulfill() }
        defer { observation.cancel() }
        var starts = 0; sound.onVerse = { _ in starts += 1 }
        sound.play(["114:1"])
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertNil(sound.loadingKey); XCTAssertNil(sound.playing)
        XCTAssertTrue(sound.error?.contains("وقتًا طويلًا") == true,
            "The actual load deadline must fire, rather than an unrelated stream rejection")
        XCTAssertEqual(starts, 0)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(sound.loadingKey); XCTAssertEqual(starts, 0)
    }
    private func fixture() throws -> URL {
        // Silent AAC tests AVPlayer/end timing, never Quran pronunciation.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        memset(try XCTUnwrap(buffer.floatChannelData)[0], 0, 16000 * MemoryLayout<Float>.size)
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
            try file.write(from: buffer)
        } // Close the encoder before validating or giving the file to AVPlayer.
        let decoded = try AVAudioFile(forReading: url)
        let check = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: decoded.processingFormat,
            frameCapacity: AVAudioFrameCount(decoded.length)))
        try decoded.read(into: check)
        XCTAssertGreaterThan(check.frameLength, 0, "AAC must actually decode before playback")
        XCTAssertEqual(Double(check.frameLength) / decoded.processingFormat.sampleRate, 1, accuracy: 0.15)
        return url
    }
    @MainActor func testRealPlayerRepeatsWholeRangeWithGapAfterEachEndAndNoTrailingGap() async throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let sound = MushafVerseAudio(source: { _ in url })
        defer { print("REPETITION_DIAGNOSTIC: \(sound.playbackDiagnostic)"); sound.stop() }
        var starts: [(String, Date)] = []
        let ended = expectation(description: "Four real AAC items reach final EOS")
        var fulfilled = false
        sound.onVerse = { starts.append(($0, Date())) }
        let observation = sound.$playing.sink { key in
            if key == nil, starts.count == 4, sound.waitingKey == nil, !fulfilled {
                fulfilled = true; ended.fulfill()
            }
        }
        defer { observation.cancel() }
        sound.play(["112:1", "112:2"], repetitions: 2, delaySeconds: 1)
        await fulfillment(of: [ended], timeout: 25)
        XCTAssertEqual(starts.map(\.0), ["112:1", "112:2", "112:1", "112:2"])
        for pair in zip(starts, starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.1.timeIntervalSince(pair.0.1), 1.8,
                "Actual one-second AAC must finish before the one-second gap")
        }
        XCTAssertNil(sound.waitingKey); XCTAssertNil(sound.loadingKey); XCTAssertNil(sound.error)
    }
    @MainActor func testStoppingRealInterVerseGapPreventsDelayedRestart() async throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let sound = MushafVerseAudio(source: { _ in url }); defer { print("REPETITION_DIAGNOSTIC: \(sound.playbackDiagnostic)"); sound.stop() }
        var starts: [String] = []; sound.onVerse = { starts.append($0) }
        let gap = expectation(description: "Real EOS enters cancellable gap")
        let observation = sound.$waitingKey.compactMap { $0 }.prefix(1).sink { _ in gap.fulfill() }
        defer { observation.cancel() }
        sound.play(["112:1"], repetitions: 3, delaySeconds: 1)
        await fulfillment(of: [gap], timeout: 10)
        sound.stop()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(starts, ["112:1"])
        XCTAssertNil(sound.playing); XCTAssertNil(sound.loadingKey); XCTAssertNil(sound.waitingKey)
    }
    @MainActor func testReplacementDuringRealGapCannotResumeOldRange() async throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let sound = MushafVerseAudio(source: { _ in url }); defer { print("REPETITION_DIAGNOSTIC: \(sound.playbackDiagnostic)"); sound.stop() }
        var starts: [String] = []
        let gap = expectation(description: "Original player actually finished")
        let replacement = expectation(description: "Replacement actually starts")
        let observation = sound.$waitingKey.compactMap { $0 }.prefix(1).sink { _ in gap.fulfill() }
        defer { observation.cancel() }
        sound.onVerse = { key in starts.append(key); if key == "113:1" { replacement.fulfill() } }
        sound.play(["112:1"], repetitions: 3, delaySeconds: 1)
        await fulfillment(of: [gap], timeout: 10)
        sound.play(["113:1"])
        await fulfillment(of: [replacement], timeout: 10)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(starts, ["112:1", "113:1"])
        XCTAssertNil(sound.waitingKey); XCTAssertNil(sound.error)
    }
    @MainActor func testOldArchiveDecodesAndRepeatOptionsSurviveRelaunchWithoutChangingLegacyPlan() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let original = Data(#"{"version":1}"#.utf8)
        let decoded = try JSONDecoder().decode(MushafStudyArchive.self, from: original)
        XCTAssertNil(decoded.repetition); XCTAssertTrue(decoded.valid(corpus: corpus))
        let suite = "Noor.Repeat." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(original, forKey: "noor.mushaf.study")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.configure(.init(chapter: 67, from: 1, to: 5, daily: 3), corpus: corpus))
        let legacy = defaults.data(forKey: "noor.memorization.plan")
        var next = store.mushafStudy; next.repetition = .init(count: 4, delaySeconds: 2)
        XCTAssertTrue(store.saveMushafStudy(next))
        XCTAssertEqual(MemorizationStore(defaults: defaults).mushafStudy.repetition, next.repetition)
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.plan"), legacy)
        for invalid in [MushafRepeatPreferences(count: 0, delaySeconds: 2), .init(count: 21, delaySeconds: 2), .init(count: 3, delaySeconds: -1), .init(count: 3, delaySeconds: 31)] {
            var rejected = next; rejected.repetition = invalid
            XCTAssertFalse(store.saveMushafStudy(rejected))
            XCTAssertEqual(MemorizationStore(defaults: defaults).mushafStudy.repetition, next.repetition)
        }
        let sound = MushafVerseAudio(source: { _ in URL(fileURLWithPath: "/missing.m4a") })
        sound.play(["112:1"], repetitions: 0)
        XCTAssertNotNil(sound.error); XCTAssertNil(sound.loadingKey)
    }
}
