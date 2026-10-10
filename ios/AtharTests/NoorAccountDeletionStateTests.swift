import XCTest
@testable import Athar

final class NoorAccountDeletionStateTests: XCTestCase {
    func testEveryPendingDeletionPhaseBlocksCloudDataActions() {
        XCTAssertTrue(NoorAccountDeletionState.permitsCloudDataActions(deletionRequested: false, needsCompletion: false))
        XCTAssertFalse(NoorAccountDeletionState.permitsCloudDataActions(deletionRequested: true, needsCompletion: false))
        XCTAssertFalse(NoorAccountDeletionState.permitsCloudDataActions(deletionRequested: false, needsCompletion: true))
        XCTAssertFalse(NoorAccountDeletionState.permitsCloudDataActions(deletionRequested: true, needsCompletion: true))
    }
    func testOldIdentityFailureCannotApplyToAnotherAccountOrSameOwnerNewSession() {
        let generation = UUID()
        let operation = NoorAccountOperationIdentity(owner: "alice", generation: generation)
        XCTAssertTrue(operation.matches(owner: "alice", generation: generation))
        XCTAssertFalse(operation.matches(owner: "bob", generation: generation))
        XCTAssertFalse(operation.matches(owner: "alice", generation: UUID()))
        XCTAssertFalse(operation.matches(owner: nil, generation: generation))
    }
    func testUncertainCommitPersistsUntilSuccessfulCleanupEvenBeforeMarkerAppears() throws {
        let name = "NoorDeletionTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = NoorAccountDeletionState(defaults: defaults)
        state.recordAttempt(owner: "alice")
        let reopened = NoorAccountDeletionState(defaults: defaults)
        XCTAssertTrue(reopened.awaitingVerification(owner: "alice"))
        XCTAssertFalse(reopened.awaitingVerification(owner: "bob"))
        // No API clears uncertainty from an absent marker: a timed-out SDK
        // commit can still reach the server after the read completes.
        reopened.complete(owner: "bob")
        XCTAssertTrue(reopened.awaitingVerification(owner: "alice"))
        state.recordCommit(owner: "alice")
        XCTAssertTrue(state.committed(owner: "alice"))
        XCTAssertTrue(state.awaitingVerification(owner: "alice"))
        state.complete(owner: "alice")
        XCTAssertFalse(state.awaitingVerification(owner: "alice"))
    }
    func testCommittedDeletionSurvivesRestartAndRemainsBoundToItsOwner() throws {
        let name = "NoorDeletionTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = NoorAccountDeletionState(defaults: defaults)
        XCTAssertFalse(state.committed(owner: "alice"))
        state.recordCommit(owner: "alice")
        let reopened = NoorAccountDeletionState(defaults: defaults)
        XCTAssertTrue(reopened.committed(owner: "alice"))
        XCTAssertFalse(reopened.committed(owner: "bob"))
        reopened.complete(owner: "bob")
        XCTAssertTrue(reopened.committed(owner: "alice"))
        reopened.complete(owner: "alice")
        XCTAssertFalse(state.committed(owner: "alice"))
    }
    func testCommitIsIdempotentAndPreservesOtherOwnersAndUnrelatedData() throws {
        let name = "NoorDeletionTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data([1, 2, 3]), forKey: "noor.bookmarks")
        let state = NoorAccountDeletionState(defaults: defaults)
        state.recordCommit(owner: "alice"); state.recordCommit(owner: "alice")
        state.recordCommit(owner: "bob"); state.recordCommit(owner: "")
        state.complete(owner: "alice")
        XCTAssertTrue(state.committed(owner: "bob"))
        XCTAssertFalse(state.committed(owner: ""))
        XCTAssertEqual(defaults.data(forKey: "noor.bookmarks"), Data([1, 2, 3]))
    }
}
