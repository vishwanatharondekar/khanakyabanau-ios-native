import XCTest
@testable import KhanaKit

/// The widget shows today or tomorrow depending on the time, so these pin the
/// one boundary that decision turns on.
final class WidgetPhaseTests: XCTestCase {

    private var kolkata: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ iso: String, _ calendar: Calendar) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private let allTypes: [MealType] = [.breakfast, .lunch, .eveningSnack, .dinner]

    /// Several meals still ahead: the day is in front of you.
    func testMorningWithMealsAheadIsTheTodayPhase() {
        XCTAssertEqual(
            WidgetPhase.phase(
                remainingToday: [.breakfast, .lunch, .dinner],
                at: date("2026-09-04T09:00:00+05:30", kolkata), calendar: kolkata
            ),
            .today
        )
    }

    /// Past the pivot with dinner still to come: dinner, plus a look at tomorrow.
    func testAfterThePivotWithDinnerLeftIsTonight() {
        XCTAssertEqual(
            WidgetPhase.phase(
                remainingToday: [.dinner],
                at: date("2026-09-04T18:00:00+05:30", kolkata), calendar: kolkata
            ),
            .tonight
        )
    }

    /// Nothing left to cook: stop showing today at all.
    ///
    /// Driven by what remains rather than by the clock, so a household that has
    /// only breakfast enabled moves on at 08:00 rather than waiting for a dinner
    /// they were never going to cook.
    func testNothingLeftTodayIsTheTomorrowPhase() {
        XCTAssertEqual(
            WidgetPhase.phase(
                remainingToday: [],
                at: date("2026-09-04T21:00:00+05:30", kolkata), calendar: kolkata
            ),
            .tomorrow
        )
    }

    func testAnEarlyFinisherReachesTomorrowBeforeThePivot() {
        XCTAssertEqual(
            WidgetPhase.phase(
                remainingToday: [],
                at: date("2026-09-04T10:00:00+05:30", kolkata), calendar: kolkata
            ),
            .tomorrow
        )
    }

    /// Before the pivot the widget stays on today even when only dinner is left:
    /// at 14:00 tomorrow is not yet the more useful thing to look at.
    func testOnlyDinnerLeftBeforeThePivotIsStillToday() {
        XCTAssertEqual(
            WidgetPhase.phase(
                remainingToday: [.dinner],
                at: date("2026-09-04T14:00:00+05:30", kolkata), calendar: kolkata
            ),
            .today
        )
    }

    /// The whole point of the change: by mid-afternoon, breakfast and lunch are
    /// history and the widget should not be spending rows on them.
    func testAfternoonCullsBreakfastAndLunch() {
        let upcoming = WidgetPhase.upcoming(
            allTypes, at: date("2026-09-04T14:00:00+05:30", kolkata), calendar: kolkata
        )
        XCTAssertEqual(upcoming, [.eveningSnack, .dinner])
    }

    func testThePivotIsFivePmLocal() {
        let pivot = WidgetPhase.pivot(on: date("2026-09-04T09:00:00+05:30", kolkata), calendar: kolkata)
        XCTAssertEqual(pivot, date("2026-09-04T17:00:00+05:30", kolkata))
    }

    /// The bug a naive `startOfDay + 17 * 3600` ships.
    ///
    /// On 8 March 2026 New York springs forward at 02:00, so midnight plus
    /// seventeen hours of *elapsed time* is 18:00 on the wall clock. The widget
    /// would switch to tomorrow an hour late, and on the autumn transition an hour
    /// early. Setting the hour on the calendar is the only correct way.
    func testThePivotSurvivesASpringForward() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        let morning = date("2026-03-08T09:00:00-05:00", newYork)
        let pivot = WidgetPhase.pivot(on: morning, calendar: newYork)

        let components = newYork.dateComponents([.hour, .minute], from: pivot)
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 0)

        // And the arithmetic version really would have been wrong.
        let naive = newYork.startOfDay(for: morning).addingTimeInterval(17 * 3600)
        XCTAssertNotEqual(naive, pivot)
    }

    func testUpcomingKeepsOnlyMealsStillAhead() {
        let evening = date("2026-09-04T18:00:00+05:30", kolkata)

        let upcoming = WidgetPhase.upcoming(
            [.breakfast, .lunch, .eveningSnack, .dinner],
            at: evening,
            calendar: kolkata
        )

        // breakfast 08:00 and lunch 13:00 are behind; eveningSnack 17:00 is too.
        XCTAssertEqual(upcoming, [.dinner])
    }

    func testUpcomingIsEmptyOnceDinnerHasPassed() {
        let lateNight = date("2026-09-04T22:00:00+05:30", kolkata)

        XCTAssertTrue(
            WidgetPhase.upcoming([.breakfast, .dinner], at: lateNight, calendar: kolkata).isEmpty
        )
    }

    func testUpcomingPreservesChronologicalOrder() {
        let dawn = date("2026-09-04T06:00:00+05:30", kolkata)

        let upcoming = WidgetPhase.upcoming([.dinner, .breakfast, .lunch], at: dawn, calendar: kolkata)

        XCTAssertEqual(upcoming, [.breakfast, .lunch, .dinner])
    }
}
