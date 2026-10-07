import Foundation
import SwiftUI

struct NoorSyncStamp: Codable, Equatable, Comparable {
    let date: Date
    let device: UUID
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.device.uuidString < rhs.device.uuidString : lhs.date < rhs.date
    }
    var valid: Bool { date.timeIntervalSince1970.isFinite }
}
struct NoorSyncedValue<Value: Codable>: Codable {
    let value: Value
    let stamp: NoorSyncStamp
}

/// No location, audio, journal text, notification permissions or device tokens.
struct NoorReadingCloudState: Codable {
    var version = 1
    var bookmarks: [String: NoorSyncedValue<Bool>] = [:]
    var page: NoorSyncedValue<Int>?
    var lowMotion: NoorSyncedValue<Bool>?
    var largeQuran: NoorSyncedValue<Bool>?
    var plan: NoorSyncedValue<MemorizationPlan>?
    var latestDate: Date {
        ([page?.stamp.date, lowMotion?.stamp.date, largeQuran?.stamp.date, plan?.stamp.date].compactMap { $0 }
            + bookmarks.values.map { $0.stamp.date }).max() ?? .distantPast
    }
    func valid(corpus: [Surah]) -> Bool {
        guard version == 1, bookmarks.count <= 6236 else { return false }
        for (key, value) in bookmarks {
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, key == "\(parts[0]):\(parts[1])", corpus.indices.contains(parts[0] - 1),
                  (1...corpus[parts[0] - 1].ayahs.count).contains(parts[1]), value.stamp.valid else { return false }
        }
        guard page.map({ (1...604).contains($0.value) && $0.stamp.valid }) ?? true,
              lowMotion?.stamp.valid ?? true, largeQuran?.stamp.valid ?? true else { return false }
        if let plan {
            let p = plan.value
            guard plan.stamp.valid, corpus.indices.contains(p.chapter - 1), p.from > 0, p.to >= p.from,
                  p.to <= corpus[p.chapter - 1].ayahs.count, (1...50).contains(p.daily) else { return false }
        }
        return true
    }
    private static func newer<T: Codable>(_ local: NoorSyncedValue<T>?, _ remote: NoorSyncedValue<T>?) throws -> NoorSyncedValue<T>? {
        guard let local else { return remote }; guard let remote else { return local }
        if local.stamp == remote.stamp {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(local) == encoder.encode(remote) else { throw CocoaError(.fileReadCorruptFile) }
        }
        return local.stamp < remote.stamp ? remote : local
    }
    static func merge(_ local: Self, _ remote: Self, corpus: [Surah]) throws -> Self {
        guard local.valid(corpus: corpus), remote.valid(corpus: corpus) else { throw CocoaError(.fileReadCorruptFile) }
        var result = local
        for (key, value) in remote.bookmarks { result.bookmarks[key] = try newer(local.bookmarks[key], value) }
        result.page = try newer(local.page, remote.page)
        result.lowMotion = try newer(local.lowMotion, remote.lowMotion)
        result.largeQuran = try newer(local.largeQuran, remote.largeQuran)
        result.plan = try newer(local.plan, remote.plan)
        return result
    }
}

@MainActor final class NoorReadingSyncJournal: ObservableObject {
    static let shared = NoorReadingSyncJournal()
    struct Record: Codable {
        let owner: String
        let device: UUID
        var enabled: Bool
        var state: NoorReadingCloudState
    }
    @Published private(set) var revision = 0
    @Published private(set) var error: String?
    private(set) var record: Record?
    private(set) var unreadable: Data?
    private let defaults: UserDefaults
    private let key = "noor.sync.journal.v1"
    var enabled: Bool { record?.enabled == true }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: key) {
            do {
                let value = try JSONDecoder().decode(Record.self, from: bytes)
                guard !value.owner.isEmpty, let corpus = QuranResources.corpus, value.state.valid(corpus: corpus) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                record = value
            } catch { unreadable = bytes; self.error = "تعذر فتح سجل المزامنة. صدّر بياناتك قبل إصلاحه؛ بيانات الجهاز لم تتغير." }
        }
    }
    @discardableResult private func save(_ value: Record) -> Bool {
        guard unreadable == nil, let corpus = QuranResources.corpus, value.state.valid(corpus: corpus) else { return false }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
            record = value; error = nil; revision += 1; return true
        } catch { self.error = "تعذر حفظ سجل المزامنة. بقي تقدمك المحلي محفوظًا."; return false }
    }
    @discardableResult func setEnabled(_ enabled: Bool, owner: String, data: DeviceData, page: Int?, plan: MemorizationPlan?) -> Bool {
        guard !owner.isEmpty, unreadable == nil else { return false }
        if let bound = record?.owner, bound != owner {
            error = "بيانات هذا الجهاز مرتبطة بحساب آخر. صدّرها وسجّل خروجك؛ احذف بيانات الجهاز قبل ربط حساب مختلف."; return false
        }
        var value = record ?? Record(owner: owner, device: UUID(), enabled: false, state: .init())
        value.enabled = enabled
        guard save(value) else { return false }
        if enabled { _ = capture(data: data, page: page, plan: plan) }
        return true
    }
    /// Track local edits while signed out/disabled, but never upload until enabled
    /// for the same UID. False bookmark values are durable deletion tombstones.
    @discardableResult func capture(data: DeviceData, page: Int?, plan: MemorizationPlan?) -> Bool {
        guard var value = record, unreadable == nil else { return false }
        let stamp = NoorSyncStamp(date: max(Date(), value.state.latestDate.addingTimeInterval(0.001)), device: value.device)
        var changed = false
        let selected = Set(data.bookmarks)
        for key in selected.union(value.state.bookmarks.keys) {
            let present = selected.contains(key)
            if value.state.bookmarks[key]?.value != present {
                value.state.bookmarks[key] = .init(value: present, stamp: stamp); changed = true
            }
        }
        if let page, value.state.page?.value != page { value.state.page = .init(value: page, stamp: stamp); changed = true }
        if value.state.lowMotion.map({ $0.value != data.lowMotion }) ?? data.lowMotion { value.state.lowMotion = .init(value: data.lowMotion, stamp: stamp); changed = true }
        if value.state.largeQuran.map({ $0.value != data.largeQuran }) ?? data.largeQuran { value.state.largeQuran = .init(value: data.largeQuran, stamp: stamp); changed = true }
        if let plan {
            let old = value.state.plan?.value
            if old?.chapter != plan.chapter || old?.from != plan.from || old?.to != plan.to || old?.daily != plan.daily {
                value.state.plan = .init(value: plan, stamp: stamp); changed = true
            }
        }
        return changed && save(value)
    }
    @discardableResult func adopt(_ state: NoorReadingCloudState, owner: String) -> Bool {
        guard var value = record, value.owner == owner else { return false }
        value.state = state; return save(value)
    }
    func pause() { guard var value = record else { return }; value.enabled = false; _ = save(value) }
    func erase() { defaults.removeObject(forKey: key); record = nil; unreadable = nil; error = nil; revision += 1 }
    var exportBytes: Data? { defaults.data(forKey: key) }
}

struct NoorSyncResult: Codable {
    let reading: NoorReadingCloudState
    let memorization: MemorizationCloudBackup
}

struct NoorReadingLocalSnapshot: Codable {
    let device: DeviceData
    let page: Int
    let plan: MemorizationPlan
}
