import Foundation
import Testing
@testable import TimeZoneCore

// Known answers use 2026 transitions: US DST Mar 8 / Nov 1, EU DST Mar 29 / Oct 25.

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private func tz(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

/// "yyyy-MM-dd HH:mm" of `date` in zone `id`.
private func wall(_ date: Date, _ id: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz(id)
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
}

private func freshDefaults() -> UserDefaults {
    let name = "TimeZoneCoreTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

private func model(now: Date, local: String = "America/Montevideo", zones: [String]) -> ComparisonModel {
    let store = ZoneStore(defaults: freshDefaults(), localZone: { tz(local) })
    store.saveZones(zones)
    return ComparisonModel(store: store, clock: { now }, localZone: { tz(local) })
}

@Suite struct ConversionTests {
    @Test func tokyoNineAMInOtherZonesWinter() {
        let t = ZoneMath.instant(minuteOfDay: 9 * 60, onDayOf: utc("2026-01-15T03:00:00Z"), in: tz("Asia/Tokyo"))
        #expect(t == utc("2026-01-15T00:00:00Z"))
        #expect(wall(t, "Europe/London") == "2026-01-15 00:00")
        #expect(wall(t, "America/New_York") == "2026-01-14 19:00")
        #expect(wall(t, "America/Los_Angeles") == "2026-01-14 16:00")
        #expect(wall(t, "America/Montevideo") == "2026-01-14 21:00")
        #expect(wall(t, "Australia/Sydney") == "2026-01-15 11:00")
    }

    @Test func tokyoNineAMInOtherZonesSummer() {
        let t = ZoneMath.instant(minuteOfDay: 9 * 60, onDayOf: utc("2026-07-15T03:00:00Z"), in: tz("Asia/Tokyo"))
        #expect(wall(t, "Europe/London") == "2026-07-15 01:00")   // BST
        #expect(wall(t, "America/New_York") == "2026-07-14 20:00") // EDT
        #expect(wall(t, "Australia/Sydney") == "2026-07-15 10:00") // AEST
    }

    @Test func modelSliderDragUpdatesAllRows() {
        let ids = ["America/Montevideo", "Asia/Tokyo", "Europe/London", "America/New_York"]
        let m = model(now: utc("2026-01-15T03:00:00Z"), zones: ids)
        #expect(m.isLive)
        m.setSlider(minutes: 9 * 60 + 5, in: tz("Asia/Tokyo"), anchor: m.instant) // snaps to 09:00
        #expect(!m.isLive)
        #expect(m.sliderMinutes(in: tz("Asia/Tokyo")) == 9 * 60)
        #expect(m.sliderMinutes(in: tz("Europe/London")) == 0)
        #expect(m.sliderMinutes(in: tz("America/New_York")) == 19 * 60)
        #expect(m.sliderMinutes(in: tz("America/Montevideo")) == 21 * 60)
        #expect(m.dayDifference(for: tz("Asia/Tokyo")) == 1)
        #expect(m.dayDifference(for: tz("Europe/London")) == 1)
        #expect(m.dayDifference(for: tz("America/New_York")) == 0)
        #expect(m.offsetDescription == "\u{2212}3h from now") // Tokyo was at 12:00 when the drag began
    }

    @Test func snappingIsFifteenMinutes() {
        #expect(ZoneMath.snap(9 * 60 + 7) == 9 * 60)
        #expect(ZoneMath.snap(9 * 60 + 8) == 9 * 60 + 15)
        #expect(ZoneMath.snap(1439) == 1440)
    }

    @Test func resetReturnsToLive() {
        var current = utc("2026-01-15T03:00:00Z")
        let store = ZoneStore(defaults: freshDefaults(), localZone: { tz("UTC") })
        let m = ComparisonModel(store: store, clock: { current }, localZone: { tz("UTC") })
        m.setSlider(minutes: 600, in: tz("UTC"), anchor: m.instant)
        #expect(m.instant == utc("2026-01-15T10:00:00Z"))
        #expect(m.offsetDescription == "+7h from now")
        current = utc("2026-01-15T03:30:00Z")
        m.tick()
        #expect(m.offsetDescription == "+6h 30m from now") // fixed instant, clock moves on
        m.resetToNow()
        #expect(m.isLive)
        #expect(m.offsetDescription == nil)
        current = utc("2026-01-15T03:31:00Z")
        m.tick()
        #expect(m.instant == current) // live ticking resumed
    }
}

@Suite struct LiveClockTests {
    @Test func tickPublishesOnlyWhenTheMinuteChanges() {
        var current = utc("2026-01-15T03:00:05Z")
        let store = ZoneStore(defaults: freshDefaults(), localZone: { tz("UTC") })
        let m = ComparisonModel(store: store, clock: { current }, localZone: { tz("UTC") })
        var publishes = 0
        let sub = m.objectWillChange.sink { publishes += 1 }
        current = utc("2026-01-15T03:00:59Z")
        m.tick()
        #expect(publishes == 0)
        #expect(m.instant == utc("2026-01-15T03:00:05Z"))
        current = utc("2026-01-15T03:01:00Z")
        m.tick()
        #expect(publishes == 1)
        #expect(m.instant == utc("2026-01-15T03:01:00Z"))
        sub.cancel()
    }
}

@Suite struct FractionalOffsetTests {
    @Test func indiaNepalChatham() {
        let t = utc("2026-01-15T00:00:00Z")
        #expect(wall(t, "Asia/Kolkata") == "2026-01-15 05:30")
        #expect(wall(t, "Asia/Kathmandu") == "2026-01-15 05:45")
        #expect(wall(t, "Pacific/Chatham") == "2026-01-15 13:45") // Chatham summer time
        #expect(ZoneMath.utcOffsetLabel(tz("Asia/Kolkata"), at: t) == "UTC+5:30")
        #expect(ZoneMath.utcOffsetLabel(tz("Asia/Kathmandu"), at: t) == "UTC+5:45")
        #expect(ZoneMath.utcOffsetLabel(tz("Pacific/Chatham"), at: t) == "UTC+13:45")
        #expect(ZoneMath.utcOffsetLabel(tz("Pacific/Chatham"), at: utc("2026-07-15T00:00:00Z")) == "UTC+12:45")
        #expect(ZoneMath.utcOffsetLabel(tz("America/Montevideo"), at: t) == "UTC\u{2212}3")
        #expect(ZoneMath.utcOffsetLabel(tz("UTC"), at: t) == "UTC")
    }

    @Test func settingTimeInNepalAndIndia() {
        let t = ZoneMath.instant(minuteOfDay: 9 * 60, onDayOf: utc("2026-07-15T06:00:00Z"), in: tz("Asia/Kathmandu"))
        #expect(t == utc("2026-07-15T03:15:00Z"))
        #expect(wall(t, "Asia/Kolkata") == "2026-07-15 08:45")
        #expect(wall(t, "Pacific/Chatham") == "2026-07-15 16:00")
        #expect(ZoneMath.minuteOfDay(t, in: tz("Pacific/Chatham")) == 16 * 60)
    }
}

@Suite struct DSTTests {
    @Test func usAndEuropeChangeOnDifferentDates() {
        // NY noon -> London: 5h apart normally, 4h between US (Mar 8) and EU (Mar 29) changes.
        for (day, london) in [("2026-03-01", "17:00"), ("2026-03-15", "16:00"), ("2026-04-01", "17:00")] {
            let t = ZoneMath.instant(minuteOfDay: 12 * 60, onDayOf: utc("\(day)T17:00:00Z"), in: tz("America/New_York"))
            #expect(wall(t, "Europe/London") == "\(day) \(london)")
        }
        // Autumn: EU back Oct 25, US back Nov 1.
        for (day, london) in [("2026-10-20", "17:00"), ("2026-10-28", "16:00"), ("2026-11-04", "17:00")] {
            let t = ZoneMath.instant(minuteOfDay: 12 * 60, onDayOf: utc("\(day)T17:00:00Z"), in: tz("America/New_York"))
            #expect(wall(t, "Europe/London") == "\(day) \(london)")
        }
    }

    @Test func springForwardGapResolvesToFirstTimeAfterGap() {
        // US: 02:00-02:59 does not exist on 2026-03-08.
        let ny = ZoneMath.instant(minuteOfDay: 2 * 60 + 30, onDayOf: utc("2026-03-08T17:00:00Z"), in: tz("America/New_York"))
        #expect(ny == utc("2026-03-08T07:00:00Z"))
        #expect(wall(ny, "America/New_York") == "2026-03-08 03:00")
        // EU: 02:00-02:59 does not exist in Paris on 2026-03-29.
        let paris = ZoneMath.instant(minuteOfDay: 2 * 60 + 15, onDayOf: utc("2026-03-29T12:00:00Z"), in: tz("Europe/Paris"))
        #expect(wall(paris, "Europe/Paris") == "2026-03-29 03:00")
        #expect(paris == utc("2026-03-29T01:00:00Z"))
        // Times either side of the gap are untouched.
        let before = ZoneMath.instant(minuteOfDay: 1 * 60 + 45, onDayOf: utc("2026-03-08T17:00:00Z"), in: tz("America/New_York"))
        #expect(before == utc("2026-03-08T06:45:00Z"))
    }

    @Test func fallBackOverlapResolvesToFirstOccurrence() {
        let ny = ZoneMath.instant(minuteOfDay: 90, onDayOf: utc("2026-11-01T17:00:00Z"), in: tz("America/New_York"))
        #expect(ny == utc("2026-11-01T05:30:00Z")) // 01:30 EDT, not 01:30 EST (06:30Z)
        let paris = ZoneMath.instant(minuteOfDay: 150, onDayOf: utc("2026-10-25T12:00:00Z"), in: tz("Europe/Paris"))
        #expect(paris == utc("2026-10-25T00:30:00Z")) // 02:30 CEST
        // The second occurrence is still displayed correctly when reached from another zone.
        #expect(ZoneMath.minuteOfDay(utc("2026-11-01T06:30:00Z"), in: tz("America/New_York")) == 90)
    }

    @Test func sliderOnTransitionDayIsWallClock() {
        // On the 25-hour fall-back day, slider 18:00 is 18:00 on the wall, not 18h after midnight.
        let t = ZoneMath.instant(minuteOfDay: 18 * 60, onDayOf: utc("2026-11-01T17:00:00Z"), in: tz("America/New_York"))
        #expect(wall(t, "America/New_York") == "2026-11-01 18:00")
        #expect(ZoneMath.minuteOfDay(t, in: tz("America/New_York")) == 18 * 60)
    }

    @Test func abbreviationsFollowDST() {
        let paris = ZoneCatalog.info(for: "Europe/Paris")!
        #expect(paris.abbreviation(at: utc("2026-01-15T12:00:00Z")) == "CET")
        #expect(paris.abbreviation(at: utc("2026-07-15T12:00:00Z")) == "CEST")
        let ny = ZoneCatalog.info(for: "America/New_York")!
        #expect(ny.abbreviation(at: utc("2026-03-07T12:00:00Z")) == "EST")
        #expect(ny.abbreviation(at: utc("2026-03-09T12:00:00Z")) == "EDT")
        #expect(ZoneCatalog.info(for: "Asia/Tokyo")!.abbreviation(at: utc("2026-01-15T12:00:00Z")) == "JST")
        #expect(ZoneCatalog.info(for: "Asia/Kolkata")!.abbreviation(at: utc("2026-01-15T12:00:00Z")) == "IST")
        // Dublin uses "negative DST" in the tz database; names must still match the season.
        let dublin = ZoneCatalog.info(for: "Europe/Dublin")!
        #expect(dublin.abbreviation(at: utc("2026-07-15T12:00:00Z")) == "IST")
        #expect(dublin.abbreviation(at: utc("2026-01-15T12:00:00Z")) == "GMT")
        // Zones without a real abbreviation show only the offset.
        let montevideo = ZoneCatalog.info(for: "America/Montevideo")!
        #expect(montevideo.abbreviation(at: utc("2026-01-15T12:00:00Z")) == nil)
        #expect(montevideo.offsetAndAbbreviation(at: utc("2026-01-15T12:00:00Z")) == "UTC\u{2212}3")
        #expect(ZoneCatalog.info(for: "Asia/Tokyo")!.offsetAndAbbreviation(at: utc("2026-01-15T12:00:00Z")) == "UTC+9 · JST")
    }
}

@Suite struct DayBoundaryTests {
    @Test func dayDifferenceLabels() {
        let t = utc("2026-01-15T02:00:00Z") // Montevideo: Jan 14 23:00
        let local = tz("America/Montevideo")
        #expect(ZoneMath.dayDifference(at: t, in: tz("Asia/Tokyo"), relativeTo: local) == 1)
        #expect(ZoneMath.dayDifference(at: t, in: tz("America/Los_Angeles"), relativeTo: local) == 0)
        #expect(ZoneMath.dayDifference(at: utc("2026-01-15T05:00:00Z"), in: tz("America/Los_Angeles"), relativeTo: tz("Asia/Tokyo")) == -1)
        #expect(ZoneMath.dayDifference(at: t, in: tz("Pacific/Kiritimati"), relativeTo: tz("Pacific/Pago_Pago")) == 1)
        #expect(ZoneMath.dayDifferenceLabel(1) == "+1 day")
        #expect(ZoneMath.dayDifferenceLabel(-1) == "\u{2212}1 day")
        #expect(ZoneMath.dayDifferenceLabel(0) == nil)
    }

    @Test func sliderCrossesMidnight() {
        let anchor = utc("2026-01-15T15:00:00Z") // Jan 15 in UTC
        // End of slider (1440) is midnight starting the next day.
        let end = ZoneMath.instant(minuteOfDay: 1440, onDayOf: anchor, in: tz("UTC"))
        #expect(end == utc("2026-01-16T00:00:00Z"))
        #expect(ZoneMath.minuteOfDay(end, relativeToDayOf: anchor, in: tz("UTC")) == 1440)
        #expect(ZoneMath.minuteOfDay(utc("2026-01-14T23:45:00Z"), relativeToDayOf: anchor, in: tz("UTC")) == -15)
        // Montevideo midnight -> Tokyo crosses to the next day as the slider moves.
        let m = model(now: anchor, zones: ["America/Montevideo", "Asia/Tokyo"])
        m.setSlider(minutes: 11 * 60, in: tz("America/Montevideo"), anchor: anchor) // 14:00Z = 23:00 Tokyo
        #expect(m.dayDifference(for: tz("Asia/Tokyo")) == 0)
        m.setSlider(minutes: 12 * 60, in: tz("America/Montevideo"), anchor: anchor) // 15:00Z = 00:00 Tokyo
        #expect(m.dayDifference(for: tz("Asia/Tokyo")) == 1)
        #expect(m.sliderMinutes(in: tz("Asia/Tokyo")) == 0)
    }

    @Test func offsetLabels() {
        let now = utc("2026-01-15T00:00:00Z")
        #expect(ZoneMath.offsetLabel(from: now, to: now.addingTimeInterval(3 * 3600 + 15 * 60)) == "+3h 15m")
        #expect(ZoneMath.offsetLabel(from: now, to: now.addingTimeInterval(-45 * 60)) == "\u{2212}45m")
        #expect(ZoneMath.offsetLabel(from: now, to: now.addingTimeInterval(26 * 3600)) == "+1d 2h")
    }
}

@Suite struct PersistenceTests {
    @Test func firstLaunchDefaultsToLocalZone() {
        let store = ZoneStore(defaults: freshDefaults(), localZone: { tz("Asia/Kathmandu") })
        #expect(store.loadZones() == ["Asia/Kathmandu"])
    }

    @Test func addRemoveMoveRoundTrip() {
        let defaults = freshDefaults()
        let store = ZoneStore(defaults: defaults, localZone: { tz("America/Montevideo") })
        let m = ComparisonModel(store: store, clock: Date.init, localZone: { tz("America/Montevideo") })
        #expect(m.isLocal("America/Montevideo"))
        m.add("Asia/Tokyo")
        m.add("Europe/London")
        m.add("Asia/Tokyo") // duplicate ignored
        m.add("Not/AZone")  // invalid ignored
        m.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(m.zoneIDs == ["Europe/London", "America/Montevideo", "Asia/Tokyo"])
        m.remove("America/Montevideo")
        m.use24Hour = false

        // A brand-new model on the same defaults sees the same state ("relaunch").
        let reloaded = ComparisonModel(store: ZoneStore(defaults: defaults), clock: Date.init)
        #expect(reloaded.zoneIDs == ["Europe/London", "Asia/Tokyo"])
        #expect(reloaded.use24Hour == false)
    }

    @Test func emptyListPersistsAndUnknownIDsDropped() {
        let defaults = freshDefaults()
        let store = ZoneStore(defaults: defaults)
        store.saveZones([])
        #expect(store.loadZones() == [])
        store.saveZones(["Asia/Tokyo", "Bogus/Zone"])
        #expect(store.loadZones() == ["Asia/Tokyo"])
    }
}

@Suite struct SearchTests {
    @Test(arguments: [("Tokyo", "Asia/Tokyo"), ("New York", "America/New_York"), ("montevideo", "America/Montevideo"),
                      ("sao paulo", "America/Sao_Paulo"), ("PST", "America/Los_Angeles"), ("CET", "Europe/Paris"),
                      ("JST", "Asia/Tokyo"), ("IST", "Asia/Calcutta"), ("Kathmandu", "Asia/Kathmandu"), ("Kolkata", "Asia/Calcutta"), ("calcutta", "Asia/Calcutta")])
    func firstResult(query: String, expected: String) {
        #expect(ZoneCatalog.search(query).first?.id == expected)
    }

    @Test func abbreviationAlsoListsOtherZonesUsingIt() {
        let ids = ZoneCatalog.search("CET").map(\.id)
        #expect(ids.contains("Europe/Berlin"))
        #expect(ids.contains("Europe/Madrid"))
    }

    @Test func catalogCoversAllKnownIdentifiers() {
        #expect(ZoneCatalog.all.count == TimeZone.knownTimeZoneIdentifiers.count)
        #expect(ZoneCatalog.search("").count == TimeZone.knownTimeZoneIdentifiers.count)
        #expect(ZoneCatalog.search("zzzzqx").isEmpty)
    }
}
