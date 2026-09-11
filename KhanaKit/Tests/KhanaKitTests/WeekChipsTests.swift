import XCTest
@testable import KhanaKit

/// Port-parity tests for `buildWeekChips`. Mirrors the webapp's
/// `lib/week-chips.ts`; when in doubt, that file is the specification.
final class WeekChipsTests: XCTestCase {

    // A Tuesday. Its Monday is the 7th, next Monday is the 14th.
    private let tuesday = PlanDate(iso: "2026-09-08")!

    func testAlwaysOffersThisWeekAndNextInThatOrder() {
        let chips = buildWeekChips(today: tuesday, weeksWithPlans: [])

        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].weekStartDate, "2026-09-07")
        XCTAssertEqual(chips[0].label, "This week")
        XCTAssertEqual(chips[0].kind, .thisWeek)
        XCTAssertEqual(chips[1].weekStartDate, "2026-09-14")
        XCTAssertEqual(chips[1].label, "Next week")
        XCTAssertEqual(chips[1].kind, .nextWeek)
    }

    func testAMondayIsItsOwnWeekStart() {
        let chips = buildWeekChips(today: PlanDate(iso: "2026-09-07")!, weeksWithPlans: [])
        XCTAssertEqual(chips[0].weekStartDate, "2026-09-07")
    }

    func testASundayStillBelongsToTheWeekThatStartedOnMonday() {
        let chips = buildWeekChips(today: PlanDate(iso: "2026-09-13")!, weeksWithPlans: [])
        XCTAssertEqual(chips[0].weekStartDate, "2026-09-07")
    }

    func testWeeksFurtherOutThatHoldAPlanGetADatedChip() {
        let chips = buildWeekChips(
            today: tuesday,
            weeksWithPlans: ["2026-09-28", "2026-09-21"]
        )

        XCTAssertEqual(chips.count, 4)
        XCTAssertEqual(chips.dropFirst(2).map(\.weekStartDate), ["2026-09-21", "2026-09-28"])
        XCTAssertEqual(chips.dropFirst(2).map(\.label), ["21 Sep", "28 Sep"])
        XCTAssertTrue(chips.dropFirst(2).allSatisfy { $0.kind == .dated })
    }

    func testNeverDuplicatesTheTwoFixedChips() {
        let chips = buildWeekChips(
            today: tuesday,
            weeksWithPlans: ["2026-09-07", "2026-09-14"]
        )
        XCTAssertEqual(chips.count, 2)
    }

    func testPastWeeksWithPlansAreNotOfferedTheStripIsForwardOnly() {
        let chips = buildWeekChips(
            today: tuesday,
            weeksWithPlans: ["2026-08-31", "2026-07-06"]
        )
        XCTAssertEqual(chips.count, 2)
    }

    func testDuplicatesCollapse() {
        let chips = buildWeekChips(
            today: tuesday,
            weeksWithPlans: ["2026-09-21", "2026-09-21"]
        )
        XCTAssertEqual(chips.count, 3)
    }

    func testAMalformedWeekFromTheApiDoesNotTakeTheStripDown() {
        let chips = buildWeekChips(
            today: tuesday,
            weeksWithPlans: ["not-a-date", "2026-09-21"]
        )
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips[2].weekStartDate, "2026-09-21")
    }

    func testAWeekWithNoChipIsOffRails() {
        let chips = buildWeekChips(today: tuesday, weeksWithPlans: [])
        XCTAssertTrue(isOffRails("2026-03-02", in: chips))
        XCTAssertFalse(isOffRails("2026-09-07", in: chips))
        XCTAssertFalse(isOffRails("2026-09-14", in: chips))
    }
}
