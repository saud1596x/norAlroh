import AudioToolbox
import Combine
import Foundation
import UIKit

@MainActor protocol NoorMicrophoneCueDriver: AnyObject {
    func prepare() -> Bool
    func play(completion: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

/// UI feedback only. This file is never a recognition fixture or learner audio.
@MainActor final class NoorSystemMicrophoneCue: NoorMicrophoneCueDriver {
    private var sound: SystemSoundID = 0
    func prepare() -> Bool {
        cancel()
        guard let url = Bundle.main.url(forResource: "mic-start", withExtension: "wav") else { return false }
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == kAudioServicesNoError, sound != 0 else {
            cancel(); return false
        }
        return true
    }
    func play(completion: @escaping @MainActor @Sendable () -> Void) {
        AudioServicesPlaySystemSoundWithCompletion(sound) {
            Task { @MainActor in completion() }
        }
    }
    func cancel() {
        if sound != 0 { AudioServicesDisposeSystemSoundID(sound); sound = 0 }
    }
}

/// Capture may start only after the real cue completion and an acoustic tail.
/// A missing file starts quietly; a queued sound that never completes fails
/// closed. Cancelling/leaving the reader invalidates every late callback.
@MainActor final class NoorMicrophoneCue: ObservableObject {
    @Published private(set) var pending = false
    @Published private(set) var error: String?
    private let driver: NoorMicrophoneCueDriver
    private let haptics: Bool
    private let deadlineNanoseconds: UInt64
    private var request: UUID?
    private var ready: (() -> Void)?
    private var deadline: Task<Void, Never>?
    private var clearance: Task<Void, Never>?

    init(driver: NoorMicrophoneCueDriver? = nil, haptics: Bool = true,
         deadlineNanoseconds: UInt64 = 1_000_000_000) {
        self.driver = driver ?? NoorSystemMicrophoneCue()
        self.haptics = haptics; self.deadlineNanoseconds = deadlineNanoseconds
    }
    func begin(ready: @escaping () -> Void) {
        guard !pending else { return }
        error = nil
        if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65) }
        guard driver.prepare() else { ready(); return }
        let token = UUID(); request = token; pending = true; self.ready = ready
        driver.play { [weak self] in self?.finished(token) }
        deadline = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.deadlineNanoseconds)
            guard !Task.isCancelled, self.request == token else { return }
            self.cancel()
            self.error = "تعذّر صوت البدء. اضغط الميكروفون للمحاولة مجددًا."
        }
    }
    private func finished(_ token: UUID) {
        guard request == token else { return }
        deadline?.cancel(); deadline = nil; driver.cancel()
        clearance = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self, !Task.isCancelled, self.request == token else { return }
            let action = self.ready
            self.ready = nil; self.request = nil; self.pending = false; self.clearance = nil
            action?()
        }
    }
    func cancel() {
        request = nil; ready = nil; pending = false
        deadline?.cancel(); deadline = nil; clearance?.cancel(); clearance = nil
        driver.cancel()
    }
}
