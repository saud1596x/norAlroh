import XCTest
@testable import Athar

final class NoorSalawatTests: XCTestCase {
    @MainActor func testGoalDoesNotCapCountAndDaysSurviveRelaunchAndMidnight() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("counter.json")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let before = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 8, hour: 23, minute: 59)))
        let after = before.addingTimeInterval(120)
        let counter = NoorSalawatStore(file: file)
        XCTAssertTrue(counter.setGoal(3))
        XCTAssertTrue(counter.setCount(1000, at: before, timeZone: calendar.timeZone))
        XCTAssertTrue(counter.increment(at: before, timeZone: calendar.timeZone))
        let restored = NoorSalawatStore(file: file)
        XCTAssertEqual(restored.counts.goal, 3)
        XCTAssertEqual(restored.counts.count(at: before, timeZone: calendar.timeZone), 1001)
        XCTAssertEqual(restored.counts.count(at: after, timeZone: calendar.timeZone), 0)
        XCTAssertTrue(restored.increment(at: after, timeZone: calendar.timeZone))
        XCTAssertEqual(restored.counts.count(at: before, timeZone: calendar.timeZone), 1001)
        XCTAssertEqual(restored.counts.count(at: after, timeZone: calendar.timeZone), 1)
        XCTAssertTrue(restored.setGoal(nil))
        XCTAssertTrue(restored.erase())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(NoorSalawatStore(file: file).counts.days.isEmpty)
    }
    @MainActor func testUnreadableArchiveAndWriteRefusalKeepPriorBytesAndCount() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("counter.json"), sentinel = Data("unreadable prior record".utf8)
        try sentinel.write(to: file)
        let damaged = NoorSalawatStore(file: file)
        XCTAssertFalse(damaged.increment()); XCTAssertEqual(damaged.exportBytes, sentinel)
        let refused = NoorSalawatStore(file: folder.appendingPathComponent("blocked.json"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("blocked.json"), withIntermediateDirectories: true)
        XCTAssertFalse(refused.increment()); XCTAssertTrue(refused.counts.days.isEmpty); XCTAssertNotNil(refused.error)
    }
    func testWidgetMidnightUsesRecordedDeviceZoneAndLegacySnapshotStillDecodes() throws {
        let before = Date(timeIntervalSince1970: 1791493140)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        let next = try XCTUnwrap(c.date(byAdding: .day, value: 1, to: c.startOfDay(for: before)))
        let counts = NoorSalawatCounts(days: [NoorSalawatCounts.dayKey(before, timeZone: zone): 27], goal: nil)
        XCTAssertEqual(counts.count(at: next.addingTimeInterval(-1), timeZone: zone), 27)
        XCTAssertEqual(counts.count(at: next, timeZone: zone), 0)
        let old = NoorWidgetSnapshot(version: 1, updated: before, prayer: PrayerCalculator.inputs(DeviceData()), page: 604,
            dailyTarget: 3, practiced: [:], reviewDates: [], dua: "", duaTitle: "")
        let restored = try JSONDecoder().decode(NoorWidgetSnapshot.self, from: JSONEncoder().encode(old))
        XCTAssertNil(restored.salawat); XCTAssertNil(restored.khatmah); XCTAssertEqual(restored.page, 604)
        var updated = old; updated.salawat = counts; updated.salawatTimeZone = zone.identifier
        let fresh = try JSONDecoder().decode(NoorWidgetSnapshot.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(fresh.salawat, counts); XCTAssertEqual(fresh.salawatTimeZone, zone.identifier)
    }
    func testKhatmahWidgetMatchesRealConfirmedAndRescheduledPlan() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let now = try XCTUnwrap(c.date(from: .init(year: 2026, month: 10, day: 8, hour: 10)))
        let plan = try KhatmahCalculator.make(first: 580, date: now, weekdays: [6], daily: 4, deadline: nil, reminder: nil, calendar: c)
        func snapshot(_ p: KhatmahPlan) -> NoorKhatmahWidgetState {
            .init(firstPage: p.firstPage, nextPage: p.nextPage, completed: p.completed.count, paused: p.paused,
                timeZone: p.timeZone, days: p.days.map { .init(date: $0.date, first: $0.first, last: $0.last) })
        }
        XCTAssertEqual(snapshot(plan).wardTitle(at: now), "الورد القادم")
        XCTAssertEqual(snapshot(plan).ward(at: now)?.first, plan.due(on: now)?.first)
        let read = try KhatmahCalculator.confirm(plan, first: 580, last: 585, date: now)
        XCTAssertEqual(snapshot(read).completed, 6)
        XCTAssertEqual(snapshot(read).ward(at: now)?.first, 586)
        let revised = try KhatmahCalculator.revised(read, date: now, weekdays: Set(1...7), daily: 2, deadline: nil, reminder: nil)
        XCTAssertTrue(snapshot(revised).valid)
        XCTAssertEqual(snapshot(revised).ward(at: now)?.last, revised.due(on: now)?.last)
        var paused = revised; paused.paused = true
        XCTAssertNil(snapshot(paused).ward(at: now)); XCTAssertEqual(snapshot(paused).wardTitle(at: now), "الرحلة متوقفة مؤقتًا")
        let finished = try KhatmahCalculator.confirm(revised, first: 586, last: 604, date: now)
        XCTAssertTrue(snapshot(finished).valid); XCTAssertNil(snapshot(finished).ward(at: now))
        XCTAssertEqual(snapshot(finished).wardTitle(at: now), "اكتملت الختمة")
    }
    @MainActor func testNewWidgetRoutesArePreservedUntilConsumed() throws {
        let router = NoorWidgetRouter()
        for host in ["khatmah", "salawat"] {
            XCTAssertTrue(router.open(try XCTUnwrap(URL(string: "nooralruh://" + host))))
            XCTAssertEqual(router.destination?.host, host)
        }
        let id = router.destination?.id
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "nooralruh://user:secret@salawat"))))
        XCTAssertEqual(router.destination?.id, id)
    }
}
