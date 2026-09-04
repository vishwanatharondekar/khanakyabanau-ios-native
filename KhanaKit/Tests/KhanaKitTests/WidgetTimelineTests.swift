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

        XCTAssertEqual(dates, [now, date("2026-09-05T00:00:00+05:30")])
    }

    func testDuplicateBoundariesCollapse() {
        let now = date("2026-09-04T09:00:00+05:30")
        let noon = date("2026-09-04T12:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [noon, noon],
            calendar: calendar
        )

        XCTAssertEqual(dates, [now, noon, date("2026-09-05T00:00:00+05:30")])
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
}
