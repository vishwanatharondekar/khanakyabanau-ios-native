import XCTest
@testable import KhanaKit

/// Week keys are the primary key for every meal plan on the server, so an
/// off-by-one here silently writes into the wrong week.
final class WeekDatesTests: XCTestCase {

    private func date(_ iso: String) -> PlanDate {
        guard let date = PlanDate(iso: iso) else {
            XCTFail("Bad fixture date \(iso)")
            return PlanDate(year: 1970, month: 1, day: 1)
        }
        return date
    }

    // MARK: - PlanDate

    func testEpochRoundTrip() {
        XCTAssertEqual(PlanDate(epochDays: 0).isoString, "1970-01-01")
        for iso in ["1969-12-31", "2000-02-29", "2024-02-29", "2026-08-09", "2099-12-31"] {
            let parsed = date(iso)
            XCTAssertEqual(PlanDate(epochDays: parsed.epochDays).isoString, iso)
        }
    }

    func testDayOfWeekIsMondayIndexed() {
        XCTAssertEqual(date("1970-01-01").dayOfWeek, .thursday)
        XCTAssertEqual(date("2026-08-03").dayOfWeek, .monday)
        XCTAssertEqual(date("2026-08-09").dayOfWeek, .sunday)
        XCTAssertEqual(date("1969-12-29").dayOfWeek, .monday, "Negative epoch days must not skew")
    }

    func testArithmeticCrossesMonthYearAndLeapBoundaries() {
        XCTAssertEqual(date("2024-02-28").adding(days: 1).isoString, "2024-02-29")
        XCTAssertEqual(date("2023-02-28").adding(days: 1).isoString, "2023-03-01")
        XCTAssertEqual(date("2025-12-31").adding(days: 1).isoString, "2026-01-01")
        XCTAssertEqual(date("2026-01-01").adding(days: -1).isoString, "2025-12-31")
    }

    func testRejectsMalformedISOStrings() {
        XCTAssertNil(PlanDate(iso: ""))
        XCTAssertNil(PlanDate(iso: "2026-08"))
        XCTAssertNil(PlanDate(iso: "not-a-date"))
        XCTAssertNil(PlanDate(iso: "2026-13-01"))
    }

    // MARK: - Week maths

    func testMondayOfReturnsTheSameMondayForEveryDayOfThatWeek() {
        let expected = "2026-08-03"
        for offset in 0...6 {
            let day = date(expected).adding(days: offset)
            XCTAssertEqual(
                WeekDates.mondayOf(day).isoString, expected,
                "\(day.isoString) should map to \(expected)"
            )
        }
    }

    func testMondayOfAMondayIsItself() {
        XCTAssertEqual(WeekDates.mondayOf(date("2026-08-10")).isoString, "2026-08-10")
    }

    func testWeekShiftPreservesISOFormat() {
        XCTAssertEqual(WeekDates.shift(weekStartDate: "2026-08-03", byWeeks: 1), "2026-08-10")
        XCTAssertEqual(WeekDates.shift(weekStartDate: "2026-08-03", byWeeks: -1), "2026-07-27")
        XCTAssertEqual(WeekDates.shift(weekStartDate: "2026-01-05", byWeeks: -1), "2025-12-29")
    }

    /// The two label forms differ in spacing around the dash, deliberately.
    func testRangeLabelWithinOneMonth() {
        XCTAssertEqual(WeekDates.rangeLabel(weekStartDate: "2026-08-03"), "Aug 3–9, 2026")
    }

    func testRangeLabelAcrossTwoMonths() {
        XCTAssertEqual(WeekDates.rangeLabel(weekStartDate: "2026-07-27"), "Jul 27 – Aug 2, 2026")
    }

    func testRangeLabelAcrossAYearBoundaryUsesTheEndYear() {
        XCTAssertEqual(WeekDates.rangeLabel(weekStartDate: "2025-12-29"), "Dec 29 – Jan 4, 2026")
    }

    func testTodayAndTomorrowIndexes() {
        let week = "2026-08-03"
        XCTAssertEqual(WeekDates.todayIndex(in: week, today: date("2026-08-03")), 0)
        XCTAssertEqual(WeekDates.todayIndex(in: week, today: date("2026-08-06")), 3)
        XCTAssertEqual(WeekDates.todayIndex(in: week, today: date("2026-08-09")), 6)
        XCTAssertNil(WeekDates.todayIndex(in: week, today: date("2026-08-10")))
        XCTAssertNil(WeekDates.todayIndex(in: week, today: date("2026-08-02")))
    }

    /// On the Sunday of the displayed week, tomorrow belongs to next week — the
    /// Today screen has to fetch that week separately.
    func testTomorrowIndexFallsOffTheEndOnSunday() {
        let week = "2026-08-03"
        XCTAssertEqual(WeekDates.tomorrowIndex(in: week, today: date("2026-08-08")), 6)
        XCTAssertNil(WeekDates.tomorrowIndex(in: week, today: date("2026-08-09")))
    }

    func testDaysOfWeekPairsSevenDaysWithConsecutiveDates() {
        let days = WeekDates.daysOfWeek(from: date("2026-08-03"))
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.day, .monday)
        XCTAssertEqual(days.first?.date.isoString, "2026-08-03")
        XCTAssertEqual(days.last?.day, .sunday)
        XCTAssertEqual(days.last?.date.isoString, "2026-08-09")
    }

    /// Local midnight in a zone well ahead of UTC must not report yesterday.
    func testTodayUsesTheGivenTimeZoneRatherThanUTC() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        // 2026-08-06 20:00 UTC is already 2026-08-07 01:30 in Kolkata.
        let instant = Date(timeIntervalSince1970: 1_786_046_400)
        let utcDay = PlanDate.today(timeZone: TimeZone(identifier: "UTC")!, now: instant)
        let kolkataDay = PlanDate.today(timeZone: kolkata, now: instant)
        XCTAssertEqual(kolkataDay.epochDays - utcDay.epochDays, 1)
    }
}
