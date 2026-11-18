import XCTest
@testable import KhanaKit

/// Port-parity tests for `MealKeys`. Mirrors the web app's
/// `lib/meal-corpus-utils.ts`; when in doubt, that file is the specification.
final class MealKeysTests: XCTestCase {

    private func key(_ name: String) -> String { MealKeys.mainDishKey(of: name) }

    /// `Fixtures/main-dish-keys.tsv` holds the web app's key for every bundled
    /// cuisine dish, the most-planned production dishes and one case per rule.
    /// Regenerate it with the web app's `scripts/export-main-dish-key-fixture.ts`.
    func testEveryFixtureNameKeysTheSameAsTheWebApp() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "main-dish-keys", withExtension: "tsv", subdirectory: "Fixtures")
        )
        let cases = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> (String, String) in
                let tab = line.firstIndex(of: "\t")!
                return (String(line[..<tab]), String(line[line.index(after: tab)...]))
            }
        XCTAssertGreaterThan(cases.count, 250, "fixture looks truncated: \(cases.count) cases")
        let mismatches = cases
            .filter { name, expected in key(name) != expected }
            .map { name, expected in "\"\(name)\": expected \"\(expected)\", got \"\(key(name))\"" }
        XCTAssertEqual(mismatches, [])
    }

    func testPlatesBuiltAroundTheSameDishShareAKey() {
        XCTAssertEqual(key("Rajma"), key("Rajma chawal with curd"))
        XCTAssertEqual(key("Rajma"), key("Rajma with jeera rice"))
        XCTAssertEqual(key("Aloo paratha with curd"), key("Aloo parantha with butter"))
        XCTAssertEqual(key("Palak Paneer"), key("Two phulka with palak paneer and salad"))
        XCTAssertEqual(key("Chole"), key("Chole (Chickpea Curry) with Rice"))
    }

    func testDifferentDishesKeepDifferentKeys() {
        XCTAssertNotEqual(key("Aloo paratha"), key("Aloo puri"))
        XCTAssertNotEqual(key("Dal makhani with rice"), key("Dal tadka with rice"))
        XCTAssertNotEqual(key("Rice with mushur dal and doi maach"), key("Rice with mushur dal and macher bhapa"))
    }

    func testMergeKeepsTheFirstNamePerMainDish() {
        XCTAssertEqual(
            MealSuggestions.merge(["Rajma chawal", "Poha"], ["Rajma rice with curd", "Upma", "poha"]),
            ["Rajma chawal", "Poha", "Upma"]
        )
    }

    func testMergeDropsNamesWithNothingToKeyOn() {
        XCTAssertEqual(
            MealSuggestions.merge(["Poha", "  ", "!!!"], ["  Upma ", "POHA"]),
            ["Poha", "Upma"]
        )
    }
}
