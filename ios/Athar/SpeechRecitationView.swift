import SwiftUI

/// Every former voice-recitation entry now opens the actual Mushaf controls.
struct SpeechRecitationView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var memorization: MemorizationStore
    @EnvironmentObject private var speech: LegacySpeechArchive
    private var position: (chapter: Int, ayah: Int) {
        speech.readerPosition(corpus: store.quran, plan: memorization.plan, pending: memorization.mushafStudy.pending)
    }
    var body: some View {
        MushafReader(chapter: position.chapter, ayah: position.ayah, startsStudy: true)
    }
}
