import XCTest
@testable import Athar

final class WidgetTimelineTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    @MainActor func testWidgetKhatmahWardMatchesBoundedDailyScopeAfterMissedDaysAndPartialReading() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let start = date("2026-10-07T07:00:00Z"), later = calendar.date(byAdding: .day, value: 8, to: start)!
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20, deadline: nil, reminder: nil, calendar: calendar)
        let partial = try KhatmahCalculator.confirm(plan, first: 1, last: 7, date: later)
        var stopped = partial; stopped.stoppedAt = .init(page: 12, chapter: 2, ayah: 77)
        let finishedToday = try KhatmahCalculator.confirm(partial, first: 8, last: 20, date: later)
        for candidate in [plan, partial, stopped, finishedToday] {
            let widget = NoorWidgetBridge.journeySnapshot(candidate, now: later)
            XCTAssertTrue(widget.valid)
            for offset in 0...2 {
                let now = calendar.date(byAdding: .day, value: offset, to: later)!
                let expected = candidate.readingScope(on: now), actual = widget.ward(at: now)
                XCTAssertEqual(actual?.first, expected?.first)
                XCTAssertEqual(actual?.last, expected?.last)
                XCTAssertEqual(actual?.date, expected?.date)
                XCTAssertEqual(widget.resumePage(at: now), expected.map { $0.resumePage(candidate.stoppedAt) })
            }
        }
        XCTAssertEqual(NoorWidgetBridge.journeySnapshot(plan, now: later).ward(at: later)?.last, 20, "Missed days cannot turn the daily quota into 60 or 180 pages")
        XCTAssertNil(NoorWidgetBridge.journeySnapshot(finishedToday, now: later).ward(at: later))
        let widget = NoorWidgetBridge.journeySnapshot(stopped, now: later)
        let route = try XCTUnwrap(NoorWidgetLink.parse(try XCTUnwrap(widget.wardURL(at: later))))
        XCTAssertEqual(route.wardID, "khatmah:\(plan.id.uuidString)")
        XCTAssertEqual(route.page, 12)
        XCTAssertEqual(NoorWidgetLink.khatmahPlanID(from: try XCTUnwrap(route.wardID)), plan.id)
        XCTAssertEqual(stopped.completed, Set(1...7), "Widget navigation must not credit any page")
    }
    @MainActor func testWidgetKhatmahDeadlineQuotaAndValidityMatchCurrentAppContract() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date("2026-10-31T14:00:00Z"), later = calendar.date(byAdding: .day, value: 2, to: start)!
        let plan = try KhatmahCalculator.make(first: 590, date: start, weekdays: Set(1...7), daily: nil,
            deadline: calendar.date(byAdding: .day, value: 4, to: start), reminder: nil, calendar: calendar)
        let widget = NoorWidgetBridge.journeySnapshot(plan, now: later)
        XCTAssertTrue(widget.valid)
        XCTAssertEqual(widget.ward(at: later)?.last, plan.readingScope(on: later)?.last)
        var noncontiguous = plan; noncontiguous.completed = [591]
        XCTAssertFalse(noncontiguous.valid, "The actual app currently rejects noncontiguous completed sets")
        let corrupted = NoorKhatmahWidgetState(firstPage: 590, nextPage: 590, completed: 1, paused: false,
            timeZone: plan.timeZone, days: widget.days)
        XCTAssertFalse(corrupted.valid)
        let legacy = NoorKhatmahWidgetState(firstPage: plan.firstPage, nextPage: plan.nextPage, completed: 0,
            paused: false, timeZone: plan.timeZone, days: widget.days)
        XCTAssertTrue(legacy.valid)
        XCTAssertNil(legacy.ward(at: later), "Legacy snapshots cannot prove same-day completion totals")
    }
    func testOnlyExplicitlyTrustedSnapshotEnablesPrayerWidgetsAndTrustChangesReloadThem() throws {
        let unknown = NoorWidgetSnapshot(version: 1, updated: date("2026-10-31T20:59:59Z"), prayer: PrayerCalculator.inputs(DeviceData()),
            page: 10, dailyTarget: 3, practiced: [:], reviewDates: [], dua: "", duaTitle: "")
        XCTAssertFalse(unknown.canDisplayPrayerTimes)
        var trusted = unknown; trusted.prayerTrusted = true
        XCTAssertTrue(trusted.canDisplayPrayerTimes)
        XCTAssertEqual(trusted.changedKinds(from: unknown), ["noor.nextPrayer", "noor.prayerDay"])
        trusted.prayerTrusted = false
        XCTAssertFalse(trusted.canDisplayPrayerTimes)
        XCTAssertNotNil(NoorWidgetSnapshot.decode(try JSONEncoder().encode(trusted)))
        XCTAssertFalse(NoorDuaCatalog.home.isEmpty, "Untrusted default location cannot block local dua")
        XCTAssertEqual(NoorWidgetLink.parse(try XCTUnwrap(NoorWidgetLink.reading(page: trusted.page)))?.page, 10)
        for invalid in ["nooralruh://ward?wardID=khatmah:invalid&pageID=1", "nooralruh://ward?wardID=khatmah:\(UUID().uuidString)", "nooralruh://ward?wardID=memorization:115:1:7"] {
            XCTAssertNil(NoorWidgetLink.parse(try XCTUnwrap(URL(string: invalid))))
        }
    }
    func testOfflineCatalogHasStableUniqueIDsAndCompleteFamilyPools() throws {
        XCTAssertEqual(NoorDuaCatalog.home.count, 53)
        XCTAssertEqual(Set(NoorDuaCatalog.home.map(\.id)).count, 53)
        XCTAssertEqual(Set(NoorDuaCatalog.home.map(\.text)).count, 53)
        XCTAssertEqual(NoorDuaFamily.small.content.count, 31)
        XCTAssertEqual(NoorDuaFamily.lockRectangular.content.count, 7)
        XCTAssertEqual(NoorDuaFamily.lockInline.content.count, 3)
        for family in NoorDuaFamily.allCases {
            for dua in family.content {
                XCTAssertEqual(NoorDuaCatalog.find(dua.id), dua)
                XCTAssertFalse(dua.text.contains("…"))
                XCTAssertFalse(dua.text.isEmpty)
            }
        }
    }
    func testTimelineCovers48HoursAndSelectionSurvivesRestartAndMidnight() throws {
        for zone in ["Asia/Riyadh", "Asia/Kathmandu", "Pacific/Chatham", "America/New_York", "Australia/Lord_Howe"] {
            for stamp in ["2026-10-31T20:59:59Z", "2026-03-08T06:59:59Z", "2026-11-01T05:30:00Z", "2026-04-04T14:30:00Z", "2026-10-03T14:30:00Z"] {
                let now = date(stamp), timeZone = try XCTUnwrap(TimeZone(identifier: zone))
                for family in NoorDuaFamily.allCases {
                    let entries = NoorDuaTimeline.entries(now: now, family: family, timeZone: timeZone)
                    XCTAssertEqual(entries.first?.date, now)
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(entries.last?.date).timeIntervalSince(now), 172_800)
                    XCTAssertLessThanOrEqual(entries.count, 52)
                    for (first, second) in zip(entries, entries.dropFirst()) {
                        XCTAssertLessThan(first.date, second.date)
                        XCTAssertNotEqual(first.dua.id, second.dua.id, "\(zone) \(stamp) \(family)")
                        XCTAssertEqual(second.dua, NoorDuaTimeline.selection(at: second.date.addingTimeInterval(1), family: family, timeZone: timeZone))
                        XCTAssertEqual(second.dua, NoorDuaTimeline.entries(now: second.date, family: family, timeZone: timeZone).first?.dua)
                    }
                    let bytes = try JSONEncoder().encode(entries)
                    XCTAssertLessThan(bytes.count, 64_000)
                    XCTAssertEqual(try JSONDecoder().decode([NoorDuaTimelineEntry].self, from: bytes), entries)
                }
            }
        }
    }
    func testSpringSkipAndFallRepeatedHourAreExplicitDifferentEntries() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let calendar = NoorDuaTimeline.calendar(timeZone: zone)
        let spring = NoorDuaTimeline.entries(now: date("2026-03-08T06:30:00Z"), family: .home, timeZone: zone)
        XCTAssertEqual(calendar.component(.hour, from: spring[0].date), 1)
        XCTAssertEqual(calendar.component(.hour, from: spring[1].date), 3)
        let fall = NoorDuaTimeline.entries(now: date("2026-11-01T05:30:00Z"), family: .home, timeZone: zone)
        XCTAssertEqual(calendar.component(.hour, from: fall[0].date), 1)
        XCTAssertEqual(calendar.component(.hour, from: fall[1].date), 1)
        XCTAssertNotEqual(fall[0].dua.id, fall[1].dua.id)
        XCTAssertEqual(Set(fall.prefix(24).map(\.dua.id)).count, 24)
    }
    func testWholeLocalDayHasNoRepeatedHomeDua() throws {
        for zone in ["Asia/Riyadh", "America/New_York", "Australia/Lord_Howe"] {
            let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let calendar = NoorDuaTimeline.calendar(timeZone: timeZone)
            for stamp in ["2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z", "2026-04-05T03:00:00Z"] {
                let start = calendar.startOfDay(for: date(stamp)), end = calendar.date(byAdding: .day, value: 1, to: start)!
                for family in [NoorDuaFamily.home, .small] {
                    let entries = NoorDuaTimeline.entries(now: start, family: family, timeZone: timeZone).filter { $0.date < end }
                    XCTAssertEqual(Set(entries.map(\.dua.id)).count, entries.count, "\(zone) \(stamp) \(family)")
                }
            }
        }
    }
    func testStickyDuaURLDoesNotRecomputeAfterHourChanges() throws {
        let tapped = NoorDuaTimeline.selection(at: date("2026-10-31T20:59:59Z"), family: .home, timeZone: .gmt)
        let later = NoorDuaTimeline.selection(at: date("2026-10-31T21:00:01Z"), family: .home, timeZone: .gmt)
        XCTAssertNotEqual(tapped, later)
        let destination = try XCTUnwrap(NoorWidgetLink.parse(NoorWidgetLink.dua(tapped)))
        XCTAssertEqual(destination.duaID, tapped.id)
        XCTAssertNil(destination.page)
        for invalid in ["nooralruh://dua?duaID=unknown", "nooralruh://dua?duaID=unknown&duaID=x", "nooralruh://reading", "nooralruh://reading/0", "nooralruh://reading/605", "nooralruh://reading/1/2", "nooralruh://reading/01", "nooralruh://ward?wardID=../../bad", "nooralruh://ward?wardID=x&pageID=no", "nooralruh://reading/1?other=x"] {
            XCTAssertNil(NoorWidgetLink.parse(try XCTUnwrap(URL(string: invalid))), invalid)
        }
        XCTAssertEqual(NoorWidgetLink.parse(try XCTUnwrap(NoorWidgetLink.ward(id: "memorization:2:1:5")))?.wardID, "memorization:2:1:5")
    }
    func testVersionedAtomicSnapshotRejectsCorruptionAndReloadsOnlyChangedKinds() throws {
        let now = date("2026-10-31T20:59:59Z")
        let first = NoorWidgetSnapshot(version: 2, updated: now, prayer: PrayerCalculator.inputs(DeviceData()), page: 10,
            dailyTarget: 3, practiced: [:], reviewDates: [], dua: "", duaTitle: "", duaCatalogVersion: 1)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try first.write(to: file)
        let old = try XCTUnwrap(NoorWidgetSnapshot.decode(Data(contentsOf: file)))
        XCTAssertTrue(first.changedKinds(from: old).isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["updated"] = now.addingTimeInterval(60).timeIntervalSinceReferenceDate
        let reopened = try XCTUnwrap(NoorWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertTrue(reopened.changedKinds(from: old).isEmpty, "Opening app alone must not reload all widget kinds")
        object["version"] = 1; object.removeValue(forKey: "duaCatalogVersion")
        let legacy = try XCTUnwrap(NoorWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(legacy.page, 10)
        XCTAssertEqual(first.changedKinds(from: legacy), ["noor.dua", "noor.shortDhikr"])
        var changed = first
        changed.hasReadingPosition = true
        XCTAssertEqual(changed.changedKinds(from: old), ["noor.reading"])
        changed = first; changed.duaCatalogVersion = 2
        XCTAssertEqual(changed.changedKinds(from: old), ["noor.dua", "noor.shortDhikr"])
        XCTAssertNil(NoorWidgetSnapshot.decode(Data("{broken".utf8)))
        XCTAssertNil(NoorWidgetSnapshot.decode(Data(repeating: 0, count: 256_000)))
        let invalid = NoorWidgetSnapshot(version: 99, updated: now, prayer: first.prayer, page: 605,
            dailyTarget: 3, practiced: [:], reviewDates: [], dua: "", duaTitle: "")
        XCTAssertThrowsError(try invalid.write(to: file))
        XCTAssertEqual(NoorWidgetSnapshot.decode(try Data(contentsOf: file))?.page, 10)
    }
    @MainActor func testColdRouterRetainsExactDuaAndWardIdentityWithoutCreditingReading() throws {
        let suite = "NoorWidgetIdentity." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(604, forKey: "noor.mushaf.lastPage")
        let progress = Data("confirmed reading progress".utf8)
        defaults.set(progress, forKey: "noor.widget.test.progress")
        let router = NoorWidgetRouter(defaults: defaults)
        let tapped = NoorDuaCatalog.home[12]
        XCTAssertTrue(router.open(NoorWidgetLink.dua(tapped)))
        XCTAssertEqual(router.destination?.duaID, tapped.id)
        XCTAssertNil(router.destination?.page)
        XCTAssertTrue(router.open(try XCTUnwrap(NoorWidgetLink.ward(id: "memorization:2:1:5"))))
        XCTAssertEqual(router.destination?.wardID, "memorization:2:1:5")
        let pendingID = router.destination?.id
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "nooralruh://reading/604/1"))))
        XCTAssertEqual(router.destination?.id, pendingID)
        XCTAssertEqual(defaults.integer(forKey: "noor.mushaf.lastPage"), 604)
        XCTAssertEqual(defaults.data(forKey: "noor.widget.test.progress"), progress)
    }
}
