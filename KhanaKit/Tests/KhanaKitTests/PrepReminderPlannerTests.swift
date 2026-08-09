import XCTest
@testable import KhanaKit

/// The rules behind the phone's own prep reminders.
///
/// Pure by construction — the planner takes the date and the hour rather than
/// reading a clock — so every case here is exact rather than "whatever today is".
final class PrepReminderPlannerTests: XCTestCase {

    // 2026-08-10 is a Monday, so 2026-08-09 is the Sunday before it.
    private let sunday = PlanDate(iso: "2026-08-09")!
    private let monday = PlanDate(iso: "2026-08-10")!

    private func soak(_ dish: String, minutes: Int = 480) -> Meal {
        Meal(
            name: dish,
            prep: MealPrep(
                steps: [PrepStep(text: "Soak \(dish.lowercased())",
                                 leadTimeMinutes: minutes, category: .soak)],
                maxLeadTimeMinutes: minutes
            ),
            prepFor: dish
        )
    }

    /// A plan for the week of 2026-08-10 with `dish` on the given date.
    private func plan(dish: Meal, on date: PlanDate) -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: "2026-08-10")
        plan.meals[date.dayOfWeek.key] = DayMeals(lunch: dish)
        return plan
    }

    // MARK: - Which weeks have to be fetched

    /// From a Sunday the whole horizon lands inside the coming week, so one fetch.
    func testHorizonFromSundayNeedsOneWeek() {
        XCTAssertEqual(PrepReminderPlanner.weekKeys(from: sunday), ["2026-08-10"])
    }

    /// From a Monday it straddles the next Monday, so two — and no more.
    func testHorizonFromMondayNeedsTwoWeeks() {
        XCTAssertEqual(
            PrepReminderPlanner.weekKeys(from: monday),
            ["2026-08-10", "2026-08-17"]
        )
    }

    func testWeekKeysAreDeduplicatedAndOrdered() {
        let keys = PrepReminderPlanner.weekKeys(from: PlanDate(iso: "2026-08-12")!)
        XCTAssertEqual(keys, ["2026-08-10", "2026-08-17"])
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: - What gets scheduled

    /// The reminder is for tomorrow, so it fires tonight.
    func testReminderFiresTheEveningBeforeItsDay() {
        let tuesday = PlanDate(iso: "2026-08-11")!
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: tuesday)],
            from: sunday, hour: 21, currentHour: 9
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.targetDate, tuesday)
        XCTAssertEqual(reminders.first?.fireDate, monday)
        XCTAssertEqual(reminders.first?.title, "Prep tonight for tomorrow")
        XCTAssertEqual(reminders.first?.body, "Rajma: Soak rajma")
    }

    /// Tonight's own reminder is still worth setting before the chosen hour…
    func testTonightIsScheduledWhenItsHourHasNotPassed() {
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: monday)],
            from: sunday, hour: 21, currentHour: 20
        )
        XCTAssertEqual(reminders.map(\.fireDate), [sunday])
    }

    /// …and pointless after it. iOS would silently drop a trigger in the past, but
    /// this keeps the pending list honest about what will actually arrive.
    func testTonightIsSkippedOnceItsHourHasPassed() {
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: monday)],
            from: sunday, hour: 21, currentHour: 21
        )
        XCTAssertTrue(reminders.isEmpty)
    }

    func testDaysWithNoPrepProduceNoReminder() {
        let tuesday = PlanDate(iso: "2026-08-11")!
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: Meal(name: "Poha"), on: tuesday)],
            from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertTrue(reminders.isEmpty, "A dish with no prep must not be reminded about")
    }

    /// Only prep for courses the user actually eats.
    func testDisabledMealTypesAreIgnored() {
        let tuesday = PlanDate(iso: "2026-08-11")!
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: tuesday)],
            from: sunday, hour: 21, currentHour: 9,
            enabledTypes: [.breakfast, .dinner]
        )
        XCTAssertTrue(reminders.isEmpty)
    }

    // MARK: - The horizon

    /// The last day inside the horizon is included…
    func testTheFarEdgeOfTheHorizonIsIncluded() {
        let sundayNext = PlanDate(iso: "2026-08-16")!   // fires Saturday, offset 6
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: sundayNext)],
            from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertEqual(reminders.map(\.fireDate), [PlanDate(iso: "2026-08-15")!])
    }

    /// …and the first day beyond it is not, so nothing is scheduled for a plan the
    /// app may not have seen the final version of.
    func testBeyondTheHorizonIsNotScheduled() {
        var plan = MealPlan.empty(weekStartDate: "2026-08-17")
        let mondayNext = PlanDate(iso: "2026-08-17")!   // would fire Sunday, offset 7
        plan.meals[mondayNext.dayOfWeek.key] = DayMeals(lunch: soak("Rajma"))

        let reminders = PrepReminderPlanner.reminders(
            plans: [plan], from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertTrue(reminders.isEmpty)
    }

    func testHorizonIsAWeek() {
        XCTAssertEqual(
            PrepReminderPlanner.horizonDays, 7,
            "The horizon is what decides how often the app must be opened"
        )
    }

    // MARK: - Shape of the result

    /// Two weeks are fetched at once near a Monday; their reminders must interleave
    /// in date order rather than in fetch order.
    func testRemindersAreOrderedByTheEveningTheyFire() {
        var thisWeek = MealPlan.empty(weekStartDate: "2026-08-10")
        thisWeek.meals[PlanDate(iso: "2026-08-13")!.dayOfWeek.key] = DayMeals(lunch: soak("Rajma"))
        var nextWeek = MealPlan.empty(weekStartDate: "2026-08-17")
        nextWeek.meals[PlanDate(iso: "2026-08-17")!.dayOfWeek.key] = DayMeals(lunch: soak("Chana"))

        let reminders = PrepReminderPlanner.reminders(
            plans: [nextWeek, thisWeek], from: monday, hour: 21, currentHour: 9
        )
        XCTAssertEqual(
            reminders.map(\.fireDate),
            [PlanDate(iso: "2026-08-12")!, PlanDate(iso: "2026-08-16")!]
        )
    }

    /// A day covered by two plans must not stack two notifications on one evening.
    func testOverlappingPlansYieldOneReminderPerDay() {
        let tuesday = PlanDate(iso: "2026-08-11")!
        let reminders = PrepReminderPlanner.reminders(
            plans: [plan(dish: soak("Rajma"), on: tuesday),
                    plan(dish: soak("Chana"), on: tuesday)],
            from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.body, "Rajma: Soak rajma", "The first plan wins")
    }

    /// Several items on one day read as a count, matching the server's push.
    func testMultipleItemsShareOneReminder() {
        let tuesday = PlanDate(iso: "2026-08-11")!
        var plan = MealPlan.empty(weekStartDate: "2026-08-10")
        plan.meals[tuesday.dayOfWeek.key] = DayMeals(
            breakfast: soak("Idli", minutes: 720), lunch: soak("Rajma")
        )

        let reminders = PrepReminderPlanner.reminders(
            plans: [plan], from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "2 things to prep tonight")
        XCTAssertEqual(reminders.first?.lines.count, 2)
        XCTAssertEqual(reminders.first?.body, "For Tuesday: \(reminders[0].lines[0])")
    }

    /// A garbled week key can't be allowed to take the whole schedule down.
    func testAnUnparseableWeekIsSkipped() {
        var broken = MealPlan.empty(weekStartDate: "not-a-date")
        broken.meals["tuesday"] = DayMeals(lunch: soak("Rajma"))

        let reminders = PrepReminderPlanner.reminders(
            plans: [broken, plan(dish: soak("Chana"), on: PlanDate(iso: "2026-08-11")!)],
            from: sunday, hour: 21, currentHour: 9
        )
        XCTAssertEqual(reminders.map(\.body), ["Chana: Soak chana"])
    }
}
