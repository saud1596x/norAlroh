import Foundation

/// Private working files for the open Mushaf, never a recording library.
/// A different process cannot restore them. Older app recordings are removed
/// on upgrade; current reading positions, Quran assets and reciter audio stay.
enum QuranLiveRecitationStorage {
    private static let processID = UUID().uuidString
    private static let migrationLock = NSLock()
    private static var migrated = false

    static func root() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent("NoorLiveRecitation", isDirectory: true)
            .appendingPathComponent(processID, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    static func removePreviousRecordings() throws {
        migrationLock.lock(); defer { migrationLock.unlock() }
        guard !migrated else { return }
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try manager.url(for: .cachesDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        try removePreviousRecordings(support: support, caches: caches, keepingProcess: processID)
        UserDefaults.standard.removeObject(forKey: "noor.recitation.pending")
        migrated = true
    }

    // Explicit parent directories let tests prove that unrelated files survive.
    static func removePreviousRecordings(support: URL, caches: URL, keepingProcess: String) throws {
        let manager = FileManager.default
        for name in ["NoorMushafRecordings", "NoorRecitation"] {
            let old = support.appendingPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: old.path) { try manager.removeItem(at: old) }
        }
        let workspace = caches.appendingPathComponent("NoorLiveRecitation", isDirectory: true)
        guard manager.fileExists(atPath: workspace.path) else { return }
        // Do not traverse a substituted directory outside this app workspace.
        guard try workspace.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        for old in try manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)
            where old.lastPathComponent != keepingProcess {
            try manager.removeItem(at: old)
        }
    }
}
