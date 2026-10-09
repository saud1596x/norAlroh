import XCTest
@testable import Athar

final class QCFV2ContentTests: XCTestCase {
    func testLiveSnapshotAndAtomicOfflineRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("qcf-v2.json")
        let endpoint = try XCTUnwrap(URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot"))
        let cache = QCFV2ContentCache(file: file, endpoint: endpoint)
        let now = Date()
        let entry = try await cache.refresh(now: now)
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot).validated()
        XCTAssertEqual(Set(snapshot.records.filter { $0.record_type == "mushaf_page" }.compactMap(\.page_number)), Set(1...604))
        XCTAssertEqual(snapshot.records.filter { $0.char_type_name == "end" }.count, 6236)
        XCTAssertEqual(snapshot.words(on: 1).first?.text, "ﱁ")
        XCTAssertEqual(snapshot.words(on: 1).first?.line_number, 9)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let layout = try QCFV2PageLayout.database(snapshot: snapshot, corpus: corpus)
        XCTAssertEqual(layout.pages.count, 604)
        XCTAssertEqual(layout.pages.first?.words.first?.line, 2)
        XCTAssertEqual(layout.pages.last?.font, "QCF2604")
        XCTAssertEqual(layout.pages.flatMap { $0.words.filter { $0.kind == "end" } }.count, 6236)
        let headings = layout.pages.flatMap { page in
            page.layout.values.compactMap { $0.type == "header" ? $0.chapter : nil }
        }.sorted()
        XCTAssertEqual(headings, Array(1...114))
        XCTAssertEqual(layout.pages[75].layout["15"]?.chapter, 4)
        XCTAssertEqual(layout.pages[76].layout["1"]?.type, "bismillah")
        XCTAssertEqual(layout.pages[76].words.first?.line, 2)
        let keys = corpus.flatMap { chapter in chapter.ayahs.map { "\(chapter.number):\($0.number)" } }
        let preparation = MushafReadingPreparation()
        let prepared = try await preparation.prepare(entry.snapshot, keys: keys)
        XCTAssertEqual(prepared.versePages.count, 6236)
        XCTAssertEqual(prepared.versePages["1:1"], 1)
        XCTAssertEqual(prepared.versePages["114:6"], 604)
        XCTAssertEqual(prepared.studyIndex.words["1:1"]?.count,
                       snapshot.records.filter { $0.verse_id == 1 && $0.char_type_name == "word" }.count)
        do {
            _ = try await preparation.prepare(Data("corrupt".utf8), keys: keys)
            XCTFail("A new invalid payload must not reuse previously prepared Quran content")
        } catch { }
        var duplicateKeys = keys; duplicateKeys[1] = duplicateKeys[0]
        do {
            _ = try await preparation.prepare(entry.snapshot, keys: duplicateKeys)
            XCTFail("Duplicate canonical keys must be rejected before indexing")
        } catch { }
        let restoredPreparation = try await preparation.prepare(entry.snapshot, keys: keys)
        XCTAssertEqual(restoredPreparation.versePages, prepared.versePages)

        // Hold the real snapshot fetch open: stale offline reading must return
        // before network completion, while still starting the required refresh.
        let networkStarted = expectation(description: "Connected refresh starts")
        let readingReturned = expectation(description: "Offline reading does not wait for refresh")
        let networkGate = SnapshotFetchGate()
        let delayed = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in
            networkStarted.fulfill()
            await networkGate.wait()
            return entry.snapshot
        })
        let staleNow = now.addingTimeInterval(8 * 86400)
        let openingSignal = await MainActor.run { SnapshotOpeningSignal() }
        let reading = Task {
            let value = try await delayed.readingEntry(now: staleNow, onDownload: { openingSignal.count += 1 })
            readingReturned.fulfill()
            return value
        }
        await fulfillment(of: [networkStarted, readingReturned], timeout: 10)
        await networkGate.release()
        let immediate = try await reading.value
        XCTAssertEqual(immediate.downloadedAt, now)
        XCTAssertEqual(immediate.snapshot, entry.snapshot)
        let cachedDownloadSignals = await openingSignal.count
        XCTAssertEqual(cachedDownloadSignals, 0, "A stale offline opening must not announce a foreground download")
        let refreshed = try await delayed.refresh(now: staleNow)
        XCTAssertEqual(refreshed.downloadedAt, staleNow)
        XCTAssertEqual(refreshed.snapshot, entry.snapshot)
        // Restore the original age for the following seven-day recovery checks.
        try JSONEncoder().encode(entry).write(to: file, options: .atomic)

        let persisted = await cache.cached()
        XCTAssertEqual(persisted?.snapshot, entry.snapshot)

        let offline = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in throw URLError(.notConnectedToInternet) })
        let reused = try await offline.refresh(now: now.addingTimeInterval(86400))
        XCTAssertEqual(reused.snapshot, entry.snapshot)
        do {
            _ = try await offline.refresh(now: now.addingTimeInterval(8 * 86400))
            XCTFail("A stale copy must attempt refresh when seven days have elapsed")
        } catch { }
        let retained = await offline.cached()
        XCTAssertEqual(retained?.snapshot, entry.snapshot, "Offline refresh must preserve the last valid copy")

        // A different edition can retain the same generic V2 family and glyph
        // range. Reject it before replacing the correctly paired offline copy.
        var changedEdition = try XCTUnwrap(JSONSerialization.jsonObject(with: entry.snapshot) as? [String: Any])
        changedEdition["resource_content_id"] = 383
        let changedEditionBytes = try JSONSerialization.data(withJSONObject: changedEdition)
        let mismatchedEditionCache = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in changedEditionBytes })
        do {
            _ = try await mismatchedEditionCache.refresh(force: true)
            XCTFail("Generic V2 name must not allow a different Content Sync edition")
        } catch { }
        let preservedEdition = await mismatchedEditionCache.cached()
        XCTAssertEqual(preservedEdition?.snapshot, entry.snapshot)

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: entry.snapshot) as? [String: Any])
        var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        let end = try XCTUnwrap(records.firstIndex { $0["char_type_name"] as? String == "end" })
        records.remove(at: end); envelope["records"] = records
        let invalid = try JSONSerialization.data(withJSONObject: envelope)
        let corrupted = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in invalid })
        do { _ = try await corrupted.refresh(force: true); XCTFail("An incomplete Quran must be rejected") } catch { }
        let afterRejection = await corrupted.cached()
        XCTAssertEqual(afterRejection?.snapshot, entry.snapshot)

        // Remove a word but repair its page positions: the old page-only
        // validation accepted this while silently omitting Quran content.
        var missingWordEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: entry.snapshot) as? [String: Any])
        var missingWordRecords = try XCTUnwrap(missingWordEnvelope["records"] as? [[String: Any]])
        let removed = try XCTUnwrap(missingWordRecords.firstIndex {
            $0["record_type"] as? String == "mushaf_word" && $0["verse_id"] as? Int == 1
                && $0["position_in_verse"] as? Int == 2
        })
        let removedPage = try XCTUnwrap(missingWordRecords[removed]["page_number"] as? Int)
        let removedPosition = try XCTUnwrap(missingWordRecords[removed]["position_in_page"] as? Int)
        missingWordRecords.remove(at: removed)
        for index in missingWordRecords.indices {
            if missingWordRecords[index]["record_type"] as? String == "mushaf_word",
               missingWordRecords[index]["page_number"] as? Int == removedPage,
               let position = missingWordRecords[index]["position_in_page"] as? Int, position > removedPosition {
                missingWordRecords[index]["position_in_page"] = position - 1
            }
        }
        missingWordEnvelope["records"] = missingWordRecords
        let missingWordBytes = try JSONSerialization.data(withJSONObject: missingWordEnvelope)
        let missingWordCache = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in missingWordBytes })
        do { _ = try await missingWordCache.refresh(force: true); XCTFail("A missing verse word must be rejected even with contiguous page positions") } catch { }
        let preservedAfterMissingWord = await missingWordCache.cached()
        XCTAssertEqual(preservedAfterMissingWord?.snapshot, entry.snapshot)
        // Even a same-timestamp replacement must invalidate memoized validation.
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let corruptFile = Data("invalid cached archive".utf8)
        try corruptFile.write(to: file, options: .atomic)
        if let modificationDate = originalAttributes[.modificationDate] {
            try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: file.path)
        }
        let afterDiskCorruption = await cache.cached()
        XCTAssertNil(afterDiskCorruption)
        let unreadable = QCFV2ContentCache(file: file, endpoint: endpoint,
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await unreadable.readingEntry()
            XCTFail("An invalid disk copy cannot satisfy offline reading")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: file), corruptFile, "A failed fetch must preserve recoverable bytes")
        let empty = QCFV2ContentCache(file: folder.appendingPathComponent("absent.json"), endpoint: endpoint,
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await empty.readingEntry(onDownload: { openingSignal.count += 1 })
            XCTFail("First-use offline reading must report unavailable original data honestly")
        } catch { }
        let firstDownloadSignals = await openingSignal.count
        XCTAssertEqual(firstDownloadSignals, 1, "Only an unavailable copy starts the explicit download state")

    }
}

private actor SnapshotFetchGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(); continuation = nil
    }
}

@MainActor private final class SnapshotOpeningSignal {
    var count = 0
}
