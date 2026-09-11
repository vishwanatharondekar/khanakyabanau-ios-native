import XCTest
@testable import KhanaKit

/// Today's agenda is `WidgetPhase` applied to the screen. These tests pin the
/// boundaries the widget already documents — breakfast until 09:00, lunch until
/// 14:00, dinner until 21:00 — so the screen and the widget can never drift.
final class TodayAgendaTests: XCTestCase {

    private let allMeals = MealType.allCases

    private func agenda(
        at hour: Int,
        _ minute: Int = 0,
        types: [MealType]? = nil
    ) -> TodayAgenda {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 11
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components)!
        return todayAgenda(enabledTypes: types ?? allMeals, at: date)
    }

    func testEveryMealTypeHasANominalTime() {
        // todayAgenda splits on WidgetPhase.upcoming, which can only place a
        // meal it can time. A type without one would fall silently into
        // `earlier` and be collapsed out of sight on a screen it belongs on.
        let untimed = MealType.allCases.filter { PrepTonight.nominalMealTimes[$0] == nil }
        XCTAssertEqual(untimed, [])
    }

    func testFirstThingInTheMorningNothingHasGoneYet() {
        let a = agenda(at: 7)
        XCTAssertEqual(a.earlier, [])
        XCTAssertEqual(a.upcoming, allMeals)
        XCTAssertEqual(a.upNext, .breakfast)
        XCTAssertEqual(a.phase, .today)
    }

    func testBreakfastSurvivesItsGraceHour() {
        // Nominal 08:00, so it is still up next at 08:59.
        XCTAssertEqual(agenda(at: 8, 59).upNext, .breakfast)
        XCTAssertEqual(agenda(at: 9, 1).upNext, .morningSnack)
    }

    func testMidMorningBreakfastIsEarlierAndTheSnackIsNext() {
        let a = agenda(at: 10)
        XCTAssertEqual(a.earlier, [.breakfast])
        XCTAssertEqual(a.upNext, .morningSnack)
        XCTAssertFalse(a.isDayDone)
    }

    func testAfterLunchTheDayPivotsToTonight() {
        // Lunch is nominal 13:00, gone at 14:00 — which is also the pivot.
        let a = agenda(at: 14, 30)
        XCTAssertTrue(a.earlier.contains(.lunch))
        XCTAssertEqual(a.upNext, .eveningSnack)
        XCTAssertEqual(a.phase, .tonight)
    }

    func testDinnerIsStillUpNextAtHalfPastEight() {
        let a = agenda(at: 20, 30)
        XCTAssertEqual(a.upNext, .dinner)
        XCTAssertEqual(a.phase, .tonight)
    }

    func testOnceDinnerHasGoneTheDayIsDone() {
        let a = agenda(at: 21, 30)
        XCTAssertEqual(a.earlier, allMeals)
        XCTAssertEqual(a.upcoming, [])
        XCTAssertNil(a.upNext)
        XCTAssertTrue(a.isDayDone)
        XCTAssertEqual(a.phase, .tomorrow)
    }

    func testABreakfastOnlyHouseholdIsDoneLongBeforeTheEveningPivot() {
        let a = agenda(at: 10, types: [.breakfast])
        XCTAssertTrue(a.isDayDone)
        XCTAssertEqual(a.phase, .tomorrow)
    }

    func testCoursesTheUserTurnedOffAppearInNeitherList() {
        let a = agenda(at: 10, types: [.breakfast, .dinner])
        XCTAssertEqual(a.earlier, [.breakfast])
        XCTAssertEqual(a.upcoming, [.dinner])
    }

    func testEarlierIsInTheDaysOrderHoweverTheCallerOrderedItsList() {
        let a = agenda(at: 18, types: [.lunch, .breakfast, .morningSnack])
        XCTAssertEqual(a.earlier, [.breakfast, .morningSnack, .lunch])
    }
}
