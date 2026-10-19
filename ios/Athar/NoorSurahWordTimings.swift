import Foundation
import CryptoKit

/// Source-recording playback guidance only. Never learner evidence or credit.
struct NoorSurahWordTimingTrack: Sendable {
    struct Position: Equatable, Sendable {
        let verse: String
        let wordID: Int
    }
    let surah: Int
    let spans: [[Int]] // ayah, native word ID, inclusive start ms, exclusive end
    init?(surah: Int, ayahCount: Int, spans: [[Int]]) {
        guard (1...114).contains(surah), ayahCount > 0, !spans.isEmpty,
              spans.allSatisfy({ $0.count == 4 && (1...ayahCount).contains($0[0]) && $0[1] > 0
                  && $0[2] >= 0 && $0[3] > $0[2] && $0[3] <= 21_600_000 }),
              zip(spans, spans.dropFirst()).allSatisfy({ $0.0[3] <= $0.1[2] }) else { return nil }
        var verses: [Int: Int] = [:]
        for span in spans {
            if let previous = verses[span[1]], previous != span[0] { return nil }
            verses[span[1]] = span[0]
        }
        self.surah = surah; self.spans = spans
    }
    func position(at seconds: Double, duration: Double) -> Position? {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration > 0,
              seconds < duration, let last = spans.last, Double(last[3]) <= duration * 1000 + 50 else { return nil }
        let milliseconds = seconds * 1000
        var low = 0, high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if Double(spans[middle][3]) <= milliseconds { low = middle + 1 }
            else { high = middle }
        }
        guard low < spans.count, Double(spans[low][2]) <= milliseconds else { return nil }
        return Position(verse: "\(surah):\(spans[low][0])", wordID: spans[low][1])
    }
}

actor NoorSurahWordTimings {
    static let shared = NoorSurahWordTimings()
    static func supports(_ reciter: NoorReciter) -> Bool {
        switch (reciter.id, reciter.recordingID, reciter.server) {
        case (74, 74, "https://cdn.mp3quran.net/audio/ali-hudhaifi/r1/"),
             (31, 31, "https://cdn.mp3quran.net/audio/saud-shuraim/r1/"): return true
        default: return false
        }
    }
    static let digest = "60fa8fe85296ba685ca273e1c19f24a0d4b3c9838ecd20f5ece340c700d72cfe"
    private struct Recording: Decodable {
        let reciterID: Int
        let recordingID: Int
        let surahs: [String: [[Int]]]
    }
    private struct Document: Decodable {
        let schema: Int
        let nativeSnapshotSHA256: String
        let recordings: [String: Recording]
    }
    private var document: Document?
    private var attempted = false
    func track(reciter: NoorReciter, surah: Int, ayahCount: Int) -> NoorSurahWordTimingTrack? {
        guard Self.supports(reciter) else { return nil }
        if !attempted {
            attempted = true
            if let url = Bundle.main.url(forResource: "surah-word-timings", withExtension: "json"),
               let bytes = try? Data(contentsOf: url),
               SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.digest,
               let decoded = try? JSONDecoder().decode(Document.self, from: bytes), decoded.schema == 1,
               decoded.nativeSnapshotSHA256 == "37544d69f3615fa2040be516eb2ba57c62fa25741332e3ba67f31f2a6df292d1" {
                document = decoded
            }
        }
        guard let recording = document?.recordings[reciter.server], recording.reciterID == reciter.id,
              recording.recordingID == reciter.recordingID, let spans = recording.surahs[String(surah)] else { return nil }
        return NoorSurahWordTimingTrack(surah: surah, ayahCount: ayahCount, spans: spans)
    }
}
