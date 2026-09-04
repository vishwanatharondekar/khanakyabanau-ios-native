import XCTest
@testable import KhanaKit

/// The worked examples mirror the shared design doc and the Kotlin PrepNowTest.
/// Dinner is nominally 20:00, so an 8-hour soak has to start at 12:00.
final class PrepNowTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: hour, minute: minute))!
    }

    private func meal(
        _ type: MealType, _ name: String, lead: Int, text: String = "Soak chana overnight"
    ) -> WidgetMeal {
        WidgetMeal(
            type: type, name: name, calories: nil, thumbnailKey: nil,
            prep: MealPrep(steps: [PrepStep(text: text, leadTimeMinutes: lead, category: .soak)])
        )
    }

    func testNothingShowsBeyondTheHorizon() {
        let due = PrepNow.due(
            today: [meal(.dinner, "Chana", lead: 480)], tomorrow: [],
            now: at(8), calendar: calendar
        )
        XCTAssertTrue(due.isEmpty)
    }

    func testAStepInsideTheHorizonShowsAsSoon() {
        let due = PrepNow.due(
            today: [meal(.dinner, "Chana", lead: 480)], tomorrow: [],
            now: at(11), calendar: calendar
        )
        XCTAssertEqual(due.count, 1)
        XCTAssertFalse(due[0].isOverdue)
        XCTAssertEqual(due[0].startAt, at(12))
    }

    func testAPassedStepShowsAsOverdue() {
        let due = PrepNow.due(
            today: [meal(.dinner, "Chana", lead: 480)], tomorrow: [],
            now: at(13), calendar: calendar
        )
        XCTAssertEqual(due.count, 1)
        XCTAssertTrue(due[0].isOverdue)
    }

    /// After dinner a soak that should have started at noon is nagging, not advice.
    func testAnOverdueStepDropsOnceItsMealHasPassed() {
        let due = PrepNow.due(
            today: [meal(.dinner, "Chana", lead: 480)], tomorrow: [],
            now: at(21), calendar: calendar
        )
        XCTAssertTrue(due.isEmpty)
    }

    /// The case a today-only banner would miss.
    func testTomorrowsPrepSurfacesThisEvening() {
        let due = PrepNow.due(
            today: [],
            tomorrow: [meal(.breakfast, "Dosa", lead: 14 * 60, text: "Ferment the dosa batter")],
            now: at(19), calendar: calendar
        )
        XCTAssertEqual(due.count, 1)
        XCTAssertTrue(due[0].isOverdue)
        XCTAssertEqual(due[0].item.step.text, "Ferment the dosa batter")
    }

    func testResultsAreOrderedByStartTime() {
        let thali = WidgetMeal(
            type: .dinner, name: "Thali", calories: nil, thumbnailKey: nil,
            prep: MealPrep(steps: [
                PrepStep(text: "Soak chana", leadTimeMinutes: 480, category: .soak),
                PrepStep(text: "Soak rajma", leadTimeMinutes: 420, category: .soak),
            ])
        )
        let due = PrepNow.due(today: [thali], tomorrow: [], now: at(13), calendar: calendar)
        XCTAssertEqual(due.map(\.item.step.text), ["Soak chana", "Soak rajma"])
    }

    func testAMealWithNoPrepContributesNothing() {
        let plain = WidgetMeal(
            type: .dinner, name: "Khichdi", calories: nil, thumbnailKey: nil, prep: nil
        )
        XCTAssertTrue(PrepNow.due(today: [plain], tomorrow: [], now: at(13), calendar: calendar).isEmpty)
    }
}
