import XCTest
@testable import KhanaKit

/// WidgetKit allows roughly 40–70 timeline reloads a day, so anything that changes
/// on a clock has to be an *entry date* rather than a reload. These pin the dates.
final class WidgetTimelineTests: XCTestCase {

    /// Fixed zone: the day boundary is the whole point, and .current would make
    /// this pass or fail depending on where it runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }


    /// Every phase boundary still ahead today — each meal's cutoff plus the
    /// pivot. `entryDates` adds these itself, so tests assert around them rather
    /// than hard-coding a list that changes whenever a meal time does.
    private func phaseBoundaries(after now: Date) -> [Date] {
        WidgetPhase.boundaries(on: now, calendar: calendar)
            .filter { $0 > now && $0 < WidgetTimeline.nextMidnight(after: now, calendar: calendar) }
    }

    func testTheFirstEntryIsAlwaysNow() {
        let now = date("2026-09-04T14:30:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates.first, now)
    }

    func testTheLastEntryIsTheNextMidnight() {
        let now = date("2026-09-04T14:30:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
    }

    /// Without this the widget schedules an entry for the instant it is already
    /// rendering and then has nothing after it.
    func testMidnightIsStrictlyAfterAMidnightInput() {
        let midnight = date("2026-09-04T00:00:00+05:30")

        let next = WidgetTimeline.nextMidnight(after: midnight, calendar: calendar)

        XCTAssertEqual(next, date("2026-09-05T00:00:00+05:30"))
    }

    func testExtraBoundariesAreIncludedInOrder() {
        let now = date("2026-09-04T09:00:00+05:30")
        let prep = date("2026-09-04T12:30:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [prep], calendar: calendar
        )

        let expected = ([now] + phaseBoundaries(after: now) + [prep]).sorted()
            + [date("2026-09-05T00:00:00+05:30")]
        XCTAssertEqual(dates, expected)
    }

    /// Tomorrow's boundaries belong to the timeline built after the rollover, and
    /// a boundary already behind us would render an entry the system skips.
    /// Tomorrow's boundaries belong to the timeline built after the rollover, and
    /// a boundary already behind us would render an entry the system skips.
    func testBoundariesOutsideTodayAreDropped() {
        let now = date("2026-09-04T09:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [
                date("2026-09-04T08:00:00+05:30"),
                date("2026-09-05T10:00:00+05:30"),
            ],
            calendar: calendar
        )

        XCTAssertEqual(
            dates,
            [now] + phaseBoundaries(after: now) + [date("2026-09-05T00:00:00+05:30")]
        )
    }

    func testDuplicateBoundariesCollapse() {
        let now = date("2026-09-04T09:00:00+05:30")
        let prep = date("2026-09-04T12:30:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [prep, prep], calendar: calendar
        )

        XCTAssertEqual(dates.count, Set(dates).count, "duplicate entry dates are rejected by WidgetKit")
        XCTAssertEqual(dates.filter { $0 == prep }.count, 1)
    }

    /// The midnight entry must survive the cap; without it the widget freezes on
    /// yesterday's menu until something else reloads it.
    /// The midnight entry must survive the cap; without it the widget freezes on
    /// yesterday's menu until something else reloads it.
    func testTheCapKeepsNowAndMidnight() {
        let now = date("2026-09-04T09:00:00+05:30")
        let boundaries = (10...20).map { date(String(format: "2026-09-04T%02d:15:00+05:30", $0)) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: boundaries, calendar: calendar, limit: 8
        )

        XCTAssertLessThanOrEqual(dates.count, 8)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
    }

    // MARK: - The pivot

    /// The pivot is the entry that turns the widget over to tomorrow, so
    /// `entryDates` puts it there itself rather than trusting every caller to
    /// remember. A provider that forgot would leave the widget showing today's
    /// plan all evening, and nothing would fail loudly.
    /// The caller never passes these. A provider that forgot to would leave the
    /// widget offering breakfast at lunchtime, and nothing would fail loudly.
    func testPhaseBoundariesAreEntriesWithoutTheCallerPassingThem() {
        let now = date("2026-09-04T06:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        for boundary in phaseBoundaries(after: now) {
            XCTAssertTrue(dates.contains(boundary), "missing boundary \(boundary)")
        }
    }

    func testPassedBoundariesAreNotEntries() {
        let now = date("2026-09-04T19:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertFalse(dates.contains(date("2026-09-04T14:00:00+05:30")))
        XCTAssertTrue(dates.contains(date("2026-09-04T21:00:00+05:30")), "dinner's cutoff is still ahead")
    }

    /// A caller passing the pivot as a prep boundary must not double it —
    /// WidgetKit rejects duplicate entry dates.
    func testAPhaseBoundaryPassedByTheCallerIsNotDuplicated() {
        let now = date("2026-09-04T09:00:00+05:30")
        let pivot = date("2026-09-04T14:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [pivot], calendar: calendar
        )

        XCTAssertEqual(dates.filter { $0 == pivot }.count, 1)
    }

    /// The failure this guards is silent and total: a day with more prep
    /// boundaries than the cap would push the pivot off the end, and the widget
    /// would never turn over to tomorrow.
    /// Prep boundaries are expendable under the cap — they are already legible on
    /// their own meal's row. Phase boundaries are not: losing one freezes the
    /// widget in a state it can never leave.
    func testTheCapNeverDropsAPhaseBoundary() {
        let now = date("2026-09-04T06:00:00+05:30")
        let noise = (7...23).map { date(String(format: "2026-09-04T%02d:07:00+05:30", $0)) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: noise, calendar: calendar, limit: 8
        )

        for boundary in phaseBoundaries(after: now) {
            XCTAssertTrue(dates.contains(boundary), "the cap dropped \(boundary)")
        }
    }

    /// Twelve, per the spec: enough for a heavy prep day, few enough that an
    /// unusual week cannot generate an unbounded timeline.
    func testTheDefaultCapIsTwelve() {
        let now = date("2026-09-04T06:00:00+05:30")
        let boundaries = (1...30).map { now.addingTimeInterval(Double($0) * 900) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: boundaries, calendar: calendar
        )

        XCTAssertEqual(dates.count, 12)
    }
}
