import XCTest
@testable import KhanaKit

/// The flag is optional on the wire. `FirstWeekSeeder` and any build that
/// predates the feature must keep generating exactly as before, so the default
/// has to be false.
final class AIGenerateRequestTests: XCTestCase {

    private func encoded(_ request: AIGenerateRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDefaultsToUnrestricted() throws {
        let body = try encoded(AIGenerateRequest(weekStartDate: "2026-09-07"))
        XCTAssertEqual(body["restrictToIngredients"] as? Bool, false)
    }

    func testCarriesTheRestrictionWhenAsked() throws {
        let body = try encoded(AIGenerateRequest(
            weekStartDate: "2026-09-07",
            ingredients: ["paneer", "rice", "spinach"],
            restrictToIngredients: true
        ))
        XCTAssertEqual(body["restrictToIngredients"] as? Bool, true)
        XCTAssertEqual(body["ingredients"] as? [String], ["paneer", "rice", "spinach"])
    }
}
