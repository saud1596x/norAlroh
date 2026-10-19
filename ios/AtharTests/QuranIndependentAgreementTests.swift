import XCTest
import WhisperKit
import CryptoKit
@testable import Athar

final class QuranIndependentAgreementTests: XCTestCase {
    private func primary(_ text:String,_ start:Double,_ end:Double) -> QuranHeardWord {
        .init(text:text,start:start,end:end,probability:0.99)
    }
    private func ctc(_ text:String,_ start:Double,_ end:Double) -> QuranIndependentWord {
        .init(text:text,start:start,end:end,meanPosterior:0.9)
    }
    func testIndependentPrefixDisagreementCannotCompleteMemorizedOpeningOrBridgeWords() throws {
        let heard=[primary("الحمد",0.1,0.4),primary("لله",0.5,0.8),primary("رب",0.9,1.2)]
        let actual=try QuranIndependentAgreement.evaluate([heard],independent:[ctc("الحمد",0.12,0.38),ctc("لن",0.52,0.78)],duration:2)
        XCTAssertEqual(actual.runs.map{$0.map(\.text)},[["الحمد"]])
        XCTAssertEqual(actual.disagreements,2)
        let opening=try QuranIndependentAgreement.evaluate([[primary("الم",0.1,1.8)]],
            independent:[ctc("ال",0.12,1.7)],duration:2)
        XCTAssertTrue(opening.runs.isEmpty)
        XCTAssertEqual(opening.disagreements,1)
    }
    func testRepetitionNeedsUniqueContemporaneousOccurrencesAndCannotUseAnotherTakeTime() throws {
        let first=primary("الله",0.1,0.8),second=primary("الله",1.1,1.8)
        let exact=try QuranIndependentAgreement.evaluate([[first,second]],
            independent:[ctc("الله",0.12,0.7),ctc("الله",1.2,1.7)],duration:2)
        XCTAssertEqual(exact.runs.flatMap{$0}.count,2)
        let broad=try QuranIndependentAgreement.evaluate([[first,second]],independent:[ctc("الله",0,1.9)],duration:2)
        XCTAssertTrue(broad.runs.isEmpty,"One broad independent occurrence cannot verify two primary repetitions")
        let delayed=try QuranIndependentAgreement.evaluate([[first]],independent:[ctc("الله",1.1,1.8)],duration:2)
        XCTAssertTrue(delayed.runs.isEmpty,"Text agreement without actual source-time overlap is insufficient")
    }
    func testRejectedMiddleHypothesisSplitsAcousticRunAndKeepsOriginalTextAndClock() throws {
        let original=[primary("قل",0.1,0.3),primary("هو",0.4,0.6),primary("الله",0.7,1)]
        let result=try QuranIndependentAgreement.evaluate([original],independent:[ctc("قل",0.1,0.3),ctc("الله",0.7,1)],duration:2)
        XCTAssertEqual(result.runs.map{$0.map(\.text)},[["قل"],["الله"]])
        XCTAssertEqual(result.runs[1][0].start,original[2].start)
        XCTAssertEqual(result.runs[1][0].probability,original[2].probability)
        XCTAssertThrowsError(try QuranIndependentAgreement.evaluate([original],independent:[ctc("قل",0,3)],duration:2))
    }
    func testIndependentObservationRejectsOverflowAndDifferentSourceClock() {
        let observation=QuranIndependentObservation(modelRevision:QuranIndependentCTC.revision,
            configuration:QuranIndependentCTC.configuration,sourceSHA256:String(repeating:"a",count:64),
            startFrame:0,endFrame:32000,words:[ctc("ال",0.1,1.9)])
        XCTAssertTrue(observation.valid(start:0,end:2))
        XCTAssertFalse(observation.valid(start:1,end:3))
        let overflow=QuranIndependentObservation(modelRevision:observation.modelRevision,configuration:observation.configuration,
            sourceSHA256:observation.sourceSHA256,startFrame:Int64.min,endFrame:Int64.max,words:[])
        XCTAssertFalse(overflow.valid(start:0,end:2))
    }
    func testIndependentOnlyWordCannotBeSilentlyBridgedByPrimarySequence() throws {
        let heard=[primary("قل",0.1,0.3),primary("هو",0.7,0.9),primary("الله",1,1.3)]
        let result=try QuranIndependentAgreement.evaluate([heard],independent:[ctc("قل",0.1,0.3),
            ctc("غريب",0.4,0.6),ctc("هو",0.7,0.9),ctc("الله",1,1.3)],duration:2)
        XCTAssertTrue(result.hasIndependentOnlyWords)
        XCTAssertEqual(result.runs.map{$0.map(\.text)},[["قل"],["هو","الله"]])
        XCTAssertEqual(result.runs.flatMap{$0}.count,3,"Existing primary words remain genuine; no extra word is invented")
    }
    func testActualBundledIndependentModelKeepsPublicPrefixSeparateFromWholeOpening() async throws {
        let file=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"002001",withExtension:"mp3"))
        let pcm=try AudioProcessor.loadAudioAsFloatArray(fromPath:file.path)
        let prefix=Array(pcm.prefix(32000))
        let partial=try await QuranIndependentCTC.shared.recognize(.init(samples:prefix,startFrame:16000,endFrame:48000))
        XCTAssertEqual(partial.words.map(\.text),["ال"],"No expected-text prompt may complete the unheard letter")
        XCTAssertTrue(partial.valid(start:1,end:3))
        let source=prefix.withUnsafeBufferPointer{SHA256.hash(data:Data(buffer:$0)).map{String(format:"%02x",$0)}.joined()}
        XCTAssertEqual(partial.sourceSHA256,source)
        let full=try await QuranIndependentCTC.shared.recognize(.init(samples:pcm,startFrame:0,endFrame:Int64(pcm.count)))
        XCTAssertEqual(full.words.map(\.text),["الم"])
        XCTAssertTrue(full.valid(start:0,end:Double(pcm.count)/16000))
        XCTAssertEqual(full.configuration,QuranIndependentCTC.configuration)
        print("NOOR_ACTUAL_NATIVE_CTC publicPrefixFrames=32000 fullFrames=\(pcm.count) noExpectedText=true")
    }
    func testActualConcurrentPreparationSharesOneModelAndPreservesRawPrefixEvidence() async throws {
        // Reuse the production worker instead of retaining two large acoustic
        // models in one test host. This exercises concurrent calls; whether
        // this invocation is cold is recorded by the model-stage trace.
        // Original public PCM checks parity, not natural-learner accuracy.
        let worker = QuranIndependentCTC.shared
        async let first: Void = worker.prepare()
        async let second: Void = worker.prepare()
        async let third: Void = worker.prepare()
        _ = try await (first, second, third)
        let attempts = await worker.modelLoadAttempts
        XCTAssertEqual(attempts, 1, "Concurrent takes must share one Core ML load")
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "002001", withExtension: "mp3"))
        let pcm = try AudioProcessor.loadAudioAsFloatArray(fromPath: file.path)
        let prefix = Array(pcm.prefix(32_000))
        let window = QuranAudioWindow(samples: prefix, startFrame: 16_000, endFrame: 48_000)
        let actual = try await worker.recognize(window)
        XCTAssertEqual(actual.words.map(\.text), ["ال"], "Loading cannot complete unheard Quran initials")
        let source = prefix.withUnsafeBufferPointer {
            SHA256.hash(data: Data(buffer: $0)).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(actual.sourceSHA256, source)
        XCTAssertEqual(actual.startFrame, window.startFrame); XCTAssertEqual(actual.endFrame, window.endFrame)
        XCTAssertEqual(actual.configuration, QuranIndependentCTC.configuration)
        XCTAssertTrue(actual.valid(start: 1, end: 3))
        let finalAttempts = await worker.modelLoadAttempts
        XCTAssertEqual(finalAttempts, 1, "Ready inference must reuse the verified loaded model")
    }
}
