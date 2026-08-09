import XCTest
@testable import KhanaKit

/// Meal-planner state transitions. These rules decide whether a user loses
/// calorie counts and AI-generated prep, so each branch is pinned.
final class MealPlanTests: XCTestCase {

    private let week = "2026-08-03"

    private func planWithRajma() -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(
            lunch: Meal(
                name: "Rajma",
                calories: 400,
                prep: MealPrep(
                    steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
                    maxLeadTimeMinutes: 480
                ),
                prepFor: "Rajma",
                videoUrl: "https://youtu.be/abcdefghijk"
            )
        )
        return plan
    }

    // MARK: - withMeal

    func testSavingAnUnchangedNameKeepsCaloriesPrepAndVideo() {
        let updated = planWithRajma().withMeal(day: .monday, type: .lunch, name: "Rajma")
        let meal = updated[.monday, .lunch]
        XCTAssertEqual(meal.calories, 400)
        XCTAssertNotNil(meal.prep)
        XCTAssertEqual(meal.videoUrl, "https://youtu.be/abcdefghijk")
    }

    func testWhitespaceOnlyDifferenceCountsAsUnchanged() {
        let updated = planWithRajma().withMeal(day: .monday, type: .lunch, name: "  Rajma  ")
        XCTAssertEqual(updated[.monday, .lunch].calories, 400)
    }

    func testGenuineRenameDropsCaloriesPrepAndVideo() {
        let updated = planWithRajma().withMeal(day: .monday, type: .lunch, name: "Chole")
        let meal = updated[.monday, .lunch]
        XCTAssertEqual(meal.name, "Chole")
        XCTAssertNil(meal.calories)
        XCTAssertNil(meal.prep)
        XCTAssertNil(meal.videoUrl)
    }

    func testClearingASlotEmptiesIt() {
        let updated = planWithRajma().withMeal(day: .monday, type: .lunch, name: "")
        XCTAssertTrue(updated[.monday, .lunch].isEmpty)
    }

    func testSuppliedImageIsCarriedOntoARename() {
        let updated = planWithRajma()
            .withMeal(day: .monday, type: .lunch, name: "Chole", imageUrl: "chole.jpg")
        XCTAssertEqual(updated[.monday, .lunch].imageUrl, "chole.jpg")
    }

    func testUnchangedNameKeepsItsExistingImageWhenNoneIsSupplied() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(lunch: Meal(name: "Rajma", imageUrl: "rajma.jpg"))
        let updated = plan.withMeal(day: .monday, type: .lunch, name: "Rajma")
        XCTAssertEqual(updated[.monday, .lunch].imageUrl, "rajma.jpg")
    }

    // MARK: - mergingFillingEmpty

    func testGenerationOnlyFillsEmptySlots() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(breakfast: Meal(name: "Poha"), lunch: Meal(name: ""))

        let generated = [
            "monday": DayMeals(breakfast: Meal(name: "Dosa"), lunch: Meal(name: "Rajma")),
        ]
        let merged = plan.mergingFillingEmpty(with: generated)

        XCTAssertEqual(merged[.monday, .breakfast].name, "Poha", "A user's dish is never replaced")
        XCTAssertEqual(merged[.monday, .lunch].name, "Rajma")
    }

    func testGenerationIgnoresDaysItDidNotReturn() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["tuesday"] = DayMeals(lunch: Meal(name: "Idli"))
        let merged = plan.mergingFillingEmpty(with: ["monday": DayMeals(lunch: Meal(name: "Dosa"))])
        XCTAssertEqual(merged[.tuesday, .lunch].name, "Idli")
        XCTAssertEqual(merged[.monday, .lunch].name, "Dosa")
    }

    func testGenerationDoesNotFillWithBlankNames() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals()
        let merged = plan.mergingFillingEmpty(with: ["monday": DayMeals(lunch: Meal(name: ""))])
        XCTAssertTrue(merged[.monday, .lunch].isEmpty)
    }

    // MARK: - withPrepFrom

    func testPrepMergesOnlyOntoMatchingDishesAndLeavesImagesAlone() {
        var local = MealPlan.empty(weekStartDate: week)
        local.meals["monday"] = DayMeals(
            breakfast: Meal(name: "Poha", imageUrl: "poha.jpg"),
            lunch: Meal(name: "Rajma", imageUrl: "rajma.jpg")
        )

        var fresh = MealPlan.empty(weekStartDate: week)
        let prep = MealPrep(
            steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
            maxLeadTimeMinutes: 480
        )
        fresh.meals["monday"] = DayMeals(
            // A different breakfast: its prep must not cross over.
            breakfast: Meal(name: "Upma", prep: prep, prepFor: "Upma"),
            lunch: Meal(name: "Rajma", prep: prep, prepFor: "Rajma")
        )

        let merged = local.withPrepFrom(fresh)
        XCTAssertNil(merged[.monday, .breakfast].prep)
        XCTAssertNotNil(merged[.monday, .lunch].prep)
        XCTAssertEqual(
            merged[.monday, .breakfast].imageUrl, "poha.jpg",
            "Merging prep must never disturb resolved images"
        )
        XCTAssertEqual(merged[.monday, .lunch].imageUrl, "rajma.jpg")
        XCTAssertEqual(merged[.monday, .breakfast].name, "Poha", "Names come from local state")
    }

    // MARK: - Images

    func testWithImagesMatchesOnLowercasedNamesAndSkipsResolvedSlots() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(
            breakfast: Meal(name: "Poha"),
            lunch: Meal(name: "Rajma", imageUrl: "existing.jpg")
        )
        let updated = plan.withImages(["poha": "poha.jpg", "rajma": "new.jpg"])
        XCTAssertEqual(updated[.monday, .breakfast].imageUrl, "poha.jpg")
        XCTAssertEqual(
            updated[.monday, .lunch].imageUrl, "existing.jpg",
            "An already-resolved image is not overwritten"
        )
    }

    func testMealNamesMissingImagesIsDedupedAndSkipsEmptySlots() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(breakfast: Meal(name: "Poha"), lunch: Meal(name: ""))
        plan.meals["tuesday"] = DayMeals(breakfast: Meal(name: "Poha"))
        XCTAssertEqual(plan.mealNamesMissingImages(), ["Poha"])
    }

    func testNormalizingImageURLsLeavesAbsoluteOnesAlone() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(
            breakfast: Meal(name: "Poha", imageUrl: "poha.jpg"),
            lunch: Meal(name: "Rajma", imageUrl: "https://cdn.example/rajma.jpg")
        )
        let updated = plan.normalizingImageURLs(MealImageURLs.absolutize)
        XCTAssertEqual(
            updated[.monday, .breakfast].imageUrl,
            "https://d3rj590miwbz96.cloudfront.net/meals-data/images/poha.jpg"
        )
        XCTAssertEqual(updated[.monday, .lunch].imageUrl, "https://cdn.example/rajma.jpg")
    }

    func testAllDishNamesSkipsEmptySlots() {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(breakfast: Meal(name: "Poha"), lunch: Meal(name: ""))
        plan.meals["tuesday"] = DayMeals(dinner: Meal(name: "Khichdi"))
        XCTAssertEqual(plan.allDishNames(), ["Poha", "Khichdi"])
    }

    // MARK: - Meal settings

    func testMealTypesAreAlwaysSortedChronologically() {
        XCTAssertEqual(
            MealType.sorted([.dinner, .breakfast, .eveningSnack, .lunch]),
            [.breakfast, .lunch, .eveningSnack, .dinner]
        )
    }

    func testEnabledTypesIgnoresUnknownKeysAndReordersStoredOnes() {
        let settings = MealSettings(enabledMealTypes: ["dinner", "brunch", "breakfast"])
        XCTAssertEqual(settings.enabledTypes, [.breakfast, .dinner])
    }

    func testFallbackMealSettingsMatchTheServerDefault() {
        XCTAssertEqual(MealSettings.fallback.enabledMealTypes, ["breakfast", "lunch", "dinner"])
    }
}
