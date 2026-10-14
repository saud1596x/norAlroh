import SwiftUI

@MainActor struct NoorAudioMiniPlayer: View {
    @ObservedObject private var focus = NoorAudioFocus.shared
    var body: some View {
        if let audio = focus.activePlayer { NoorAudioMiniPlayerControls(audio: audio) }
    }
}
@MainActor private struct NoorAudioMiniPlayerControls: View {
    @ObservedObject var audio: MushafVerseAudio
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2").foregroundStyle(Theme.gold).accessibilityHidden(true)
            Text(audio.displayName).font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if audio.isPaused { audio.resumePlayback() } else { audio.pausePlayback() }
            } label: {
                Image(systemName: audio.isPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(audio.isPaused ? "استئناف التلاوة" : "إيقاف التلاوة مؤقتًا")
            Button { audio.stop() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("إيقاف التلاوة")
        }.padding(.horizontal, 16).background(Theme.panel)
    }
}
