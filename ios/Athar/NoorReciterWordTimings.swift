import Foundation
import CryptoKit

/// Playback guidance only. These published times are never user-recitation
/// evidence, memorization credit, or a pronunciation assessment.
struct NoorReciterTimingTrack: Sendable {
    let spans: [[Int]] // native word ID, inclusive start ms, exclusive end ms
    init?(_ spans: [[Int]]) {
        guard !spans.isEmpty, spans.allSatisfy({ $0.count == 3 && $0[0] > 0 && $0[1] >= 0 && $0[2] > $0[1] }),
              zip(spans, spans.dropFirst()).allSatisfy({ $0.0[2] <= $0.1[1] }) else { return nil }
        self.spans = spans
    }
    func word(at seconds: Double, duration: Double) -> Int? {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration > 0,
              seconds < duration, let last = spans.last, Double(last[2]) <= duration * 1000 + 50 else { return nil }
        let milliseconds = seconds * 1000
        var low = 0, high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if Double(spans[middle][2]) <= milliseconds { low = middle + 1 }
            else { high = middle }
        }
        guard low < spans.count, Double(spans[low][1]) <= milliseconds else { return nil }
        return spans[low][0]
    }
}

actor NoorReciterWordTimings {
    static let shared = NoorReciterWordTimings()
    static let timedDirectories: Set<String> = [
        "Abdul_Basit_Murattal_64kbps", "Abdurrahmaan_As-Sudais_192kbps", "Saood_ash-Shuraym_128kbps"
    ]
    private struct Document: Decodable {
        let schema: Int
        let recordings: [String: [String: [[Int]]]]
    }
    private var document: Document?
    private var attempted = false
    static let digest = "c3364cd2f2f76de78274e24d6b7b4e0ce8a74f7c5f8dd64fad9cad6826d2eb9d"
    func track(directory: String, verse: String) -> NoorReciterTimingTrack? {
        if !attempted {
            attempted = true
            if let url = Bundle.main.url(forResource: "reciter-word-timings", withExtension: "json"),
               let bytes = try? Data(contentsOf: url),
               SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.digest,
               let decoded = try? JSONDecoder().decode(Document.self, from: bytes), decoded.schema == 1 {
                document = decoded
            }
        }
        guard let spans = document?.recordings[directory]?[verse] else { return nil }
        return NoorReciterTimingTrack(spans)
    }
}
