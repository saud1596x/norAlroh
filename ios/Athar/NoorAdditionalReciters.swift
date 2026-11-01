import Foundation
import CryptoKit

/// Noor-internal recording IDs, deliberately outside provider ID namespaces.
/// Each identity owns one exact source recording and its published clocks.
enum NoorAdditionalReciters {
    static let catalogDigest = "7bd7f9b0f27f111458d240c41308cbf8996420f794c95f07c3467aaa93b34392"
    static let timingDigest = "69317b4f3c27a38a60a312d535419e2193a1e7bd71f0e87b24a895d078b2903c"
    static let bases: [Int: String] = [
        1000001: "https://cdn.mp3quran.net/audio/mishary-alafasy/r1/",
        1000002: "https://download.quranicaudio.com/quran/maher_almu3aiqly/year1440/",
        1000003: "https://cdn.mp3quran.net/audio/mahmoud-husary/r1/"]
    static func matches(_ reciter: NoorReciter) -> Bool {
        reciter.recordingID == reciter.id && bases[reciter.id] == reciter.server &&
        reciter.surahs.count == 114 && Set(reciter.surahs) == Set(1...114)
    }
    private struct Document: Decodable {
        let schema: Int
        let namespace: String
        let reciters: [NoorReciter]
    }
    static let reciters: [NoorReciter] = {
        guard let url = Bundle.main.url(forResource: "additional-reciters", withExtension: "json"),
              let bytes = try? Data(contentsOf: url), bytes.count < 32_000,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == catalogDigest,
              let document = try? JSONDecoder().decode(Document.self, from: bytes), document.schema == 1,
              document.namespace == "NOOR_INTERNAL_RECORDING_IDS_NOT_PROVIDER_IDS",
              document.reciters.count == bases.count, Set(document.reciters.map(\.id)) == Set(bases.keys),
              document.reciters.allSatisfy({ !$0.name.isEmpty && matches($0) }) else { return [] }
        return document.reciters
    }()
}
