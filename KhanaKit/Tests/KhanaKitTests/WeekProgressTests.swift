import XCTest
@testable import KhanaKit

final class WeekProgressTests: XCTestCase {

    private let allDays = Set(DayOfWeek.allCases)

    func testAWhollyEmptyWeekIsMostlyUnplanned() {
        XCTAssertTrue(isMostlyUnplanned(plannedDays: [], pastDays: []))
    }

    func testAWhollyPlannedWeekIsNot() {
        XCTAssertFalse(isMostlyUnplanned(plannedDays: allDays, pastDays: []))
    }

    func testFourOfSevenDaysEmptyIsStillMostlyUnplanned() {
        XCTAssertTrue(
            isMostlyUnplanned(plannedDays: [.monday, .tuesday, .wednesday], pastDays: [])
        )
    }

    func testThreeOfSevenDaysEmptyIsNotThatIsAWeekWithGaps() {
        XCTAssertFalse(
            isMostlyUnplanned(
                plannedDays: [.monday, .tuesday, .wednesday, .thursday],
                pastDays: []
            )
        )
    }

    func testDaysAlreadyGoneAreNotCountedAsNeedingFilling() {
        // Thursday signup: Mon-Wed are blank and always will be. Thu-Sun are
        // planned, so there is nothing left to fill and no hero.
        XCTAssertFalse(
            isMostlyUnplanned(
                plannedDays: [.thursday, .friday, .saturday, .sunday],
                pastDays: [.monday, .tuesday, .wednesday]
            )
        )
    }

    func testMidWeekWithMostOfTheRemainderBlankStillOffersToFill() {
        // Of Thu-Sun only Thursday is planned: three of four still blank.
        XCTAssertTrue(
            isMostlyUnplanned(
                plannedDays: [.thursday],
                pastDays: [.monday, .tuesday, .wednesday]
            )
        )
    }

    func testExactlyHalfTheRemainderBlankIsNotMostlyUnplanned() {
        // Saturday planned, Sunday not — one of two.
        XCTAssertFalse(
            isMostlyUnplanned(
                plannedDays: [.saturday],
                pastDays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            )
        )
    }

    func testAWeekThatHasWhollyHappenedOffersNothing() {
        XCTAssertFalse(isMostlyUnplanned(plannedDays: [], pastDays: allDays))
    }
}
