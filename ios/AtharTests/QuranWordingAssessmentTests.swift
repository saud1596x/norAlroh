import XCTest
@testable import Athar

final class QuranWordingAssessmentTests: XCTestCase {
    private let take = UUID()
    private let reference = ["قل", "هو", "الله", "أحد", "الله", "الصمد"].enumerated().map {
        QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
    }
    private func span(_ tokens: [String], offset: Double = 0, window: UUID = UUID(), takeID: UUID? = nil) -> QuranObservedSpeech {
        var value = QuranObservedSpeech(takeID: takeID ?? take, start: offset, end: offset + Double(tokens.count),
            words: tokens, unresolved: false, backendID: "test")
        value.evidenceVersion = 1; value.recognitionWindowID = window; value.recognitionRevision = 0
        value.wordObservations = tokens.enumerated().map {
            .init(occurrenceIndex: $0.offset, runIndex: 0, observedText: $0.element,
                startInTakeSeconds: offset + Double($0.offset), endInTakeSeconds: offset + Double($0.offset) + 0.8,
                backendConfidence: 0.95, recognitionState: "accepted", timingSource: "backend-word")
        }
        return value
    }
    func testCorrectSpeechAndSilenceDoNotGenerateMistakes() {
        XCTAssertTrue(QuranWordingAssessment.evaluate([span(["قل", "هو", "الله", "أحد", "الله", "الصمد"])], expected: reference).isEmpty)
        XCTAssertTrue(QuranWordingAssessment.evaluate([], expected: reference).isEmpty)
    }
    func testRecognizerRetractionPreservesPriorFindingAndIsNotSelfCorrection() throws {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let correct = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"])
        let initial = QuranWordingAssessment.evaluate([wrong], expected: reference)
        let revised = QuranWordingAssessment.reconcile(previous: initial,
            incoming: QuranWordingAssessment.evaluate([wrong, correct], expected: reference), reconsidered: [wrong, correct])
        XCTAssertEqual(revised.count, 1)
        XCTAssertEqual(revised.first?.state, "superseded")
        XCTAssertNil(revised.first?.resolution, "A changed interpretation of the same audio is not an acoustic correction")
        XCTAssertEqual(revised.first?.supportingObservationIDs, initial.first?.supportingObservationIDs)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        record.takes = [.init(id: take, startedAt: record.startedAt, frames: 320_000, closed: true)]
        record.observedSpeech = [wrong, correct]; record.wordingEvents = revised
        try record.validate()
        let decoded = try JSONDecoder().decode(QuranRecitationRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.wordingEvents, revised)
    }
    func testRealCorrectionCreatesRevisionAndRepeatedEvaluationIsIdempotent() {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let later = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"], offset: 10)
        let initial = QuranWordingAssessment.evaluate([wrong], expected: reference)
        let incoming = QuranWordingAssessment.evaluate([wrong, later], expected: reference)
        let revised = QuranWordingAssessment.reconcile(previous: initial, incoming: incoming, reconsidered: [wrong, later])
        XCTAssertEqual(revised.count, 2)
        XCTAssertEqual(revised.map(\.state), ["superseded", "provisional"])
        XCTAssertEqual(revised.map(\.revision), [0, 1])
        XCTAssertEqual(revised.last?.resolution, "later-independent-evidence")
        XCTAssertEqual(QuranWordingAssessment.reconcile(previous: revised, incoming: incoming,
            reconsidered: [wrong, later]), revised)
    }
    func testSubstitutionRetainsSpokenWordAndRequiresFollowingContext() {
        let source = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let events = QuranWordingAssessment.evaluate([source], expected: reference)
        XCTAssertEqual(events.map(\.category), ["substitution"])
        XCTAssertEqual(events.first?.referenceIDs, [3])
        XCTAssertEqual(events.first?.supportingObservationIDs, [source.wordObservations![2].observationID])
        XCTAssertEqual(events.first?.state, "provisional", "Uncalibrated acoustic evidence must never become a confirmed learner mistake")
        XCTAssertTrue(QuranWordingAssessment.evaluate([span(["قل", "هو", "شيء"])], expected: reference).isEmpty)
    }
    func testAssistedRetryUsesNewTakeAndNeverBecomesIndependentRecall() {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let secondID = UUID()
        let later = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"], takeID: secondID)
        let start = Date()
        let first = QuranRecitationTake(id: take, startedAt: start, frames: 160_000, closed: true)
        var assisted = QuranRecitationTake(id: secondID, startedAt: start.addingTimeInterval(20), frames: 160_000, closed: true)
        assisted.referenceExposure = "Abdul_Basit_Murattal_64kbps"
        let initial = QuranWordingAssessment.evaluate([wrong], expected: reference)
        let linked = QuranWordingAssessment.linkLaterAttempts(initial, spans: [later], takes: [first, assisted], expected: reference)
        XCTAssertEqual(linked.first?.resolution, "later-assisted-evidence")
        XCTAssertEqual(linked.first?.state, "provisional")
        var textAssisted = assisted
        textAssisted.referenceExposure = nil; textAssisted.textHintIDs = [3]
        XCTAssertEqual(QuranWordingAssessment.linkLaterAttempts(initial, spans: [later], takes: [first, textAssisted],
            expected: reference).first?.resolution, "later-assisted-evidence")
        textAssisted.textHintIDs = nil; textAssisted.textExposureOccurred = true
        XCTAssertEqual(QuranWordingAssessment.linkLaterAttempts(initial, spans: [later], takes: [first, textAssisted],
            expected: reference).first?.resolution, "later-assisted-evidence",
            "Reading exposed during a capture failure cannot become independent recall")
        XCTAssertTrue(Set(linked.first?.correctionObservationIDs ?? []).isSubset(of: Set(later.wordObservations!.map(\.observationID))))
        let stored = QuranWordingAssessment.reconcile(previous: initial, incoming: linked, reconsidered: [later])
        XCTAssertEqual(stored.filter { $0.state == "provisional" }.first?.resolution, "later-assisted-evidence")
        XCTAssertEqual(stored.filter { $0.state == "superseded" }.count, 1)
        XCTAssertNil(QuranWordingAssessment.linkLaterAttempts(initial, spans: [later], takes: [first], expected: reference).first?.resolution,
                     "A playback-only source with no learner microphone take cannot resolve an incident")
        let conflicting = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"], offset: 0.1, takeID: secondID)
        XCTAssertNil(QuranWordingAssessment.linkLaterAttempts(initial, spans: [later, conflicting], takes: [first, assisted], expected: reference).first?.resolution)
    }
    func testOmissionRequiresLaterSpeechAndUnclearAudioAbstains() {
        let source = span(["قل", "هو", "أحد", "الله", "الصمد"])
        XCTAssertEqual(QuranWordingAssessment.evaluate([source], expected: reference).map(\.category), ["omission"])
        var unclear = source; unclear = QuranObservedSpeech(takeID: take, start: 0, end: 5,
            words: unclear.words, unresolved: true, backendID: "test")
        XCTAssertTrue(QuranWordingAssessment.evaluate([unclear], expected: reference).isEmpty)
    }
    func testSameAudioReplacementIsNotSelfCorrectionAndLaterAttemptIsLinked() {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let correctedSameAudio = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"])
        XCTAssertTrue(QuranWordingAssessment.evaluate([wrong, correctedSameAudio], expected: reference).isEmpty)
        let later = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"], offset: 10)
        let events = QuranWordingAssessment.evaluate([wrong, later], expected: reference)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.resolution, "later-independent-evidence")
        XCTAssertNotNil(events.first?.correctionObservationIDs)
    }
    func testAdditionalSpeechIsPreservedAsProvisionalInsertion() {
        let source = span(["قل", "هو", "الله", "شيء", "أحد", "الله", "الصمد"])
        XCTAssertEqual(QuranWordingAssessment.evaluate([source], expected: reference).map(\.category), ["insertion"])
        XCTAssertEqual(source.wordObservations?[3].observedText, "شيء")
    }
    func testSwappedWordsRetainBothAcousticOccurrencesAndCanonicalTargets() {
        let source = span(["قل", "هو", "أحد", "الله", "الله", "الصمد"])
        let events = QuranWordingAssessment.evaluate([source], expected: reference)
        XCTAssertEqual(events.map(\.category), ["transposition"])
        XCTAssertEqual(events.first?.referenceIDs, [3, 4])
        XCTAssertEqual(events.first?.supportingObservationIDs,
                       source.wordObservations?[2...3].map(\.observationID))
        XCTAssertEqual(events.first?.state, "provisional")
        XCTAssertEqual(source.words, ["قل", "هو", "أحد", "الله", "الله", "الصمد"])
    }
    func testSkippedPassageNeedsBothAnchorsAndPartialRetryCannotResolveIt() {
        let tokens = ["قل", "هو", "الله", "أحد", "الله", "الصمد", "لم", "يلد", "ولم", "يولد"]
        let longer = tokens.enumerated().map {
            QuranAlignedWord(id: $0.offset + 1, verse: "112:1", page: 604, aliases: [[$0.element]])
        }
        let skipped = span(["قل", "هو", "لم", "يلد"])
        let initial = QuranWordingAssessment.evaluate([skipped], expected: longer)
        XCTAssertEqual(initial.map(\.category), ["skipped-passage"])
        XCTAssertEqual(initial.first?.referenceIDs, [3, 4, 5, 6])
        let partial = span(Array(tokens.prefix(6)), offset: 10)
        XCTAssertNil(QuranWordingAssessment.evaluate([skipped, partial], expected: longer).first?.resolution)
        let full = span(tokens, offset: 10)
        XCTAssertEqual(QuranWordingAssessment.evaluate([skipped, full], expected: longer).first?.resolution,
                       "later-independent-evidence")
        XCTAssertTrue(QuranWordingAssessment.evaluate([span(["قل", "هو"])], expected: longer).isEmpty,
                      "A stopped or silent attempt cannot establish a skipped passage")
    }
    func testRepeatedWordInLaterUnrelatedContextDoesNotResolveIncident() {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let fragment = span(["الله", "أحد", "الله", "الصمد"], offset: 10)
        XCTAssertNil(QuranWordingAssessment.evaluate([wrong, fragment], expected: reference).first?.resolution)
    }
    func testConflictingOverlappingWindowsAbstainInsteadOfInventingSelfCorrection() {
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let revised = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"], offset: 0.1)
        XCTAssertTrue(QuranWordingAssessment.evaluate([wrong, revised], expected: reference).isEmpty)
    }
    func testAssessmentAndCorrectionSurviveReopeningWithoutDuplicateEvents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrong = span(["قل", "هو", "شيء", "أحد", "الله", "الصمد"])
        let later = span(["قل", "هو", "الله", "أحد", "الله", "الصمد"], offset: 10)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        record.takes = [.init(id: take, startedAt: record.startedAt, frames: 320_000, closed: true)]
        record.observedSpeech = [wrong, later]
        record.wordingEvents = QuranWordingAssessment.evaluate([wrong, wrong, later], expected: reference)
        XCTAssertEqual(record.wordingEvents?.count, 1)
        let journal = QuranRecitationJournal(root: root)
        try journal.create(record)
        let loaded = try journal.load(record.id)
        XCTAssertEqual(loaded.wordingEvents, record.wordingEvents)
        XCTAssertEqual(loaded.wordingEvents?.first?.resolution, "later-independent-evidence")
        var missingSource = record
        missingSource.observedSpeech = []
        XCTAssertThrowsError(try missingSource.validate(), "A finding cannot survive without its actual source observations")
        var forgedCorrection = record
        forgedCorrection.wordingEvents?[0].correctionObservationIDs = [UUID()]
        XCTAssertThrowsError(try forgedCorrection.validate(), "Correction links must point to recorded observations")
    }
}
