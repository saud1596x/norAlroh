import Foundation
import CryptoKit

/// Published ayah boundaries for an exact full-surah recording. These are
/// playback guidance only, never word timing or learner-recitation evidence.
struct NoorSurahAyahTimingTrack: Sendable {
    let surah: Int
    let spans: [[Int]] // ayah, inclusive start milliseconds, exclusive end
    init?(surah: Int, ayahCount: Int, spans: [[Int]]) {
        guard (1...114).contains(surah), ayahCount > 0,
              spans.count == ayahCount,
              spans.enumerated().allSatisfy({ index, span in
                  span.count == 3 && span[0] == index + 1 && span[1] >= 0
                      && span[2] > span[1] && span[2] <= 21_600_000
              }), zip(spans, spans.dropFirst()).allSatisfy({ $0.0[2] <= $0.1[1] }) else { return nil }
        self.surah = surah; self.spans = spans
    }
    func verse(at seconds: Double, duration: Double) -> String? {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration > 0,
              seconds < duration, let last = spans.last,
              Double(last[2]) <= duration * 1000 + 50 else { return nil }
        let milliseconds = seconds * 1000
        var low = 0, high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if Double(spans[middle][2]) <= milliseconds { low = middle + 1 }
            else { high = middle }
        }
        guard low < spans.count, Double(spans[low][1]) <= milliseconds else { return nil }
        return "\(surah):\(spans[low][0])"
    }
}

actor NoorSurahAyahTimings {
    static let shared = NoorSurahAyahTimings()
    static let digest = "cbd83bf75fd43a7e1d51306fa1484d7ef6600c4ee034b09ee07af243550229ff"
    static let coverageDigest = "eda4a4e62a53256436c1eca0bab45ee47700d224249942ef3e83cb0497dfb8b7"
    private struct CoverageRecord: Decodable, Sendable {
        let server: String
        let reciterID: Int
        let recordingID: Int
        let surahs: [Int]
    }
    private struct Coverage: Decodable {
        let schema: Int
        let dataSHA256: String
        let recordings: [CoverageRecord]
    }
    // The picker reads this small coverage index, never the full timing data
    // on the UI thread. Names alone cannot select another recording's times.
    private static let coverage: [CoverageRecord] = {
        guard let url = Bundle.main.url(forResource: "surah-ayah-timing-coverage", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == coverageDigest,
              let decoded = try? JSONDecoder().decode(Coverage.self, from: bytes),
              decoded.schema == 1, decoded.dataSHA256 == digest else { return [] }
        return decoded.recordings
    }()
    static func supports(_ reciter: NoorReciter) -> Bool {
        coverage.contains { $0.server == reciter.server && $0.reciterID == reciter.id
            && $0.recordingID == reciter.recordingID && !$0.surahs.isEmpty }
    }
    private struct Recording: Decodable {
        let readID: Int
        let reciterID: Int
        let recordingID: Int
        let surahs: [String: [[Int]]]
    }
    private struct Document: Decodable {
        let schema: Int
        let recordings: [String: Recording] // exact publisher folder URL
    }
    private var document: Document?
    private var attempted = false
    func track(reciter: NoorReciter, surah: Int, ayahCount: Int) -> NoorSurahAyahTimingTrack? {
        if !attempted {
            attempted = true
            if let url = Bundle.main.url(forResource: "surah-ayah-timings", withExtension: "json"),
               let bytes = try? Data(contentsOf: url),
               SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.digest,
               let decoded = try? JSONDecoder().decode(Document.self, from: bytes), decoded.schema == 1 {
                document = decoded
            }
        }
        guard let recording = document?.recordings[reciter.server],
              recording.reciterID == reciter.id, recording.recordingID == reciter.recordingID,
              let spans = recording.surahs[String(surah)] else { return nil }
        return NoorSurahAyahTimingTrack(surah: surah, ayahCount: ayahCount, spans: spans)
    }
}
