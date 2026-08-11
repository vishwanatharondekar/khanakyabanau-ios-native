import XCTest
@testable import KhanaKit

/// The afternoon reminder fires on the day it describes, not the evening before.
final class PrepReminderPlannerAfternoonTests: XCTestCase {

    private func soakMeal(_ name: String, _ leadTimeMinutes: Int) -> Meal {
        Meal(
            name: name,
            prep: MealPrep(
                steps: [PrepStep(text: "Soak", leadTimeMinutes: leadTimeMinutes, category: .soak)],
                maxLeadTimeMinutes: leadTimeMinutes
            ),
            prepFor: name
        )
    }

    /// A plan whose every day carries an 8-hour dinner soak — startBy 12:00, so
    /// squarely inside the afternoon band.
    private func planWithDinnerSoak(weekStartDate: String, lead: Int = 480) -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: weekStartDate)
        for (day, _) in WeekDates.daysOfWeek(from: PlanDate(iso: weekStartDate)!) {
            plan.meals[day.key] = DayMeals(dinner: soakMeal("Chole", lead))
        }
        return plan
    }

    func testWeekKeysIncludeTodaysWeekWhenStartingAtZero() {
        // 2026-08-10 is a Monday, so today's week key is its own date.
        let monday = PlanDate(iso: "2026-08-10")!
        let fromTomorrow = PrepReminderPlanner.weekKeys(from: monday)
        let fromToday = PrepReminderPlanner.weekKeys(from: monday, startOffset: 0)
        XCTAssertTrue(fromToday.contains("2026-08-10"))
        XCTAssertEqual(fromTomorrow.first, "2026-08-10")
        // Deviation from the task brief's verbatim assertion here — see the task
        // report for the full justification. The brief additionally asserted
        // `fromToday.count >= fromTomorrow.count`, reasoning that starting earlier
        // should reach at least as many weeks. That does not hold for a Monday
        // `now`: both windows span exactly `horizonDays` (7) days, just shifted by
        // one offset. `fromToday` (offsets 0..<7, Mon..Sun) sits flush against the
        // week boundary and collapses to exactly one key, while `fromTomorrow`
        // (offsets 1..<8, Tue..Mon) straddles the next Monday and yields two — the
        // same two keys the pre-existing, currently-green
        // `testHorizonFromMondayNeedsTwoWeeks` asserts. So
        // `fromToday.count (1) >= fromTomorrow.count (2)` is false by construction,
        // independent of implementation. The two assertions above already cover the
        // brief's actual "critical detail": that `startOffset: 0` reaches today's
        // week.
    }

    func testAfternoonReminderFiresOnTheTargetDay() {
        let now = PlanDate(iso: "2026-08-10")!
        let reminders = PrepReminderPlanner.afternoonReminders(
            plans: [planWithDinnerSoak(weekStartDate: "2026-08-10")],
            from: now,
            hour: 11,
            currentHour: 9
        )
        XCTAssertFalse(reminders.isEmpty)
        let today = reminders.first { $0.targetDate == now }
        XCTAssertNotNil(today)
        // The distinguishing assertion: same day, not the evening before.
        XCTAssertEqual(today?.fireDate, today?.targetDate)
    }

    func testTodaysAfternoonReminderIsSkippedOnceItsHourHasPassed() {
        let now = PlanDate(iso: "2026-08-10")!
        let reminders = PrepReminderPlanner.afternoonReminders(
            plans: [planWithDinnerSoak(weekStartDate: "2026-08-10")],
            from: now,
            hour: 11,
            currentHour: 13
        )
        XCTAssertNil(reminders.first { $0.targetDate == now })
        // Later days are unaffected.
        XCTAssertFalse(reminders.isEmpty)
    }

    func testCopyMatchesTheAfternoonWording() {
        let reminders = PrepReminderPlanner.afternoonReminders(
            plans: [planWithDinnerSoak(weekStartDate: "2026-08-10")],
            from: PlanDate(iso: "2026-08-10")!,
            hour: 11,
            currentHour: 9
        )
        XCTAssertEqual(reminders.first?.title, "Prep this afternoon")
        XCTAssertEqual(reminders.first?.body, "Chole: Soak")
    }

    func testLongLeadPrepProducesNoAfternoonReminder() {
        XCTAssertTrue(
            PrepReminderPlanner.afternoonReminders(
                plans: [planWithDinnerSoak(weekStartDate: "2026-08-10", lead: 840)],
                from: PlanDate(iso: "2026-08-10")!,
                hour: 11,
                currentHour: 9
            ).isEmpty
        )
    }
}
