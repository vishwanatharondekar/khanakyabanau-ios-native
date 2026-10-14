import XCTest
@testable import KhanaKit

final class ShoppingPlanKeyTests: XCTestCase {

    private var plan: MealPlan {
        MealPlan(weekStartDate: "2026-09-07")
            .withMeal(day: .monday, type: .breakfast, name: "Poha")
            .withMeal(day: .monday, type: .dinner, name: "Dal")
    }

    func testChangingADishChangesTheKey() {
        let edited = plan.withMeal(day: .monday, type: .dinner, name: "Rajma")
        XCTAssertNotEqual(shoppingPlanKey(plan), shoppingPlanKey(edited))
    }

    func testMovingADishToAnotherSlotChangesTheKey() {
        let moved = plan
            .withMeal(day: .monday, type: .dinner, name: "")
            .withMeal(day: .tuesday, type: .dinner, name: "Dal")
        XCTAssertNotEqual(shoppingPlanKey(plan), shoppingPlanKey(moved))
    }

    func testAResolvedImageIsNotAChange() {
        let withImage = plan.withImages(["poha": "https://img/poha.jpg"])
        XCTAssertEqual(shoppingPlanKey(plan), shoppingPlanKey(withImage))
    }
}
