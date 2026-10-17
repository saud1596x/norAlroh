import XCTest
@testable import Athar

final class NoorReciterTests: XCTestCase {
    func testVerseCacheKeepsEachReciterSeparateAndRejectsInventedDirectories() throws {
        var urls = Set<URL>(), keys = Set<String>()
        for reader in NoorVerseReciter.all {
            let key = try XCTUnwrap(NoorVerseReciter.cacheKey(directory: reader.id, verse: "2:255"))
            let url = try XCTUnwrap(NoorAudioIntegrity.url(key))
            XCTAssertEqual(url.host, "everyayah.com")
            XCTAssertEqual(url.path, "/data/\(reader.id)/002255.mp3")
            XCTAssertTrue(keys.insert(key).inserted)
            XCTAssertTrue(urls.insert(url).inserted)
        }
        XCTAssertEqual(NoorVerseReciter.cacheKey(directory: "Abdul_Basit_Murattal_64kbps", verse: "2:255"), "2:255",
                       "Existing verified default-reciter cache remains readable")
        XCTAssertNil(NoorVerseReciter.cacheKey(directory: "../wrong", verse: "2:255"))
        XCTAssertNil(NoorAudioIntegrity.url("v:unknown:2:255"))
        XCTAssertNil(NoorAudioIntegrity.url("v:Hudhaify_64kbps:2:999"))
        XCTAssertNil(NoorAudioIntegrity.url("v:Hudhaify_64kbps:2:255:extra"))
        XCTAssertNil(NoorVerseReciter.cacheKey(directory: "Hudhaify_64kbps", verse: "v:Hudhaify_64kbps:2:255"))
    }
    func testCatalogContainsVerifiedCoverageAndDistinctRecordings() throws {
        let readers = NoorReciterCatalog.reciters
        XCTAssertEqual(readers.count, 20)
        XCTAssertEqual(Set(readers.map(\.recordingID)).count, readers.count)
        XCTAssertNil(readers.first { $0.id == 21188 })
        for reader in readers {
            XCTAssertEqual(reader.surahs.count, Set(reader.surahs).count)
            XCTAssertEqual(Set(reader.surahs), Set(1...114))
            for number in reader.surahs {
                XCTAssertEqual(reader.audioURL(surah: number)?.lastPathComponent,
                               String(format: "%03d.mp3", number))
            }
            XCTAssertNil(reader.audioURL(surah: 0))
            XCTAssertNil(reader.audioURL(surah: 115))
            for missing in (1...114) where !reader.surahs.contains(missing) {
                XCTAssertNil(reader.audioURL(surah: missing))
            }
        }
    }
    func testUntrustedServersCannotBecomeAudioSources() {
        for server in ["http://cdn.mp3quran.net/audio/a/r1/", "https://evil.example/audio/a/r1/",
                       "https://cdn.mp3quran.net@evil.example/audio/a/r1/", "https://cdn.mp3quran.net/audio/a/r1/?token=x"] {
            XCTAssertNil(NoorReciter(id: 1, name: "قارئ", recordingID: 1,
                                    server: server, surahs: [1]).audioURL(surah: 1))
        }
    }
    func testDirectoryURLProducesAnAudioFileOnFoundation() {
        let reader = NoorReciter(id: 54, name: "السديس", recordingID: 54,
            server: "https://cdn.mp3quran.net/audio/abdulrahman-sudais/r1/", surahs: [1, 114])
        XCTAssertEqual(reader.audioURL(surah: 1)?.absoluteString,
            "https://cdn.mp3quran.net/audio/abdulrahman-sudais/r1/001.mp3")
        XCTAssertEqual(reader.audioURL(surah: 114)?.absoluteString,
            "https://cdn.mp3quran.net/audio/abdulrahman-sudais/r1/114.mp3")
        XCTAssertNil(reader.audioURL(surah: 2))
    }
    @MainActor func testRecordingStopsPlaybackAndStaleLeaseCannotUnlockIt() {
        let focus = NoorAudioFocus(), player = UUID(), first = UUID(), second = UUID()
        var stops = 0
        focus.register(player) { stops += 1 }
        XCTAssertTrue(focus.acquireRecording(first))
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(focus.preparePlayback(player))
        XCTAssertFalse(focus.acquireRecording(second))
        focus.releaseRecording(first)
        XCTAssertTrue(focus.acquireRecording(second))
        focus.releaseRecording(first)
        XCTAssertFalse(focus.preparePlayback(player))
        focus.releaseRecording(second)
        XCTAssertTrue(focus.preparePlayback(player))
    }
    @MainActor func testActualPlayerCannotStartReferenceAudioDuringRecording() {
        let lease = UUID()
        let audio = MushafVerseAudio(source: { _ in URL(string: "https://cdn.mp3quran.net/audio/abdulrahman-sudais/r1/001.mp3") })
        XCTAssertTrue(NoorAudioFocus.shared.acquireRecording(lease))
        defer { NoorAudioFocus.shared.releaseRecording(lease) }
        audio.play(["1"])
        XCTAssertEqual(audio.error, "أوقف التسميع أولًا للاستماع إلى التلاوة.")
        XCTAssertNil(audio.playing)
        XCTAssertNil(audio.loadingKey)
    }
}
