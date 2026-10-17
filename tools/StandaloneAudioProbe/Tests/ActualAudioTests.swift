import XCTest
import AVFoundation

// These real media controls isolate the test host; they do not validate Noor,
// speech recognition or capture, and do not replace any app release assertion.
final class ActualAudioTests: XCTestCase {
    @MainActor func testAVAudioPlayerReachesActualEnd() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)
        let ended = expectation(description: "Actual AVAudioPlayer delegate end")
        let delegate = EndDelegate(ended)
        let player = try AVAudioPlayer(contentsOf: file)
        player.delegate = delegate
        defer { player.stop(); player.delegate = nil }
        NSLog("ISOLATED_AUDIO avaudio.play.begin")
        XCTAssertTrue(player.play())
        NSLog("ISOLATED_AUDIO avaudio.play.return")
        await fulfillment(of: [ended], timeout: 10)
        withExtendedLifetime(delegate) {}
    }
    @MainActor func testAVPlayerReachesActualEnd() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "112001", withExtension: "mp3"))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)
        let item = AVPlayerItem(url: file)
        let player = AVPlayer(playerItem: item)
        let ended = expectation(description: "Actual AVPlayer item end")
        let observation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { _ in ended.fulfill() }
        defer { NotificationCenter.default.removeObserver(observation); player.pause() }
        NSLog("ISOLATED_AUDIO avplayer.play.begin")
        player.play()
        NSLog("ISOLATED_AUDIO avplayer.play.return")
        await fulfillment(of: [ended], timeout: 10)
        NSLog("ISOLATED_AUDIO item=%ld player=%ld", item.status.rawValue, player.status.rawValue)
    }
    private final class EndDelegate: NSObject, AVAudioPlayerDelegate {
        let ended: XCTestExpectation
        init(_ ended: XCTestExpectation) { self.ended = ended }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            XCTAssertTrue(flag)
            NSLog("ISOLATED_AUDIO avaudio.actual-end success=%d", flag)
            ended.fulfill()
        }
    }
}
