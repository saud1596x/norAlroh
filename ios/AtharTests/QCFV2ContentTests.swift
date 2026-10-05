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

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: entry.snapshot) as? [String: Any])
        var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        let end = try XCTUnwrap(records.firstIndex { $0["char_type_name"] as? String == "end" })
        records.remove(at: end); envelope["records"] = records
        let invalid = try JSONSerialization.data(withJSONObject: envelope)
        let corrupted = QCFV2ContentCache(file: file, endpoint: endpoint, fetch: { _ in invalid })
        do { _ = try await corrupted.refresh(force: true); XCTFail("An incomplete Quran must be rejected") } catch { }
        let afterRejection = await corrupted.cached()
        XCTAssertEqual(afterRejection?.snapshot, entry.snapshot)
    }
}
