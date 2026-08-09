import XCTest
@testable import KhanaKit

/// The `Meal` codec is the highest-risk piece of the whole port: `PUT /api/meals/{week}`
/// replaces the entire grid with what we send, so an encoding slip silently deletes
/// calories, videos or prep for every slot in the week.
final class MealCodecTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private func decodeMeals(_ json: String) throws -> [String: Meal] {
        try decoder.decode([String: Meal].self, from: Data(json.utf8))
    }

    private func encodeToJSON(_ meals: [String: Meal]) throws -> [String: Any] {
        let data = try encoder.encode(meals)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Decoding

    func testDecodesBareStringSlot() throws {
        let meals = try decodeMeals(#"{"lunch": "Poha"}"#)
        XCTAssertEqual(meals["lunch"]?.name, "Poha")
        XCTAssertNil(meals["lunch"]?.calories)
        XCTAssertFalse(try XCTUnwrap(meals["lunch"]).isEmpty)
    }

    func testDecodesEmptyStringAsEmptySlot() throws {
        let meals = try decodeMeals(#"{"lunch": ""}"#)
        XCTAssertEqual(meals["lunch"]?.name, "")
        XCTAssertTrue(try XCTUnwrap(meals["lunch"]).isEmpty)
    }

    func testDecodesNullAsEmptySlot() throws {
        let meals = try decodeMeals(#"{"lunch": null}"#)
        XCTAssertEqual(meals["lunch"], .empty)
    }

    func testDecodesObjectSlotWithEveryField() throws {
        let json = """
        {"dinner": {
          "name": "Chana Masala",
          "imageUrl": "chana.jpg",
          "calories": 480,
          "videoUrl": "https://youtu.be/abcdefghijk",
          "prepFor": "Chana Masala",
          "prep": {
            "steps": [{"text": "Soak chana overnight", "leadTimeMinutes": 480, "category": "soak"}],
            "maxLeadTimeMinutes": 480,
            "activeMinutes": 5,
            "generatedAt": "2026-08-01T00:00:00Z"
          }
        }}
        """
        let meal = try XCTUnwrap(decodeMeals(json)["dinner"])
        XCTAssertEqual(meal.name, "Chana Masala")
        XCTAssertEqual(meal.imageUrl, "chana.jpg")
        XCTAssertEqual(meal.calories, 480)
        XCTAssertEqual(meal.videoUrl, "https://youtu.be/abcdefghijk")
        XCTAssertEqual(meal.prep?.steps.count, 1)
        XCTAssertEqual(meal.prep?.steps.first?.category, .soak)
        XCTAssertEqual(meal.prep?.steps.first?.leadTimeMinutes, 480)
        XCTAssertNotNil(meal.validPrep, "prepFor matches the name, so prep is current")
    }

    /// A whole week is 35 slots decoded in one pass. One bad prep must not take the
    /// response down with it.
    func testMalformedPrepDegradesToNilWithoutLosingTheDish() throws {
        let json = #"{"lunch": {"name": "Dosa", "calories": 300, "prep": "not-an-object"}}"#
        let meal = try XCTUnwrap(decodeMeals(json)["lunch"])
        XCTAssertEqual(meal.name, "Dosa")
        XCTAssertEqual(meal.calories, 300)
        XCTAssertNil(meal.prep)
    }

    func testUnknownPrepCategoryFallsBackToRest() throws {
        let json = """
        {"lunch": {"name": "Idli", "prepFor": "Idli",
          "prep": {"steps": [{"text": "Sprout", "leadTimeMinutes": 60, "category": "sprout"}]}}}
        """
        let meal = try XCTUnwrap(decodeMeals(json)["lunch"])
        XCTAssertEqual(meal.prep?.steps.first?.category, .rest)
    }

    func testDecodesUnexpectedShapeAsEmpty() throws {
        let meals = try decodeMeals(#"{"lunch": [1, 2, 3]}"#)
        XCTAssertEqual(meals["lunch"], .empty)
    }

    // MARK: - validPrep staleness rule

    func testValidPrepIsNilWhenTheDishWasRenamed() {
        let prep = MealPrep(steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)])
        let meal = Meal(name: "Rajma", prep: prep, prepFor: "Chana Masala")
        XCTAssertNotNil(meal.prep)
        XCTAssertNil(meal.validPrep, "Prep for a dish that was swapped out must not be shown")
    }

    func testValidPrepIgnoresSurroundingWhitespace() {
        let prep = MealPrep(steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)])
        let meal = Meal(name: " Rajma ", prep: prep, prepFor: "Rajma")
        XCTAssertNotNil(meal.validPrep)
    }

    // MARK: - Encoding

    func testEncodesNameOnlyMealAsAPlainString() throws {
        let json = try encodeToJSON(["lunch": Meal(name: "Poha")])
        XCTAssertEqual(json["lunch"] as? String, "Poha")
    }

    /// An `imageUrl` alone must not force the object form — the server re-attaches
    /// images on read, so emitting it would just churn data.
    func testImageURLAloneStillEncodesAsAString() throws {
        let json = try encodeToJSON(["lunch": Meal(name: "Poha", imageUrl: "poha.jpg")])
        XCTAssertEqual(json["lunch"] as? String, "Poha")
    }

    func testEncodesCaloriesAsAnObject() throws {
        let json = try encodeToJSON(["lunch": Meal(name: "Poha", calories: 250)])
        let slot = try XCTUnwrap(json["lunch"] as? [String: Any])
        XCTAssertEqual(slot["name"] as? String, "Poha")
        XCTAssertEqual(slot["calories"] as? Int, 250)
        XCTAssertNil(slot["imageUrl"], "imageUrl is never sent back to the server")
    }

    /// prepFor is what makes prep interpretable, and what lets the server notice the
    /// dish has changed. Sending prep alone would read as freshly generated and stop
    /// it ever being regenerated.
    func testPrepIsNotEmittedWithoutPrepFor() throws {
        let prep = MealPrep(steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)])
        let json = try encodeToJSON(["lunch": Meal(name: "Rajma", prep: prep, prepFor: nil)])
        XCTAssertEqual(json["lunch"] as? String, "Rajma",
                       "With nothing else to carry, the slot collapses back to a plain string")
    }

    func testPrepIsEmittedTogetherWithPrepFor() throws {
        let prep = MealPrep(
            steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
            maxLeadTimeMinutes: 480,
            activeMinutes: 5
        )
        let json = try encodeToJSON(["lunch": Meal(name: "Rajma", prep: prep, prepFor: "Rajma")])
        let slot = try XCTUnwrap(json["lunch"] as? [String: Any])
        XCTAssertEqual(slot["prepFor"] as? String, "Rajma")
        let encodedPrep = try XCTUnwrap(slot["prep"] as? [String: Any])
        XCTAssertEqual(encodedPrep["maxLeadTimeMinutes"] as? Int, 480)
        let steps = try XCTUnwrap(encodedPrep["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.first?["category"] as? String, "soak")
    }

    func testEncodesVideoURL() throws {
        let json = try encodeToJSON([
            "lunch": Meal(name: "Poha", videoUrl: "https://youtu.be/abcdefghijk"),
        ])
        let slot = try XCTUnwrap(json["lunch"] as? [String: Any])
        XCTAssertEqual(slot["videoUrl"] as? String, "https://youtu.be/abcdefghijk")
    }

    // MARK: - Round trip

    /// The property that actually protects user data on save.
    func testRoundTripPreservesEverythingTheServerStores() throws {
        let original = Meal(
            name: "Chana Masala",
            calories: 480,
            prep: MealPrep(
                steps: [PrepStep(text: "Soak chana", leadTimeMinutes: 480, category: .soak)],
                maxLeadTimeMinutes: 480,
                activeMinutes: 5,
                generatedAt: "2026-08-01T00:00:00Z"
            ),
            prepFor: "Chana Masala",
            videoUrl: "https://youtu.be/abcdefghijk"
        )
        let data = try encoder.encode(["dinner": original])
        let decoded = try XCTUnwrap(decoder.decode([String: Meal].self, from: data)["dinner"])

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.calories, original.calories)
        XCTAssertEqual(decoded.videoUrl, original.videoUrl)
        XCTAssertEqual(decoded.prepFor, original.prepFor)
        XCTAssertEqual(decoded.prep, original.prep)
    }

    func testDayMealsDefaultsMissingCoursesToEmpty() throws {
        let day = try decoder.decode(
            DayMeals.self,
            from: Data(#"{"breakfast": "Poha", "dinner": "Khichdi"}"#.utf8)
        )
        XCTAssertEqual(day.breakfast.name, "Poha")
        XCTAssertEqual(day.dinner.name, "Khichdi")
        XCTAssertTrue(day.lunch.isEmpty)
        XCTAssertTrue(day.morningSnack.isEmpty)
        XCTAssertTrue(day.eveningSnack.isEmpty)
    }
}
