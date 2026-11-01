import XCTest
import AVFoundation
@testable import Athar

final class NoorAdditionalReciterTests: XCTestCase {
    @MainActor func testActualThreeFatihaRecordingsDriveTheirOwnWordClocks() async throws {
        executionTimeAllowance = 120
        XCTAssertEqual(Set(NoorAdditionalReciters.reciters.map(\.id)), [1000001, 1000002, 1000003])
        let defaults = UserDefaults.standard
        // This is a player-clock test; reader position/geometry is outside its scope.
        let preferenceKeys = ["noor.mushaf.reciter"]
        let previousPreferences = preferenceKeys.map { defaults.object(forKey: $0) as? NSObject }
        defer {
            for (index, key) in preferenceKeys.enumerated() {
                XCTAssertEqual(defaults.object(forKey: key) as? NSObject, previousPreferences[index], key)
            }
        }
        for reciter in NoorAdditionalReciters.reciters {
            let choice = try XCTUnwrap(NoorMushafReciter.selected("surah:\(reciter.id):\(reciter.recordingID)"))
            let sourceURL = try XCTUnwrap(reciter.audioURL(surah: 1))
            let bookmarkKey = "noor.audio.bookmark." + choice.recordingIdentity
            let previousBookmark = defaults.object(forKey: bookmarkKey)
            // No source/cache/resolver override: exercise the actual production
            // URL, AVPlayer and published-clock path. No microphone is started.
            let audio = MushafVerseAudio()
            var proof: [String: Any] = ["scope": "ACTUAL_THREE_FATIHA_PLAYBACK_NOT_ALL_RECORDINGS_AUDIBLE_APPROVAL",
                "recordingID": reciter.recordingID, "internalReciterID": reciter.id,
                "url": sourceURL.absoluteString, "observedWordTracking": false]
            defer {
                proof["diagnostic"] = audio.playbackDiagnostic
                proof["error"] = audio.error ?? ""
                proof["observedSeconds"] = audio.currentSeconds.isFinite ? audio.currentSeconds : -1
                proof["loadedDuration"] = audio.durationSeconds.isFinite ? audio.durationSeconds : -1
                audio.stop()
                if let previousBookmark { defaults.set(previousBookmark, forKey: bookmarkKey) }
                else { defaults.removeObject(forKey: bookmarkKey) }
                XCTAssertEqual(defaults.object(forKey: bookmarkKey) as? NSObject, previousBookmark as? NSObject)
                XCTAssertNil(audio.playing); XCTAssertNil(audio.loadingKey); XCTAssertNil(audio.activeWordID)
                let bytes = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
                let attachment = XCTAttachment(string: bytes.flatMap { String(data: $0, encoding: .utf8) } ?? "Failed to encode actual playback proof")
                attachment.name = "additional-reciter-\(reciter.id)-actual-fatiha-clock"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            audio.selectReciter(choice)
            XCTAssertEqual(audio.currentRecordingIdentity, choice.recordingIdentity)
            audio.play(["1:1"])
            let ready = await waitForAudio(seconds: 15) {
                audio.error != nil || (audio.playing != nil && audio.durationSeconds.isFinite && audio.durationSeconds > 0)
            }
            XCTAssertTrue(ready, "Actual source did not become ready: \(reciter.id) \(audio.playbackDiagnostic)")
            XCTAssertNil(audio.error)
            guard ready, audio.error == nil, audio.durationSeconds.isFinite, audio.durationSeconds > 0 else { continue }
            let key = try XCTUnwrap(NoorAudioIntegrity.reciterKey(reciter, surah: 1))
            XCTAssertEqual(audio.playing, key)
            XCTAssertEqual(NoorAudioIntegrity.url(key), sourceURL)
            XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
            let loaded = await NoorSurahWordTimings.shared.track(reciter: reciter, surah: 1, ayahCount: 7)
            let track = try XCTUnwrap(loaded)
            let span = try XCTUnwrap(track.spans.filter { $0[0] == 1 }.max { ($0[3] - $0[2]) < ($1[3] - $1[2]) })
            XCTAssertEqual(span[1], 529420)
            let midpoint = Double(span[2] + span[3]) / 2000
            proof["sourceIntervalMS"] = [span[2], span[3]]; proof["seekSeconds"] = midpoint
            proof["expectedNativeID"] = span[1]; proof["expectedVerse"] = "1:1"
            XCTAssertLessThanOrEqual(Double(try XCTUnwrap(track.spans.last)[3]) / 1000, audio.durationSeconds + 0.05)
            audio.seek(to: midpoint)
            let tracked = await waitForAudio(seconds: 2) {
                audio.activeWordID == span[1] && audio.activeVerseKey == "1:1" && audio.currentSeconds.isFinite &&
                audio.currentSeconds >= Double(span[2]) / 1000 && audio.currentSeconds < Double(span[3]) / 1000
            }
            proof["observedWordTracking"] = tracked
            proof["activeNativeID"] = audio.activeWordID ?? -1; proof["activeVerse"] = audio.activeVerseKey ?? ""
            XCTAssertTrue(tracked, "Actual source did not drive its exact word clock: \(reciter.id) \(audio.playbackDiagnostic)")
            var advanced = false
            if tracked {
                let firstClock = audio.currentSeconds
                proof["firstTrackedSeconds"] = firstClock
                advanced = await waitForAudio(seconds: 1) {
                    audio.activeWordID == span[1] && audio.activeVerseKey == "1:1" && audio.currentSeconds.isFinite &&
                    audio.currentSeconds >= firstClock + 0.10 && audio.currentSeconds < Double(span[3]) / 1000
                }
            }
            proof["actualClockAdvancedInsideWord"] = advanced
            XCTAssertTrue(advanced, "Seeking alone is not playback: the actual clock must advance inside the same word")
            XCTAssertEqual(audio.currentRecordingIdentity, choice.recordingIdentity)
        }
    }

    @MainActor private func waitForAudio(seconds: Double, condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return false }
        }
        return condition()
    }

    func testAdditionalSourcesHaveSeparateExactRecordingsAndCacheKeys() throws {
        XCTAssertEqual(NoorAdditionalReciters.reciters.count, 3)
        XCTAssertEqual(NoorReciterCatalog.legacyReciters.count, 20)
        XCTAssertEqual(NoorReciterCatalog.reciters.count, 23)
        let maher = try XCTUnwrap(NoorAdditionalReciters.reciters.first { $0.id == 1000002 })
        XCTAssertEqual(maher.audioURL(surah: 114)?.absoluteString,
            "https://download.quranicaudio.com/quran/maher_almu3aiqly/year1440/114.mp3")
        let old = try XCTUnwrap(NoorReciterCatalog.legacyReciters.first { $0.id == 102 })
        XCTAssertNotEqual(NoorAudioIntegrity.reciterKey(old, surah: 1), NoorAudioIntegrity.reciterKey(maher, surah: 1))
        XCTAssertFalse(NoorSurahWordTimings.supports(old), "The old Maher recording cannot borrow the QDC clock")
        for reciter in NoorAdditionalReciters.reciters {
            let key = try XCTUnwrap(NoorAudioIntegrity.reciterKey(reciter, surah: 114))
            XCTAssertEqual(NoorAudioIntegrity.reciterRecording(key)?.0, reciter)
            XCTAssertEqual(NoorAudioIntegrity.url(key), reciter.audioURL(surah: 114))
            XCTAssertTrue(NoorSurahWordTimings.supports(reciter))
        }
    }

    func testForeignRecordingOrURLCannotAcquireAnAdditionalSourceClock() async throws {
        let maher = try XCTUnwrap(NoorAdditionalReciters.reciters.first { $0.id == 1000002 })
        for server in ["https://download.quranicaudio.com/quran/maher_almu3aiqly/", maher.server + "?q=1",
                       "http://download.quranicaudio.com/quran/maher_almu3aiqly/year1440/",
                       "https://cdn.mp3quran.net/audio/maher-muaiqly/r1/",
                       "https://download.quranicaudio.com@evil.example/quran/maher_almu3aiqly/year1440/"] {
            let foreign = NoorReciter(id: maher.id, name: maher.name, recordingID: maher.recordingID,
                                     server: server, surahs: maher.surahs)
            XCTAssertNil(foreign.audioURL(surah: 1)); XCTAssertFalse(NoorSurahWordTimings.supports(foreign))
            let track = await NoorSurahWordTimings.shared.track(reciter: foreign, surah: 1, ayahCount: 7)
            XCTAssertNil(track)
        }
        let unknown = NoorReciter(id: 1000004, name: maher.name, recordingID: 1000004, server: maher.server, surahs: maher.surahs)
        XCTAssertNil(unknown.audioURL(surah: 1)); XCTAssertFalse(NoorSurahWordTimings.supports(unknown))
    }

    func testAllThreeBundledClocksCoverEveryNativeWordIncludingFirstBasmala() async throws {
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self,
            from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let words = snapshot.records.filter {
            $0.record_type == "mushaf_word" && $0.char_type_name == "word"
        }
        let expected = Dictionary(uniqueKeysWithValues: try words.map { word in
            let verse = try XCTUnwrap(word.verse_id)
            return (word.id, keys[verse - 1])
        })
        for reciter in NoorAdditionalReciters.reciters {
            var seen = Set<Int>(), verses = Set<String>()
            for surah in corpus {
                let loaded = await NoorSurahWordTimings.shared.track(reciter: reciter, surah: surah.number, ayahCount: surah.ayahs.count)
                let track = try XCTUnwrap(loaded, "Missing additional source \(reciter.id):\(surah.number)")
                let last = try XCTUnwrap(track.spans.last)
                let duration = Double(last[3]) / 1000 + 1
                var previousEnd = 0
                for span in track.spans {
                    XCTAssertEqual(expected[span[1]], "\(surah.number):\(span[0])")
                    let midpoint = Double(span[2] + span[3]) / 2000
                    let position = track.position(at: midpoint, duration: duration)
                    XCTAssertEqual(position?.wordID, span[1])
                    XCTAssertEqual(position?.verse, "\(surah.number):\(span[0])")
                    if previousEnd < span[2] {
                        let gap = Double(previousEnd + span[2]) / 2000
                        XCTAssertNil(track.position(at: gap, duration: duration), "Never interpolate a source pause")
                    }
                    previousEnd = span[3]
                    seen.insert(span[1]); verses.insert("\(surah.number):\(span[0])")
                }
            }
            XCTAssertEqual(seen, Set(expected.keys)); XCTAssertEqual(seen.count, 77429)
            XCTAssertEqual(verses, Set(keys)); XCTAssertTrue(verses.contains("1:1"))
        }
    }
}
