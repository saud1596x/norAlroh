import Foundation

/// All state changes are serialized with the UI. Recording owns the audio
/// route until its capture has closed, including final recognition draining.
@MainActor final class NoorAudioFocus {
    static let shared = NoorAudioFocus()
    private var recording: UUID?
    private var players: [UUID: () -> Void] = [:]
    func register(_ id: UUID, stop: @escaping () -> Void) { players[id] = stop }
    func unregister(_ id: UUID) { players.removeValue(forKey: id) }
    func acquireRecording(_ id: UUID) -> Bool {
        guard recording == nil || recording == id else { return false }
        recording = id
        for stop in Array(players.values) { stop() }
        return true
    }
    func releaseRecording(_ id: UUID) {
        if recording == id { recording = nil }
    }
    func preparePlayback(_ id: UUID) -> Bool {
        guard recording == nil else { return false }
        for (other, stop) in Array(players) where other != id { stop() }
        return true
    }
}
