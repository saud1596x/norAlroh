import Foundation

struct NoorAccountOperationIdentity {
    let owner: String
    let generation: UUID
    func matches(owner currentOwner: String?, generation currentGeneration: UUID) -> Bool {
        owner == currentOwner && generation == currentGeneration
    }
}

/// A committed server deletion marker cannot be undone by cancelling a UI flow.
/// Persist only identity keys; never profile, audio or reading data.
struct NoorAccountDeletionState {
    static func permitsCloudDataActions(deletionRequested: Bool, needsCompletion: Bool) -> Bool {
        !deletionRequested && !needsCompletion
    }
    private let defaults: UserDefaults
    private let key = "noor.account.committedDeletionOwners.v1"
    private let pendingKey = "noor.account.unverifiedDeletionOwners.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func committed(owner: String) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(owner)
    }
    func recordCommit(owner: String) {
        guard !owner.isEmpty else { return }
        var owners = Set(defaults.stringArray(forKey: key) ?? [])
        owners.insert(owner); defaults.set(owners.sorted(), forKey: key)
    }
    func awaitingVerification(owner: String) -> Bool {
        (defaults.stringArray(forKey: pendingKey) ?? []).contains(owner)
    }
    func recordAttempt(owner: String) {
        guard !owner.isEmpty else { return }
        var owners = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        owners.insert(owner); defaults.set(owners.sorted(), forKey: pendingKey)
    }
    func complete(owner: String) {
        let owners = (defaults.stringArray(forKey: key) ?? []).filter { $0 != owner }
        defaults.set(owners, forKey: key)
        defaults.set((defaults.stringArray(forKey: pendingKey) ?? []).filter { $0 != owner }, forKey: pendingKey)
    }
}
