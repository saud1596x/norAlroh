import Foundation

/// Network event ordering cannot mutate a reading position before the source
/// model/edition and contiguous event sequence have been validated. The local
/// tracker remains responsible for binding source words to native display IDs.
struct QuranRemoteEventReducer {
    struct Event: Decodable, Sendable {
        let schema_version: Int
        let event_id: Int
        let type: String
        let session_id: String
        let audio_sequence: Int
        let audio_start_frame: Int64
        let audio_end_frame: Int64
        let engine_version: String
        let model_id: String
        let model_revision: String
        let corpus_version: String
    }
    private(set) var lastEventID = 0
    mutating func consume(_ events: [Event], session: String, sequence: Int,
                          startFrame: Int64, endFrame: Int64) throws {
        var next = lastEventID
        let types: Set<String> = ["AUDIO_ACCEPTED", "PARTIAL_RECOGNITION", "WORD_CONFIRMED",
            "VERSE_LOCATION_CHANGED", "ERROR_CANDIDATE", "ERROR_RETRACTED", "SESSION_INTERRUPTED"]
        guard !events.isEmpty else { throw QuranRemoteRecognitionFailure.invalidResponse }
        for event in events {
            guard event.schema_version == 1, event.session_id == session,
                  event.audio_sequence == sequence, event.audio_start_frame == startFrame,
                  event.audio_end_frame == endFrame, event.engine_version == "noor-session-1",
                  event.model_id == "OdyAsh/faster-whisper-base-ar-quran",
                  event.model_revision == "8578bafd427d122f671b187706650e76edf6f86f",
                  event.corpus_version == "1968cf3a4e8338ae2056b5fba309099d2f7645b1609062cc1a52eac1804c5951",
                  types.contains(event.type), event.event_id == next + 1 else {
                throw QuranRemoteRecognitionFailure.invalidResponse
            }
            next = event.event_id
        }
        guard events.first?.type == "AUDIO_ACCEPTED" else { throw QuranRemoteRecognitionFailure.invalidResponse }
        lastEventID = next
    }
}
