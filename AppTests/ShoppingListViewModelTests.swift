import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// App-layer behaviour that isn't covered by the pure-logic suite in `KhanaKit`.
@MainActor
final class ShoppingListViewModelTests: XCTestCase {

    private func makeList() -> ShoppingList {
        ShoppingList(
            categorized: [
                "Vegetables": [Ingredient(name: "Onion", amount: 300, unit: "g")],
                "Grains & Pulses": [Ingredient(name: "Rajma", amount: 200, unit: "g")],
            ],
            dayWise: [
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
            ],
            haveAlready: ["rajma"],
            newItems: ["onion"]
        )
    }

    private func makeModel() -> ShoppingListViewModel {
        ShoppingListViewModel(
            env: AppEnvironment(), list: makeList(), weekStartDate: "2026-08-03"
        )
    }

    func testSeedsHaveAlreadyFromTheServer() {
        let model = makeModel()
        XCTAssertTrue(model.isHad("Rajma"))
        XCTAssertFalse(model.isHad("Onion"))
    }

    func testNewItemsAreFlaggedCaseInsensitively() {
        let model = makeModel()
        XCTAssertTrue(model.isNew("Onion"))
        XCTAssertTrue(model.isNew("onion"))
    }

    func testTogglingHaveFlipsTheCounts() {
        let model = makeModel()
        model.selectedDays = [.monday]
        let before = model.toBuyCount
        model.toggleHave("Onion")
        XCTAssertEqual(model.toBuyCount, before - 1)
        XCTAssertTrue(model.isHad("Onion"))
    }

    func testCategoryToggleTicksAllThenUnticksAll() {
        let model = makeModel()
        model.selectedDays = [.monday]
        guard let vegetables = model.scoped.categorized.first(where: { $0.name == "Vegetables" })
        else { return XCTFail("Expected a Vegetables section") }

        model.toggleCategory(vegetables)
        XCTAssertTrue(vegetables.items.allSatisfy { model.isHad($0.name) })

        model.toggleCategory(vegetables)
        XCTAssertTrue(vegetables.items.allSatisfy { !model.isHad($0.name) })
    }

    func testScopeNarrowingRecomputesQuantities() {
        let model = makeModel()
        model.selectedDays = [.monday, .tuesday]
        let bothDays = model.scoped.categorized
            .first { $0.name == "Vegetables" }?.items.first
        // 100 g + 900 g rolls over into kilograms.
        XCTAssertEqual(bothDays?.unit, "kg")
        XCTAssertEqual(bothDays?.amount, 1.0)

        model.selectedDays = [.monday]
        let mondayOnly = model.scoped.categorized
            .first { $0.name == "Vegetables" }?.items.first
        XCTAssertEqual(mondayOnly?.unit, "g")
        XCTAssertEqual(mondayOnly?.amount, 100)
    }

    func testContextLineListsTheDishesAnIngredientIsFor() {
        let model = makeModel()
        model.selectedDays = [.monday, .tuesday]
        XCTAssertEqual(model.meals(for: "Onion"), ["Rajma Chawal", "Pulao"])
    }

    func testDefaultScopeIsSeededFromTheWeek() {
        // A past week scopes to all seven days.
        let model = ShoppingListViewModel(
            env: AppEnvironment(), list: makeList(), weekStartDate: "2020-01-06"
        )
        XCTAssertEqual(model.selectedDays.count, 7)
    }
}
