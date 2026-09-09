import XCTest
@testable import KhanaKit

/// A `cachedOnly` probe answers 200 with `{"absent":true,"cached":false}` when
/// nothing is stored. That is a normal answer, not an error — the caller asked
/// whether a list exists and the answer is no.
final class ShoppingListAbsentTests: XCTestCase {

    private func decode(_ json: String) throws -> ShoppingList {
        try JSONDecoder().decode(ShoppingList.self, from: Data(json.utf8))
    }

    func testAProbeMissDecodesAsAbsent() throws {
        let list = try decode(#"{"absent":true,"cached":false}"#)
        XCTAssertTrue(list.absent)
        XCTAssertTrue(list.categorized.isEmpty)
    }

    func testARealListIsNotAbsent() throws {
        let list = try decode(
            #"{"categorized":{"Produce":[{"name":"onion","amount":2,"unit":"pcs"}]},"cached":true}"#
        )
        XCTAssertFalse(list.absent)
        XCTAssertTrue(list.cached)
    }

    func testAnOlderResponseWithNoAbsentKeyIsNotAbsent() throws {
        XCTAssertFalse(try decode(#"{"categorized":{}}"#).absent)
    }

    func testTheRequestDefaultsToNotProbing() throws {
        let normal = ShoppingListRequest(meals: [], dayWiseMeals: [:], weekStartDate: "2026-09-07")
        XCTAssertFalse(normal.cachedOnly)

        let probe = ShoppingListRequest(
            meals: [], dayWiseMeals: [:], weekStartDate: "2026-09-07", cachedOnly: true
        )
        XCTAssertTrue(probe.cachedOnly)
    }
}
