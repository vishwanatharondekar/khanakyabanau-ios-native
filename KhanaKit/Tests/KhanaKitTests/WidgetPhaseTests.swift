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

    private let allTypes: [MealType] = [.breakfast, .lunch, .dinner]

    private func upcoming(_ hour: Int, _ minute: Int = 0) -> [MealType] {
        WidgetPhase.upcoming(
            allTypes,
            at: date(String(format: "2026-09-04T%02d:%02d:00+05:30", hour, minute), kolkata),
            calendar: kolkata
        )
    }

    private func phase(_ hour: Int, _ minute: Int = 0) -> WidgetPhase.Phase {
        let at = date(String(format: "2026-09-04T%02d:%02d:00+05:30", hour, minute), kolkata)
        return WidgetPhase.phase(
            remainingToday: WidgetPhase.upcoming(allTypes, at: at, calendar: kolkata),
            at: at,
            calendar: kolkata
        )
    }

    // The four windows, pinned at their edges. Each meal survives an hour past
    // its nominal time, so nobody loses a meal they are running late for.

    func testBeforeNineShowsAllThree() {
        XCTAssertEqual(upcoming(6), [.breakfast, .lunch, .dinner])
        XCTAssertEqual(upcoming(8, 59), [.breakfast, .lunch, .dinner])
        XCTAssertEqual(phase(8, 59), .today)
    }

    func testNineToTwoDropsBreakfast() {
        XCTAssertEqual(upcoming(9), [.lunch, .dinner])
        XCTAssertEqual(upcoming(13, 59), [.lunch, .dinner])
        XCTAssertEqual(phase(9), .today)
        XCTAssertEqual(phase(13, 59), .today)
    }

    func testTwoToNineIsDinnerAndTomorrow() {
        XCTAssertEqual(upcoming(14), [.dinner])
        XCTAssertEqual(upcoming(20, 59), [.dinner])
        XCTAssertEqual(phase(14), .tonight)
        XCTAssertEqual(phase(20, 59), .tonight)
    }

    func testAfterNineIsTomorrowOnly() {
        XCTAssertEqual(upcoming(21), [])
        XCTAssertEqual(phase(21), .tomorrow)
        XCTAssertEqual(phase(23, 30), .tomorrow)
    }

    /// A meal is still worth showing while someone might be about to cook it.
    /// Dropping dinner at its nominal 20:00 would hide it from everyone who eats
    /// at half past.
    func testEachMealSurvivesAnHourPastItsNominalTime() {
        XCTAssertTrue(upcoming(8, 30).contains(.breakfast), "breakfast at 08:30")
        XCTAssertTrue(upcoming(13, 30).contains(.lunch), "lunch at 13:30")
        XCTAssertTrue(upcoming(20, 30).contains(.dinner), "dinner at 20:30")
    }

    /// The snack slots get the same grace, without being named anywhere.
    func testSnacksFollowTheSameRule() {
        let types: [MealType] = [.morningSnack, .eveningSnack]
        let at = date("2026-09-04T12:30:00+05:30", kolkata)
        // morningSnack is nominally 11:00, so it is gone by 12:00.
        XCTAssertEqual(WidgetPhase.upcoming(types, at: at, calendar: kolkata), [.eveningSnack])
    }

    /// Nothing enabled that is still ahead means tomorrow, whatever the hour.
    func testAnEarlyFinisherReachesTomorrowBeforeThePivot() {
        let at = date("2026-09-04T10:00:00+05:30", kolkata)
        XCTAssertEqual(
            WidgetPhase.phase(remainingToday: [], at: at, calendar: kolkata), .tomorrow
        )
    }

    func testThePivotIsTwoPmLocal() {
        let pivot = WidgetPhase.pivot(on: date("2026-09-04T09:00:00+05:30", kolkata), calendar: kolkata)
        XCTAssertEqual(pivot, date("2026-09-04T14:00:00+05:30", kolkata))
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
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)

        // And the arithmetic version really would have been wrong.
        let naive = newYork.startOfDay(for: morning).addingTimeInterval(14 * 3600)
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
