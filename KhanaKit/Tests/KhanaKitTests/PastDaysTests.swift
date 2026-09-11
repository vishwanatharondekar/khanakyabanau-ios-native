import XCTest
@testable import KhanaKit

/// Port-parity tests for `pastDaysInWeek`. Mirrors the webapp's
/// `lib/past-days.ts`; when in doubt, that file is the specification.
final class PastDaysTests: XCTestCase {

    private let week = "2026-09-07" // Monday

    func testAFutureWeekHasNoPastDays() {
        XCTAssertEqual(pastDaysInWeek("2026-09-14", today: PlanDate(iso: "2026-09-08")!), [])
    }

    func testAWeekWhollyGoneHasAllSeven() {
        XCTAssertEqual(
            pastDaysInWeek("2026-08-31", today: PlanDate(iso: "2026-09-08")!),
            DayOfWeek.allCases
        )
    }

    func testMidWeekTheDaysBeforeTodayArePast() {
        // Thursday the 10th.
        XCTAssertEqual(
            pastDaysInWeek(week, today: PlanDate(iso: "2026-09-10")!),
            [.monday, .tuesday, .wednesday]
        )
    }

    func testTodayIsNeverPastThereIsStillDinnerToCook() {
        XCTAssertFalse(isPastDay(week, day: .thursday, today: PlanDate(iso: "2026-09-10")!))
    }

    func testOnMondayNothingIsPastYet() {
        XCTAssertEqual(pastDaysInWeek(week, today: PlanDate(iso: "2026-09-07")!), [])
    }

    func testOnSundaySixDaysArePast() {
        let sunday = PlanDate(iso: "2026-09-13")!
        XCTAssertEqual(pastDaysInWeek(week, today: sunday).count, 6)
        XCTAssertTrue(isPastDay(week, day: .saturday, today: sunday))
        XCTAssertFalse(isPastDay(week, day: .sunday, today: sunday))
    }
}
