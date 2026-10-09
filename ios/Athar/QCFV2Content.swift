import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Content Sync's full-copy contract. Glyphs are never bundled or substituted
/// into the QCF4 renderer. A font and its positioned words must share an edition.
struct QCFV2Snapshot: Decodable, Sendable {
    let resource_group: String
    let resource_id: Int
    // Immutable Content Sync edition matching the pinned original V2 fonts.
    let resource_content_id: Int
    let schema_version: Int
    let sync_sequence: Int
    let records: [Record]

    struct Record: Decodable, Sendable {
        let id: Int
        let record_type: String
        let mushaf_id: Int?
        let page_number: Int?
        let pages_count: Int?
        let lines_per_page: Int?
        let default_font_name: String?
        let word_id: Int?
        let verse_id: Int?
        let text: String?
        let char_type_name: String?
        let line_number: Int?
        let position_in_page: Int?
        let position_in_line: Int?
        let position_in_verse: Int?
    }

    enum Invalid: Error { case envelope, edition, page, word, sequence, verse }

    func validated() throws -> QCFV2Snapshot {
        guard resource_group == "mushafs", resource_id == 1, resource_content_id == 382,
              schema_version == 1, sync_sequence >= 0, records.count < 120_000 else { throw Invalid.envelope }
        let editions = records.filter { $0.record_type == "mushaf" }
        guard editions.count == 1, editions[0].id == 1,
              editions[0].pages_count == 604, editions[0].lines_per_page == 15,
              editions[0].default_font_name == "v2" else { throw Invalid.edition }
        let pages = records.filter { $0.record_type == "mushaf_page" }
        guard pages.count == 604, Set(pages.compactMap(\.page_number)) == Set(1...604),
              pages.allSatisfy({ $0.mushaf_id == 1 }) else { throw Invalid.page }
        let words = records.filter { $0.record_type == "mushaf_word" }
        guard words.count + pages.count + editions.count == records.count,
              Set(words.map(\.id)).count == words.count,
              Set(words.compactMap(\.word_id)).count == words.count else { throw Invalid.word }
        var positioned: [Int: [Record]] = [:]
        var verseEnds = Set<Int>()
        for word in words {
            guard word.mushaf_id == 1, let page = word.page_number, (1...604).contains(page),
                  let line = word.line_number, (1...15).contains(line),
                  let verse = word.verse_id, (1...6236).contains(verse),
                  let position = word.position_in_page, position > 0,
                  let inLine = word.position_in_line, inLine > 0,
                  let inVerse = word.position_in_verse, inVerse > 0,
                  let text = word.text, !text.isEmpty, text.utf16.count <= 16,
                  text.unicodeScalars.contains(where: { $0.value != 0x20 }),
                  text.unicodeScalars.allSatisfy({ $0.value == 0x20 || (0xFC00...0xFDFF).contains($0.value) }),
                  ["word", "end"].contains(word.char_type_name ?? "") else { throw Invalid.word }
            if word.char_type_name == "end", !verseEnds.insert(verse).inserted { throw Invalid.verse }
            positioned[page, default: []].append(word)
        }
        guard verseEnds == Set(1...6236), Set(positioned.keys) == Set(1...604) else { throw Invalid.verse }
        for pageWords in positioned.values {
            let ordered = pageWords.sorted { $0.position_in_page! < $1.position_in_page! }
            guard ordered.map({ $0.position_in_page! }) == Array(1...ordered.count),
                  ordered.map({ $0.line_number! }) == ordered.map({ $0.line_number! }).sorted(),
                  ordered.map({ $0.verse_id! }) == ordered.map({ $0.verse_id! }).sorted() else { throw Invalid.sequence }
            // Upstream position_in_line resets inconsistently on some lines.
            // position_in_page is the verified ordering contract for rendering.
        }
        // Page order alone cannot detect a missing word after positions have
        // been renumbered. Validate each complete verse across page boundaries.
        var expectedVerse = 1
        var expectedPosition = 1
        for page in 1...604 {
            for word in positioned[page]!.sorted(by: { $0.position_in_page! < $1.position_in_page! }) {
                guard word.verse_id == expectedVerse,
                      word.position_in_verse == expectedPosition else { throw Invalid.sequence }
                if word.char_type_name == "end" {
                    guard expectedPosition > 1 else { throw Invalid.verse }
                    expectedVerse += 1
                    expectedPosition = 1
                } else {
                    expectedPosition += 1
                }
            }
        }
        guard expectedVerse == 6237, expectedPosition == 1 else { throw Invalid.verse }
        return self
    }

    func words(on page: Int) -> [Record] {
        records.filter { $0.record_type == "mushaf_word" && $0.page_number == page }
            .sorted { ($0.position_in_page ?? 0) < ($1.position_in_page ?? 0) }
    }
}

/// A failed refresh never overwrites the last validated offline copy.
/// The complete Content Sync snapshot is fetched again at least every seven
/// days when a connection is available; API credentials stay on the gateway.
actor QCFV2ContentCache {
    struct Entry: Codable, Sendable { let downloadedAt: Date; let snapshot: Data }
    private let file: URL
    private let endpoint: URL
    private let fetch: @Sendable (URL) async throws -> Data
    private var pending: Task<Entry, Error>?
    private var verifiedFile: SHA256.Digest?
    private var verifiedEntry: Entry?

    init(file: URL, endpoint: URL,
         fetch: @escaping @Sendable (URL) async throws -> Data = QCFV2ContentCache.download) {
        self.file = file; self.endpoint = endpoint; self.fetch = fetch
    }

    func cached() -> Entry? {
        guard let data = try? Data(contentsOf: file), data.count <= 48_000_000 else {
            verifiedFile = nil; verifiedEntry = nil; return nil
        }
        // Check the actual bytes on every entry. A replaced/corrupt file must
        // never inherit validation merely because its timestamp is unchanged.
        let fingerprint = SHA256.hash(data: data)
        if fingerprint == verifiedFile, let verifiedEntry { return verifiedEntry }
        verifiedFile = nil; verifiedEntry = nil
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.snapshot.count <= 32_000_000,
              (try? JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot).validated()) != nil else { return nil }
        verifiedFile = fingerprint; verifiedEntry = entry
        return entry
    }

    /// Open a verified offline copy without waiting for a connected refresh.
    /// The existing seven-day refresh policy still runs in the background.
    func readingEntry(now: Date = Date()) async throws -> Entry {
        if let entry = cached() {
            Task { _ = try? await self.refresh(now: now) }
            return entry
        }
        return try await refresh(now: now)
    }

    func refresh(now: Date = Date(), force: Bool = false) async throws -> Entry {
        if !force, let entry = cached(), now >= entry.downloadedAt,
           now.timeIntervalSince(entry.downloadedAt) < 7 * 86400 { return entry }
        if let pending { return try await pending.value }
        let endpoint = self.endpoint; let fetch = self.fetch; let file = self.file
        let task = Task {
            let bytes = try await fetch(endpoint)
            guard bytes.count <= 32_000_000 else { throw QCFV2Snapshot.Invalid.envelope }
            _ = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
            let entry = Entry(downloadedAt: now, snapshot: bytes)
            let manager = FileManager.default
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let stored = try JSONEncoder().encode(entry)
            #if os(iOS)
            try stored.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try stored.write(to: file, options: .atomic)
            #endif
            var protectedFile = file
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try protectedFile.setResourceValues(resources)
            return entry
        }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    static func download(_ endpoint: URL) async throws -> Data {
        guard endpoint.scheme == "https", endpoint.host == "noor-quran-sync.onrender.com",
              endpoint.path == "/v1/mushaf/snapshot", endpoint.query == nil,
              endpoint.user == nil, endpoint.password == nil else { throw URLError(.badURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 75
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (temporary, response) = try await session.download(from: endpoint)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType == "application/json",
              let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 32_000_000 else { throw URLError(.badServerResponse) }
        return try Data(contentsOf: temporary)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}

/// All reader entries share one cache, including its in-flight refresh.
@MainActor enum MushafReadingResources {
    private static var contentCache: QCFV2ContentCache?
    static func cache() throws -> QCFV2ContentCache {
        if let contentCache { return contentCache }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let value = QCFV2ContentCache(file: directory.appendingPathComponent("qcf-v2-cache.json"),
            endpoint: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        contentCache = value
        return value
    }
}

/// Decoding, authored-row verification and word indexing run off MainActor.
/// A new payload is always validated before replacing a prepared reading copy.
actor MushafReadingPreparation {
    static let shared = MushafReadingPreparation()
    struct Content: Sendable {
        let snapshot: QCFV2Snapshot
        let rows: OriginalMushafRows
        let studyIndex: MushafStudyWordIndex
        let versePages: [String: Int]
    }
    private var source: Data?
    private var corpusKeys: [String] = []
    private var prepared: Content?

    func prepare(_ bytes: Data, keys: [String]) throws -> Content {
        try Task.checkCancellation()
        guard keys.count == 6236, Set(keys).count == 6236 else { throw QCFV2Snapshot.Invalid.verse }
        if source == bytes, corpusKeys == keys, let prepared { return prepared }
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: bytes).validated()
        let rows = try OriginalMushafRows.load()
        try rows.validate(snapshot)
        let index = MushafStudyWordIndex(snapshot: snapshot, keys: keys)
        let pages = index.pages.compactMapValues { $0.first }
        guard pages.count == 6236 else { throw QCFV2Snapshot.Invalid.verse }
        try Task.checkCancellation()
        let content = Content(snapshot: snapshot, rows: rows, studyIndex: index, versePages: pages)
        source = bytes; corpusKeys = keys; prepared = content
        return content
    }
}
