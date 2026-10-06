import XCTest
@testable import Athar

final class RecitationComparisonTests: XCTestCase {
    func testExactPartialAndDifferentWordsAreDistinct() throws {
        let chapter = try XCTUnwrap(QuranResources.corpus?[111])
        let words = RecitationComparison.words(chapter: chapter, from: 1, to: 4)
        let exact = RecitationComparison.align(expected: words, heard: "قل هو الله أحد")
        XCTAssertTrue(exact.reliableAlignment)
        XCTAssertEqual(exact.endIndex, 4)
        XCTAssertTrue(exact.possibleDifferences.isEmpty, "An unspoken suffix is not a missing verse.")
        let difference = RecitationComparison.align(expected: words, heard: "قل هو الله واحد")
        XCTAssertTrue(difference.reliableAlignment)
        XCTAssertEqual(difference.possibleDifferences.first?.wordIndex, 3)
        let skippedBeginning = RecitationComparison.align(expected: words, heard: "هو الله أحد")
        XCTAssertTrue(skippedBeginning.reliableAlignment)
        XCTAssertEqual(skippedBeginning.possibleDifferences.first?.wordIndex, 0)
        XCTAssertNil(skippedBeginning.possibleDifferences.first?.heard)
        let continuing = RecitationComparison.align(expected: words, heard: "الله الصمد لم يلد", anchor: 4)
        XCTAssertTrue(continuing.reliableAlignment)
        XCTAssertTrue(continuing.possibleDifferences.isEmpty)
        XCTAssertEqual(continuing.endIndex, 8)
        XCTAssertFalse(RecitationComparison.align(expected: words, heard: "مرحبا كيف حالك").reliableAlignment)
        XCTAssertFalse(RecitationComparison.align(expected: words, heard: "قل هو").reliableAlignment)
    }
    func testAudioBufferIsBoundedAndCannotReceiveAfterErase() {
        let buffer = RecitationAudioBuffer()
        buffer.append(Array(repeating: 0.1, count: 40 * 16000))
        XCTAssertEqual(buffer.snapshot().count, 30 * 16000)
        buffer.erase(); buffer.append([1, 2, 3])
        XCTAssertTrue(buffer.snapshot().isEmpty)
    }
    func testIncrementalWindowsReuseOnlyShortOverlapAndDoNotReplayWithoutNewAudio() throws {
        let buffer = RecitationAudioBuffer()
        buffer.append((0..<80000).map(Float.init))
        let first = try XCTUnwrap(buffer.nextWindow())
        XCTAssertEqual(first.start, 0); XCTAssertEqual(first.end, 80000)
        buffer.consume(through: first.end)
        XCTAssertNil(buffer.nextWindow())
        buffer.append((80000..<128000).map(Float.init))
        let next = try XCTUnwrap(buffer.nextWindow())
        XCTAssertEqual(next.start, 48000)
        XCTAssertEqual(next.end, 128000)
        XCTAssertEqual(next.samples.first, 48000)
        XCTAssertEqual(next.samples.last, 127999)
        buffer.consume(through: next.end)
        XCTAssertNil(buffer.nextWindow(minimumNewSamples: 16000))
    }
    func testSlowDecoderReportsEvictionInsteadOfSilentlySkippingAudio() throws {
        let buffer = RecitationAudioBuffer()
        buffer.append(Array(repeating: 0.1, count: 40 * 16000))
        let window = try XCTUnwrap(buffer.nextWindow())
        XCTAssertEqual(window.lostSamples, 10 * 16000)
        XCTAssertLessThanOrEqual(window.samples.count, 12 * 16000)
    }
    func testRepeatedVerseCanMoveFollowPositionBackwards() throws {
        let chapter = try XCTUnwrap(QuranResources.corpus?[111])
        let words = RecitationComparison.words(chapter: chapter, from: 1, to: 4)
        let repeated = RecitationComparison.align(expected: words, heard: "قل هو الله أحد", anchor: 10)
        XCTAssertTrue(repeated.reliableAlignment)
        XCTAssertEqual(repeated.endIndex, 4)
        XCTAssertTrue(repeated.possibleDifferences.isEmpty)
    }
    func testUthmaniComparisonAnnotationsDoNotAlterDisplayedText() throws {
        XCTAssertEqual(RecitationComparison.normalize("مَالَهُۥ"), "ماله")
        XCTAssertEqual(RecitationComparison.normalize("بِهِۦ"), "به")
        let chapter = try XCTUnwrap(QuranResources.corpus?.first)
        let words = RecitationComparison.words(chapter: chapter, from: 2, to: 2)
        let ordinaryArabic = RecitationComparison.align(expected: words, heard: "الحمد لله رب العالمين")
        XCTAssertTrue(ordinaryArabic.reliableAlignment)
        XCTAssertTrue(ordinaryArabic.possibleDifferences.isEmpty)
        XCTAssertEqual(words.map(\.text).joined(separator: " "), chapter.ayahs[1].text)
    }
}
