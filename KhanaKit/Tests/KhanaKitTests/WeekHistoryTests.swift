import XCTest
@testable import KhanaKit

/// Port-parity tests for week history. Mirrors the webapp's
/// `lib/week-history.ts`; when in doubt, that file is the specification.
final class WeekHistoryTests: XCTestCase {

    // A Tuesday; its Monday is the 7th.
    private let today = PlanDate(iso: "2026-09-08")!

    func testAWeekBeforeThisOneHasPassed() {
        XCTAssertTrue(isPastWeek("2026-08-31", today: today))
    }

    func testTheCurrentWeekHasNotPassedOnAnyDayOfIt() {
        XCTAssertFalse(isPastWeek("2026-09-07", today: today))
        XCTAssertFalse(isPastWeek("2026-09-07", today: PlanDate(iso: "2026-09-13")!))
    }

    func testAFutureWeekHasNotPassed() {
        XCTAssertFalse(isPastWeek("2026-09-14", today: today))
    }

    func testEarlierWeekStartsWalkBackAWeekAtATimeNearestFirst() {
        XCTAssertEqual(
            earlierWeekStarts("2026-09-07", count: 3),
            ["2026-08-31", "2026-08-24", "2026-08-17"]
        )
    }

    func testTheHorizonIsTwelveWeeksMatchingTheApisBoundedKeyLookup() {
        XCTAssertEqual(earlierHorizon, 12)
        XCTAssertEqual(earlierWeekStarts("2026-09-07").count, 12)
    }

    func testSteppingBackSkipsWeeksWithNoPlan() {
        // Nothing was cooked in the two weeks before last.
        XCTAssertEqual(
            nearestEarlierWeekWithPlan("2026-09-07", in: ["2026-08-10", "2026-07-20"]),
            "2026-08-10"
        )
    }

    func testTheOldestWeekHasNothingBeforeIt() {
        XCTAssertNil(
            nearestEarlierWeekWithPlan("2026-07-20", in: ["2026-08-10", "2026-07-20"])
        )
    }

    func testNoHistoryAtAllMeansNoStepBack() {
        XCTAssertNil(nearestEarlierWeekWithPlan("2026-09-07", in: []))
    }
}
