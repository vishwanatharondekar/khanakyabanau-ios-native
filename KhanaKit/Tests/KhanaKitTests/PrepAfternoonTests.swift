import XCTest
@testable import KhanaKit

/// Mirrors the worked examples in the web app's `lib/prep-afternoon.test.ts` and
/// Android's `PrepAfternoonTest`. A disagreement here means the app and the
/// reminder tell the user different things.
final class PrepAfternoonTests: XCTestCase {

    private func meal(
        _ name: String,
        steps: [PrepStep],
        prepFor: String? = nil
    ) -> Meal {
        Meal(
            name: name,
            prep: MealPrep(
                steps: steps,
                maxLeadTimeMinutes: steps.map(\.leadTimeMinutes).max() ?? 0
            ),
            prepFor: prepFor ?? name
        )
    }

    private func soak(_ leadTimeMinutes: Int, _ text: String = "Do the thing") -> PrepStep {
        PrepStep(text: text, leadTimeMinutes: leadTimeMinutes, category: .soak)
    }

    // MARK: - Inclusions

    func testTenHourFermentForDinnerStartsAtTen() {
        let day = DayMeals(dinner: meal("Dosa", steps: [soak(600, "Ferment batter")]))
        let items = PrepAfternoon.itemsForThisAfternoon(day)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.startByMinutes, 600)
        XCTAssertEqual(items.first?.mealType, .dinner)
    }

    func testEightHourSoakForDinnerStartsAtNoon() {
        let day = DayMeals(dinner: meal("Chole", steps: [soak(480, "Soak chana")]))
        XCTAssertEqual(PrepAfternoon.itemsForThisAfternoon(day).first?.startByMinutes, 720)
    }

    func testSixHourSoakForEveningSnackStartsAtEleven() {
        let day = DayMeals(eveningSnack: meal("Sabudana Vada", steps: [soak(360, "Soak sabudana")]))
        let items = PrepAfternoon.itemsForThisAfternoon(day)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.startByMinutes, 660)
        XCTAssertEqual(items.first?.mealType, .eveningSnack)
    }

    /// Dinner 20:00 minus 13 h = 07:00 exactly. Pins the inclusive lower bound.
    func testExactlySevenAMIsIncluded() {
        let day = DayMeals(dinner: meal("Chole", steps: [soak(780)]))
        XCTAssertEqual(PrepAfternoon.itemsForThisAfternoon(day).first?.startByMinutes, 420)
    }

    // MARK: - Exclusions

    /// Pins the strict greater-than: exactly four hours is cooking-time prep.
    func testExactlyFourHoursIsExcluded() {
        let day = DayMeals(dinner: meal("Tikka", steps: [
            PrepStep(text: "Thaw chicken", leadTimeMinutes: 240, category: .thaw)
        ]))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testLongLeadDinnerPrepBelongsToTheEveningReminder() {
        let day = DayMeals(dinner: meal("Chole", steps: [soak(840)]))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testLongLeadEveningSnackPrepBelongsToTheEveningReminder() {
        let day = DayMeals(eveningSnack: meal("Sabudana Vada", steps: [soak(660)]))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    /// Lunch 13:00 minus 5 h = 08:00 — past the cutoff and lead over 240, so only
    /// the explicit meal list keeps it out.
    func testLunchIsExcludedDespiteSatisfyingBothBounds() {
        let day = DayMeals(lunch: meal("Rajma", steps: [soak(300)]))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testBreakfastAndMorningSnackAreExcluded() {
        XCTAssertTrue(
            PrepAfternoon.itemsForThisAfternoon(DayMeals(breakfast: meal("Poha", steps: [soak(300)]))).isEmpty
        )
        XCTAssertTrue(
            PrepAfternoon.itemsForThisAfternoon(DayMeals(morningSnack: meal("Chai", steps: [soak(300)]))).isEmpty
        )
    }

    func testShortMarinadeNeverQualifies() {
        let day = DayMeals(dinner: meal("Tikka", steps: [
            PrepStep(text: "Marinate", leadTimeMinutes: 30, category: .marinate)
        ]))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testStalePrepIsIgnored() {
        let day = DayMeals(dinner: meal("Poha", steps: [soak(480)], prepFor: "Chole"))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testGeneratedButEmptyPrepYieldsNothing() {
        let day = DayMeals(dinner: meal("Poha", steps: []))
        XCTAssertTrue(PrepAfternoon.itemsForThisAfternoon(day).isEmpty)
    }

    func testDisabledMealTypesAreSkipped() {
        let day = DayMeals(
            eveningSnack: meal("Sabudana Vada", steps: [soak(360)]),
            dinner: meal("Chole", steps: [soak(480)])
        )
        let items = PrepAfternoon.itemsForThisAfternoon(day, enabledTypes: [.dinner])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.dish, "Chole")
    }

    func testEveryStepIsConsideredIndependently() {
        let day = DayMeals(dinner: meal("Biryani", steps: [
            soak(480, "Soak rice"),
            PrepStep(text: "Marinate", leadTimeMinutes: 30, category: .marinate),
        ]))
        let items = PrepAfternoon.itemsForThisAfternoon(day)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.step.leadTimeMinutes, 480)
    }

    // MARK: - Ordering and copy

    func testItemsAreOrderedMostUrgentFirst() {
        let day = DayMeals(
            eveningSnack: meal("Sabudana Vada", steps: [soak(360)]),
            dinner: meal("Chole", steps: [soak(480)])
        )
        XCTAssertEqual(
            PrepAfternoon.itemsForThisAfternoon(day).map(\.dish),
            ["Sabudana Vada", "Chole"]
        )
    }

    func testSingleItemCopy() {
        let day = DayMeals(dinner: meal("Chole", steps: [soak(480, "Soak chana")]))
        let copy = PrepAfternoon.buildAfternoonReminderCopy(
            items: PrepAfternoon.itemsForThisAfternoon(day)
        )
        XCTAssertEqual(copy.title, "Prep this afternoon")
        XCTAssertEqual(copy.body, "Chole: Soak chana")
        XCTAssertEqual(copy.lines, ["Soak chana — Chole"])
    }

    func testMultiItemCopy() {
        let day = DayMeals(
            eveningSnack: meal("Sabudana Vada", steps: [soak(360, "Soak sabudana")]),
            dinner: meal("Chole", steps: [soak(480, "Soak chana")])
        )
        let copy = PrepAfternoon.buildAfternoonReminderCopy(
            items: PrepAfternoon.itemsForThisAfternoon(day)
        )
        XCTAssertEqual(copy.title, "2 things to prep this afternoon")
        XCTAssertEqual(copy.body, "Soak sabudana — Sabudana Vada")
        XCTAssertEqual(copy.lines.count, 2)
    }
}
