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
        let noon = date("2026-09-04T12:00:00+05:30")
        let evening = date("2026-09-04T17:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [evening, noon],
            calendar: calendar
        )

        XCTAssertEqual(dates, [now, noon, evening, date("2026-09-05T00:00:00+05:30")])
    }

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

        // 17:00 is the pivot, which `entryDates` adds itself.
        XCTAssertEqual(dates, [
            now,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ])
    }

    func testDuplicateBoundariesCollapse() {
        let now = date("2026-09-04T09:00:00+05:30")
        let noon = date("2026-09-04T12:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [noon, noon],
            calendar: calendar
        )

        XCTAssertEqual(dates, [
            now, noon,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ])
    }

    /// The midnight entry must survive the cap; without it the widget freezes on
    /// yesterday's menu until something else reloads it.
    func testTheCapKeepsNowAndMidnight() {
        let now = date("2026-09-04T09:00:00+05:30")
        let boundaries = (10...20).map { date(String(format: "2026-09-04T%02d:00:00+05:30", $0)) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: boundaries,
            calendar: calendar,
            limit: 4
        )

        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
    }

    // MARK: - The pivot

    /// The pivot is the entry that turns the widget over to tomorrow, so
    /// `entryDates` puts it there itself rather than trusting every caller to
    /// remember. A provider that forgot would leave the widget showing today's
    /// plan all evening, and nothing would fail loudly.
    func testThePivotIsAnEntryWithoutTheCallerPassingIt() {
        let now = date("2026-09-04T09:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates, [
            now,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ])
    }

    func testThePivotIsNotAnEntryOnceItHasPassed() {
        let now = date("2026-09-04T19:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates, [now, date("2026-09-05T00:00:00+05:30")])
    }

    /// A caller passing the pivot as a prep boundary must not double it —
    /// WidgetKit rejects duplicate entry dates.
    func testAPivotPassedAsABoundaryIsNotDuplicated() {
        let now = date("2026-09-04T09:00:00+05:30")
        let pivot = date("2026-09-04T17:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [pivot], calendar: calendar
        )

        XCTAssertEqual(dates, [now, pivot, date("2026-09-05T00:00:00+05:30")])
    }

    /// The failure this guards is silent and total: a day with more prep
    /// boundaries than the cap would push the pivot off the end, and the widget
    /// would never turn over to tomorrow.
    func testTheCapNeverDropsThePivot() {
        let now = date("2026-09-04T06:00:00+05:30")
        // Twenty half-hourly boundaries, all before 17:00.
        let boundaries = (1...20).map { now.addingTimeInterval(Double($0) * 1800) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: boundaries, calendar: calendar
        )

        XCTAssertTrue(
            dates.contains(date("2026-09-04T17:00:00+05:30")),
            "the pivot was capped away — the widget would show today's plan all evening"
        )
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
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
