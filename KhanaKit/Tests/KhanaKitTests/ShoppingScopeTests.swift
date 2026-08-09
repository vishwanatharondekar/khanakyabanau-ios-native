import XCTest
@testable import KhanaKit

/// `ShoppingScope` is a line-by-line port of `lib/shopping-list-scope.ts`. These
/// tests are the contract that keeps the three clients producing the same list.
final class ShoppingScopeTests: XCTestCase {

    private func date(_ iso: String) -> PlanDate { PlanDate(iso: iso)! }

    private let categorized: [String: [Ingredient]] = [
        "Vegetables": [Ingredient(name: "Onion", amount: 300, unit: "g")],
        "Grains & Pulses": [Ingredient(name: "Rajma", amount: 200, unit: "g")],
    ]

    private let dayWise: [String: [String: MealIngredients]] = [
        "monday": [
            "lunch": MealIngredients(
                name: "Rajma Chawal",
                ingredients: [
                    Ingredient(name: "Onion", amount: 100, unit: "g"),
                    Ingredient(name: "Rajma", amount: 200, unit: "g"),
                ]
            ),
        ],
        "tuesday": [
            "dinner": MealIngredients(
                name: "Pulao",
                ingredients: [Ingredient(name: "onion", amount: 900, unit: "g")]
            ),
        ],
    ]

    // MARK: - Normalisation

    func testNormalizationTrimsAndLowercases() {
        XCTAssertEqual(ShoppingScope.normalizeIngredientName("  Toor Dal "), "toor dal")
    }

    func testTitleCaseNormalisesShoutingInput() {
        XCTAssertEqual(ShoppingScope.titleCaseIngredient("toor DAL"), "Toor Dal")
    }

    // MARK: - Unit maths

    func testGramsSumAsGrams() {
        let total = ShoppingScope.sumAmounts([
            IngredientAmount(amount: 200, unit: "g"),
            IngredientAmount(amount: 400, unit: "g"),
        ])
        XCTAssertEqual(total, IngredientAmount(amount: 600, unit: "g"))
    }

    func testGramsRollOverIntoKilogramsAtExactlyOneThousand() {
        XCTAssertEqual(
            ShoppingScope.sumAmounts([IngredientAmount(amount: 1000, unit: "g")]),
            IngredientAmount(amount: 1, unit: "kg")
        )
        XCTAssertEqual(
            ShoppingScope.sumAmounts([IngredientAmount(amount: 999, unit: "g")]),
            IngredientAmount(amount: 999, unit: "g")
        )
    }

    func testKilogramsAreSummedInGramsThenConvertedBack() {
        let total = ShoppingScope.sumAmounts([
            IngredientAmount(amount: 1, unit: "kg"),
            IngredientAmount(amount: 500, unit: "g"),
        ])
        XCTAssertEqual(total, IngredientAmount(amount: 1.5, unit: "kg"))
    }

    func testLongUnitNamesAreTreatedAsWeights() {
        let total = ShoppingScope.sumAmounts([
            IngredientAmount(amount: 500, unit: "grams"),
            IngredientAmount(amount: 1, unit: "kilogram"),
        ])
        XCTAssertEqual(total, IngredientAmount(amount: 1.5, unit: "kg"))
    }

    /// The first non-weight unit resets the running total — mixing grams and
    /// pieces has no meaningful sum, so the later unit wins outright.
    func testFirstNonWeightUnitResetsTheTotal() {
        let total = ShoppingScope.sumAmounts([
            IngredientAmount(amount: 200, unit: "g"),
            IngredientAmount(amount: 3, unit: "pieces"),
        ])
        XCTAssertEqual(total, IngredientAmount(amount: 3, unit: "pieces"))
    }

    func testSubsequentNonWeightUnitsAccumulate() {
        let total = ShoppingScope.sumAmounts([
            IngredientAmount(amount: 2, unit: "ml"),
            IngredientAmount(amount: 3, unit: "ml"),
        ])
        XCTAssertEqual(total, IngredientAmount(amount: 5, unit: "ml"))
    }

    func testEmptyInputSumsToNil() {
        XCTAssertNil(ShoppingScope.sumAmounts([]))
    }

    func testAmountFormattingMatchesJavaScriptNumberRendering() {
        XCTAssertEqual(ShoppingScope.formatAmount(IngredientAmount(amount: 600, unit: "g")), "600 g")
        XCTAssertEqual(ShoppingScope.formatAmount(IngredientAmount(amount: 1.2, unit: "kg")), "1.2 kg")
        XCTAssertEqual(ShoppingScope.formatAmount(IngredientAmount(amount: 1500, unit: "g")), "1.5 kg")
        XCTAssertEqual(ShoppingScope.formatAmount(nil), "")
    }

    // MARK: - Default scope

    func testCurrentWeekScopesTodayPlusTwoDays() {
        XCTAssertEqual(
            ShoppingScope.computeDefaultScopeDays(
                weekStartDate: "2026-08-03", today: date("2026-08-05")
            ),
            [.wednesday, .thursday, .friday]
        )
    }

    func testScopeIsClampedAtSunday() {
        XCTAssertEqual(
            ShoppingScope.computeDefaultScopeDays(
                weekStartDate: "2026-08-03", today: date("2026-08-08")
            ),
            [.saturday, .sunday]
        )
        XCTAssertEqual(
            ShoppingScope.computeDefaultScopeDays(
                weekStartDate: "2026-08-03", today: date("2026-08-09")
            ),
            [.sunday]
        )
    }

    func testFutureWeekScopesItsFirstThreeDays() {
        XCTAssertEqual(
            ShoppingScope.computeDefaultScopeDays(
                weekStartDate: "2026-08-17", today: date("2026-08-05")
            ),
            [.monday, .tuesday, .wednesday]
        )
    }

    func testPastWeekScopesTheWholeWeek() {
        XCTAssertEqual(
            ShoppingScope.computeDefaultScopeDays(
                weekStartDate: "2026-07-20", today: date("2026-08-05")
            ).count,
            7
        )
    }

    // MARK: - Aggregation

    func testAggregationMergesCaseVariantsAndKeepsPresentationOrder() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [.monday, .tuesday], categorized: categorized
        )
        XCTAssertEqual(scoped.categorized.map(\.name), ["Vegetables", "Grains & Pulses"])

        let onion = scoped.categorized.first?.items.first
        XCTAssertEqual(onion?.name, "Onion", "The first-seen spelling is the display name")
        XCTAssertEqual(onion?.unit, "kg")
        XCTAssertEqual(onion?.amount, 1.0, "100 g + 900 g rolls over into kilograms")
    }

    func testNarrowingTheScopeRecomputesQuantities() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [.monday], categorized: categorized
        )
        XCTAssertEqual(scoped.categorized.first?.items.first?.amount, 100)
        XCTAssertEqual(scoped.categorized.first?.items.first?.unit, "g")
    }

    func testAnEmptyScopeProducesNothing() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [], categorized: categorized
        )
        XCTAssertTrue(scoped.categorized.isEmpty)
    }

    /// Legacy cached documents predate the per-day breakdown.
    func testLegacyDocumentsWithoutDayWiseFallBackToTheFullWeek() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: [:], selectedDays: [.monday], categorized: categorized
        )
        XCTAssertEqual(scoped.categorized.map(\.name), ["Vegetables", "Grains & Pulses"])
        XCTAssertEqual(scoped.categorized.first?.items.first?.amount, 300)
    }

    func testUnknownCategoriesSortAfterTheKnownOnes() {
        let withUnknown = categorized.merging(
            ["Bakery": [Ingredient(name: "Pav", amount: 6, unit: "pieces")]]
        ) { current, _ in current }
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: [:], selectedDays: [], categorized: withUnknown
        )
        XCTAssertEqual(scoped.categorized.last?.name, "Bakery")
    }

    func testIngredientMealMapIsInDayOrderAndDeduplicated() {
        let map = ShoppingScope.buildIngredientMealMap(dayWise: dayWise)
        XCTAssertEqual(map["onion"], ["Rajma Chawal", "Pulao"])
        XCTAssertEqual(map["rajma"], ["Rajma Chawal"])
    }

    // MARK: - Labels and export

    func testScopeLabelForms() {
        XCTAssertEqual(
            ShoppingScope.formatScopeLabel(
                weekStartDate: "2026-08-03", selectedDays: [.monday, .tuesday, .wednesday]
            ),
            "Aug 3 – Aug 5"
        )
        XCTAssertEqual(
            ShoppingScope.formatScopeLabel(weekStartDate: "2026-08-03", selectedDays: [.monday]),
            "Aug 3"
        )
        XCTAssertEqual(
            ShoppingScope.formatScopeLabel(
                weekStartDate: "2026-08-03", selectedDays: [.monday, .wednesday]
            ),
            "Aug 3, Aug 5"
        )
        XCTAssertEqual(
            ShoppingScope.formatScopeLabel(weekStartDate: "2026-08-03", selectedDays: []),
            ""
        )
    }

    func testShareTextIsGroupedByCategory() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [.monday], categorized: categorized
        )
        let text = ShoppingScope.buildShareText(
            scoped: scoped, haveAlready: [], scopeLabel: "Aug 3"
        )
        XCTAssertEqual(
            text,
            """
            Shopping list · Aug 3

            Vegetables
            - Onion — 100 g

            Grains & Pulses
            - Rajma — 200 g
            """
        )
    }

    func testShareTextDropsPrunedItemsAndTheirEmptiedCategories() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [.monday], categorized: categorized
        )
        let text = ShoppingScope.buildShareText(
            scoped: scoped, haveAlready: ["onion"], scopeLabel: "Aug 3"
        )
        XCTAssertFalse(text.contains("Vegetables"))
        XCTAssertTrue(text.contains("Rajma"))
    }

    /// One item per line, no headings — pasting this into Reminders should create
    /// one entry per ingredient.
    func testCopyTextIsFlat() {
        let scoped = ShoppingScope.aggregateScopedList(
            dayWise: dayWise, selectedDays: [.monday], categorized: categorized
        )
        XCTAssertEqual(
            ShoppingScope.buildCopyText(scoped: scoped, haveAlready: []),
            "Onion 100 g\nRajma 200 g"
        )
    }

    func testCategoryOrderMatchesTheServerContract() {
        XCTAssertEqual(ShoppingScope.categoryOrder, [
            "Vegetables", "Fruits", "Dairy & Eggs", "Meat & Seafood",
            "Grains & Pulses", "Spices & Herbs", "Pantry Items", "Other",
        ])
    }
}
