import XCTest
@testable import KhanaKit

/// The snapshot crosses a process boundary, so its codec is the contract between
/// the app that writes it and an extension that cannot ask questions about it.
final class WidgetSnapshotTests: XCTestCase {

    private func meal(_ name: String, prep: MealPrep? = nil) -> Meal {
        var meal = Meal(name: name)
        meal.calories = 420
        meal.imageUrl = "https://example.test/\(name).jpg"
        meal.prep = prep
        meal.prepFor = prep == nil ? nil : name
        return meal
    }

    private var kolkata: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    func testRoundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: Date(timeIntervalSince1970: 1_780_000_000),
            days: [
                WidgetDay(day: .monday, date: "2026-09-07", meals: [
                    WidgetMeal(type: .breakfast, name: "Poha", calories: 300,
                               thumbnailKey: "poha.jpg", prep: nil),
                ]),
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    /// A meal with nothing optional set is the common case for a plan that has
    /// never been through image resolution or prep generation.
    func testRoundTripsAMealWithNoThumbnailCaloriesOrPrep() throws {
        let snapshot = WidgetSnapshot(
            isAuthenticated: false,
            writtenAt: Date(timeIntervalSince1970: 0),
            days: [
                WidgetDay(day: .sunday, date: "2026-09-06", meals: [
                    WidgetMeal(type: .dinner, name: "Khichdi", calories: nil,
                               thumbnailKey: nil, prep: nil),
                ]),
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
    }

    func testBuildsTodayAndTomorrowInThatOrder() {
        var plan = MealPlan(weekStartDate: "2026-08-31")
        plan.meals["friday"] = DayMeals(breakfast: meal("Poha"), dinner: meal("Dal"))
        plan.meals["saturday"] = DayMeals(lunch: meal("Rajma"))

        let snapshot = WidgetSnapshot.build(
            today: plan,
            tomorrow: plan,
            on: date("2026-09-04T09:00:00+05:30"),
            enabledTypes: [.breakfast, .lunch, .dinner],
            isAuthenticated: true,
            calendar: kolkata
        )

        XCTAssertEqual(snapshot.days.count, 2)
        XCTAssertEqual(snapshot.days[0].day, .friday)
        XCTAssertEqual(snapshot.days[1].day, .saturday)
        XCTAssertEqual(snapshot.days[0].date, "2026-09-04")
        XCTAssertEqual(snapshot.days[1].date, "2026-09-05")
    }

    /// The case Android calls out in `loadTomorrowSnapshot`: on a Sunday, tomorrow
    /// belongs to next week's plan, which is a different document.
    func testTomorrowComesFromTheSecondPlanAcrossAWeekRollover() {
        var thisWeek = MealPlan(weekStartDate: "2026-08-31")
        thisWeek.meals["sunday"] = DayMeals(dinner: meal("Sunday dinner"))
        var nextWeek = MealPlan(weekStartDate: "2026-09-07")
        nextWeek.meals["monday"] = DayMeals(breakfast: meal("Monday breakfast"))

        let snapshot = WidgetSnapshot.build(
            today: thisWeek,
            tomorrow: nextWeek,
            on: date("2026-09-06T20:00:00+05:30"),
            enabledTypes: [.breakfast, .dinner],
            isAuthenticated: true,
            calendar: kolkata
        )

        XCTAssertEqual(snapshot.days[0].meals.map(\.name), ["Sunday dinner"])
        XCTAssertEqual(snapshot.days[1].meals.map(\.name), ["Monday breakfast"])
    }

    func testDisabledMealTypesAreLeftOut() {
        var plan = MealPlan(weekStartDate: "2026-08-31")
        plan.meals["friday"] = DayMeals(breakfast: meal("Poha"), lunch: meal("Rajma"))

        let snapshot = WidgetSnapshot.build(
            today: plan, tomorrow: plan,
            on: date("2026-09-04T09:00:00+05:30"),
            enabledTypes: [.breakfast],
            isAuthenticated: true, calendar: kolkata
        )

        XCTAssertEqual(snapshot.days[0].meals.map(\.type), [.breakfast])
    }

    func testEmptySlotsAreLeftOut() {
        var plan = MealPlan(weekStartDate: "2026-08-31")
        plan.meals["friday"] = DayMeals(breakfast: meal("Poha"), lunch: Meal(name: "   "))

        let snapshot = WidgetSnapshot.build(
            today: plan, tomorrow: plan,
            on: date("2026-09-04T09:00:00+05:30"),
            enabledTypes: [.breakfast, .lunch],
            isAuthenticated: true, calendar: kolkata
        )

        XCTAssertEqual(snapshot.days[0].meals.map(\.name), ["Poha"])
    }

    /// Prep whose `prepFor` no longer matches the dish is stale — the same rule
    /// `Meal.validPrep` applies everywhere else, so the widget cannot disagree
    /// with the app about what needs soaking.
    func testOnlyValidPrepSurvives() {
        var stale = meal("Rajma", prep: MealPrep(steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)]))
        stale.prepFor = "Something else entirely"
        var plan = MealPlan(weekStartDate: "2026-08-31")
        plan.meals["friday"] = DayMeals(breakfast: stale)

        let snapshot = WidgetSnapshot.build(
            today: plan, tomorrow: plan,
            on: date("2026-09-04T09:00:00+05:30"),
            enabledTypes: [.breakfast],
            isAuthenticated: true, calendar: kolkata
        )

        XCTAssertNil(snapshot.days[0].meals[0].prep)
    }

    func testHasAnyMealReflectsContent() {
        XCTAssertFalse(WidgetDay(day: .monday, date: "2026-09-07", meals: []).hasAnyMeal)
        XCTAssertTrue(
            WidgetDay(day: .monday, date: "2026-09-07", meals: [
                WidgetMeal(type: .breakfast, name: "Poha", calories: nil, thumbnailKey: nil, prep: nil),
            ]).hasAnyMeal
        )
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = kolkata.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }
}
