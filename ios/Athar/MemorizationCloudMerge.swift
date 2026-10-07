import Foundation

/// Pure merge: transaction retries cannot mutate a local session or progress.
enum MemorizationCloudMerge {
    enum MergeError: Error { case invalidArchive, conflictingEvent }
    private static func valid(_ backup: MemorizationCloudBackup, corpus: [Surah]) -> Bool {
        let plan = backup.plan
        guard backup.version == 1, backup.archive.version == 1,
              corpus.indices.contains(plan.chapter - 1), plan.from > 0, plan.to >= plan.from,
              plan.to <= corpus[plan.chapter - 1].ayahs.count, (1...50).contains(plan.daily),
              backup.archive.progress.verses.count <= 6236, backup.archive.progress.valid(corpus: corpus),
              Set(backup.archive.history.map(\.id)).count == backup.archive.history.count else { return false }
        return backup.archive.history.allSatisfy { result in
            corpus.indices.contains(result.chapter - 1) && !result.answers.isEmpty && result.date.timeIntervalSince1970.isFinite
                && Set(result.answers.map(\.ayah)).count == result.answers.count
                && result.answers.allSatisfy { (1...corpus[result.chapter - 1].ayahs.count).contains($0.ayah)
                    && ["remembered", "review", "skip"].contains($0.assessment) && $0.hints >= 0 }
        }
    }
    static func merge(local: MemorizationCloudBackup, remote: MemorizationCloudBackup, corpus: [Surah]) throws -> MemorizationCloudBackup {
        guard valid(local, corpus: corpus), valid(remote, corpus: corpus) else { throw MergeError.invalidArchive }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var results = Dictionary(uniqueKeysWithValues: local.archive.history.map { ($0.id, $0) })
        for result in remote.archive.history {
            if let local = results[result.id], try encoder.encode(local) != encoder.encode(result) {
                throw MergeError.conflictingEvent
            }
            results[result.id] = result
        }
        let combined = results.values.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
        var restored = MemorizationProgress()
        for result in combined.reversed() { restored.record(result) }
        // Retain older progress whose full event history may not be present in
        // a legacy archive. Do not add cumulative counters from two devices.
        for source in [local.archive.progress, remote.archive.progress] {
            for (key, value) in source.verses {
                guard var current = restored.verses[key] else { restored.verses[key] = value; continue }
                let attempts = max(current.attempts, value.attempts)
                let lapses = max(current.lapses, value.lapses)
                if value.lastPracticed > current.lastPracticed { current = value }
                else if value.lastPracticed == current.lastPracticed {
                    current.stage = min(current.stage, value.stage)
                    current.needsHelp = current.needsHelp || value.needsHelp
                    current.nextReview = min(current.nextReview, value.nextReview)
                }
                current.attempts = attempts; current.lapses = lapses
                restored.verses[key] = current
            }
            for (day, keys) in source.practiceDays { restored.practiceDays[day, default: []].formUnion(keys) }
        }
        restored.excludedMistakeIDs = local.archive.progress.excludedMistakeIDs.union(remote.archive.progress.excludedMistakeIDs)
        var notes: [UUID: ConfirmedRecitationMistake] = [:]
        for note in local.archive.progress.confirmedMistakes + remote.archive.progress.confirmedMistakes {
            guard !restored.excludedMistakeIDs.contains(note.id) else { continue }
            if let local = notes[note.id], try encoder.encode(local) != encoder.encode(note) {
                throw MergeError.conflictingEvent
            }
            notes[note.id] = note
        }
        restored.confirmedMistakes = notes.values.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
        guard restored.valid(corpus: corpus) else { throw MergeError.invalidArchive }
        return MemorizationCloudBackup(version: 1, plan: local.plan,
            archive: MemorizationArchive(version: 1, history: combined, progress: restored, plan: local.plan))
    }
}
