import XCTest
@testable import KhanaKit

/// Golden-shape tests for the responses this backend actually returns, including
/// the unwrapped and inconsistent ones. Several routes return bare arrays, bare
/// dictionaries or a bare `null`, which strict `Codable` would reject.
final class APIParsingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - Meal plan

    func testMealPlanWithMixedSlotShapes() throws {
        let json = """
        {
          "id": "user123_2026-08-03",
          "userId": "user123",
          "weekStartDate": "2026-08-03",
          "meals": {
            "monday": {
              "breakfast": "Poha",
              "lunch": {"name": "Rajma", "calories": 420, "imageUrl": "rajma.jpg"},
              "dinner": ""
            },
            "tuesday": {"breakfast": "Upma"}
          }
        }
        """
        let plan = try decode(MealPlan.self, json)
        XCTAssertEqual(plan.id, "user123_2026-08-03")
        XCTAssertEqual(plan.weekStartDate, "2026-08-03")
        XCTAssertEqual(plan[.monday, .breakfast].name, "Poha")
        XCTAssertEqual(plan[.monday, .lunch].calories, 420)
        XCTAssertTrue(plan[.monday, .dinner].isEmpty)
        XCTAssertTrue(plan[.monday, .morningSnack].isEmpty, "Absent courses default to empty")
        XCTAssertEqual(plan[.tuesday, .breakfast].name, "Upma")
    }

    /// `GET /api/meals/history` returns a bare array, not `{plans: […]}`.
    func testHistoryIsABareArray() throws {
        let json = """
        [
          {"weekStartDate": "2026-07-27", "meals": {"monday": {"lunch": "Rajma"}}},
          {"weekStartDate": "2026-07-20", "meals": {"monday": {"lunch": "Chole"}}}
        ]
        """
        let history = try decode([MealPlan].self, json)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.weekStartDate, "2026-07-27")
    }

    /// Timestamps come back as ISO strings, or occasionally as raw Firestore maps.
    /// Neither is read by the client, so neither may break decoding.
    func testUnreadTimestampFieldsDoNotBreakDecoding() throws {
        let iso = """
        {"weekStartDate": "2026-08-03", "meals": {}, "createdAt": "2026-08-01T00:00:00Z"}
        """
        XCTAssertEqual(try decode(MealPlan.self, iso).weekStartDate, "2026-08-03")

        let firestoreMap = """
        {"weekStartDate": "2026-08-03", "meals": {}, "createdAt": {"seconds": 1, "nanoseconds": 0}}
        """
        XCTAssertEqual(try decode(MealPlan.self, firestoreMap).weekStartDate, "2026-08-03")
    }

    // MARK: - Auth

    func testAuthResponseFromLogin() throws {
        let json = """
        {"token": "eyJ1c2VySWQiOiJhYmMifQ==",
         "user": {"id": "abc", "email": "a@b.com", "name": "Asha"}}
        """
        let response = try decode(AuthResponse.self, json)
        XCTAssertEqual(response.token, "eyJ1c2VySWQiOiJhYmMifQ==")
        XCTAssertEqual(response.user.name, "Asha")
        XCTAssertFalse(response.user.isGuest, "Absent isGuest defaults to false")
    }

    func testGuestAuthResponseCarriesUsageCounters() throws {
        let json = """
        {"token": "t",
         "user": {"id": "guest_abc", "name": "Guest User", "isGuest": true,
                  "onboardingCompleted": false, "aiUsageCount": 2,
                  "shoppingListUsageCount": 0}}
        """
        let user = try decode(AuthResponse.self, json).user
        XCTAssertTrue(user.isGuest)
        XCTAssertEqual(user.aiUsageCount, 2)
    }

    func testProfileResponseExposesGuestAllowances() throws {
        let json = """
        {"user": {"id": "guest_abc", "name": "Guest User", "isGuest": true,
                  "aiUsageCount": 2, "shoppingListUsageCount": 3,
                  "guestUsageLimits": {"aiGeneration": 3, "shoppingList": 3}}}
        """
        let user = try decode(ProfileResponse.self, json).user
        XCTAssertEqual(user.remainingAIGenerations, 1)
        XCTAssertEqual(user.remainingShoppingLists, 0)
    }

    func testRegisteredUsersHaveNoUsageCeiling() throws {
        let json = #"{"user": {"id": "abc", "name": "Asha", "email": "a@b.com"}}"#
        let user = try decode(ProfileResponse.self, json).user
        XCTAssertNil(user.remainingAIGenerations)
        XCTAssertNil(user.remainingShoppingLists)
    }

    // MARK: - Unwrapped responses

    /// `GET /api/auth/dietary-preferences` returns the object itself, or a bare
    /// `null` when the user has never saved any.
    func testDietaryPreferencesAreUnwrapped() throws {
        let json = """
        {"isVegetarian": true, "nonVegDays": ["sunday"], "showCalories": true,
         "dailyCalorieTarget": 1800, "glutenFree": false}
        """
        let prefs = try decode(DietaryPreferences.self, json)
        XCTAssertTrue(prefs.isVegetarian)
        XCTAssertEqual(prefs.nonVegDays, ["sunday"])
        XCTAssertEqual(prefs.dailyCalorieTarget, 1800)
        XCTAssertFalse(prefs.nutsFree, "Absent flags default to false")
    }

    func testDietaryPreferencesDefaultsWhenFieldsAreMissing() throws {
        let prefs = try decode(DietaryPreferences.self, "{}")
        XCTAssertEqual(prefs.dailyCalorieTarget, 2000)
        XCTAssertFalse(prefs.isVegetarian)
    }

    func testDietaryAnalyticsValueDistinguishesMixedFromNonVegetarian() {
        XCTAssertEqual(DietaryPreferences(isVegetarian: true).analyticsValue, "vegetarian")
        XCTAssertEqual(DietaryPreferences(nonVegDays: []).analyticsValue, "non-vegetarian")
        XCTAssertEqual(DietaryPreferences(nonVegDays: ["sunday"]).analyticsValue, "mixed")
    }

    /// `GET /api/auth/video-urls` returns a bare dictionary.
    func testVideoURLsAreABareDictionary() throws {
        let map = try decode([String: String].self, #"{"poha": "https://youtu.be/abcdefghijk"}"#)
        XCTAssertEqual(map["poha"], "https://youtu.be/abcdefghijk")
    }

    func testLanguagePreferencesAreUnwrapped() throws {
        XCTAssertEqual(try decode(LanguagePreferences.self, #"{"language": "hi"}"#).language, "hi")
        XCTAssertEqual(try decode(LanguagePreferences.self, "{}").language, "en")
    }

    func testMealSettingsAreWrapped() throws {
        let json = #"{"mealSettings": {"enabledMealTypes": ["breakfast", "dinner"]}}"#
        let settings = try decode(MealSettingsEnvelope.self, json).mealSettings
        XCTAssertEqual(settings.enabledTypes, [.breakfast, .dinner])
    }

    // MARK: - Shopping list

    func testShoppingListResponse() throws {
        let json = """
        {
          "categorized": {"Vegetables": [{"name": "Onion", "amount": 300, "unit": "g"}]},
          "dayWise": {"monday": {"lunch": {"name": "Rajma Chawal",
                     "ingredients": [{"name": "Onion", "amount": 100, "unit": "g"}]}}},
          "haveAlready": ["salt"],
          "newItems": ["onion"],
          "cached": true
        }
        """
        let list = try decode(ShoppingList.self, json)
        XCTAssertEqual(list.categorized["Vegetables"]?.first?.amount, 300)
        XCTAssertEqual(list.dayWise["monday"]?["lunch"]?.name, "Rajma Chawal")
        XCTAssertEqual(list.haveAlready, ["salt"])
        XCTAssertTrue(list.cached)
    }

    func testLegacyShoppingListWithoutDayWise() throws {
        let json = #"{"categorized": {"Fruits": [{"name": "Apple", "amount": 4, "unit": "pieces"}]}}"#
        let list = try decode(ShoppingList.self, json)
        XCTAssertTrue(list.dayWise.isEmpty)
        XCTAssertFalse(list.cached)
    }

    // MARK: - AI and suggestions

    /// `POST /api/ai/generate` returns a raw planner grid, not a wrapped plan.
    func testAIGenerateReturnsARawGrid() throws {
        let json = """
        {"monday": {"breakfast": "Poha", "lunch": {"name": "Rajma", "calories": 400}},
         "tuesday": {"breakfast": "Upma"}}
        """
        let grid = try decode([String: DayMeals].self, json)
        XCTAssertEqual(grid["monday"]?.breakfast.name, "Poha")
        XCTAssertEqual(grid["monday"]?.lunch.calories, 400)
    }

    func testCorpusSuggestionsResponse() throws {
        let json = #"{"suggestions": ["Poha", "Upma"], "corpusSize": 812, "matchedBeforeTopN": 40}"#
        let response = try decode(CorpusSuggestionsResponse.self, json)
        XCTAssertEqual(response.suggestions, ["Poha", "Upma"])
        XCTAssertEqual(response.corpusSize, 812)
    }

    func testPrepResponseHandlesTheSkippedShape() throws {
        let updated = try decode(
            GeneratePrepResponse.self, #"{"updated": 3, "dishes": ["Rajma"]}"#
        )
        XCTAssertEqual(updated.updated, 3)

        let skipped = try decode(
            GeneratePrepResponse.self, #"{"updated": 0, "skipped": "nothing missing prep"}"#
        )
        XCTAssertEqual(skipped.updated, 0)
        XCTAssertEqual(skipped.skipped, "nothing missing prep")
        XCTAssertTrue(skipped.dishes.isEmpty)
    }

    // MARK: - Video search

    func testYouTubeSearchMapsToResults() throws {
        let json = """
        {"items": [{"id": "abcdefghijk", "title": "Rajma Recipe",
                    "thumbnail": "https://img/thumb.jpg", "channelTitle": "Chef",
                    "duration": "PT4M13S", "url": "https://youtu.be/abcdefghijk",
                    "viewCount": 12345, "publishedAt": "2026-01-01"}],
         "nextPageToken": "CAoQAA", "totalResults": 200}
        """
        let page = try decode(YouTubeSearchResponse.self, json).asPage
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.duration, "4:13", "ISO duration is pre-formatted")
        XCTAssertEqual(page.items.first?.thumbnailUrl, "https://img/thumb.jpg")
        XCTAssertEqual(page.nextPageToken, "CAoQAA")
    }

    func testImageMappingNeverFailsOnAnEmptyPayload() throws {
        let response = try decode(ImageMappingResponse.self, "{}")
        XCTAssertTrue(response.mealImageMappings.isEmpty)
    }

    // MARK: - Notifications

    func testNotificationPreferencesResponse() throws {
        let json = """
        {"notificationPreferences": {"prepReminders": true, "hourLocal": 20,
          "timezone": "Asia/Kolkata", "notifySlotUtc": 29},
         "weeklyMenuEmails": false}
        """
        let response = try decode(NotificationPreferencesResponse.self, json)
        XCTAssertEqual(response.settings.hour, 20)
        XCTAssertTrue(response.settings.enabled)
        XCTAssertEqual(response.weeklyMenuEmails, false)
    }

    // MARK: - Request encoding

    /// `{}` is what the prep route reads as "the whole week".
    func testEmptyPrepRequestEncodesToAnEmptyObject() throws {
        let data = try XCTUnwrap(Endpoint.json(GeneratePrepRequest()))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
    }

    func testTargetedPrepRequestEncodesBothFields() throws {
        let data = try XCTUnwrap(
            Endpoint.json(GeneratePrepRequest(day: "monday", mealType: "lunch"))
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["day"] as? String, "monday")
        XCTAssertEqual(object["mealType"] as? String, "lunch")
    }

    func testShoppingListRequestAlwaysSendsOnePortion() throws {
        let data = try XCTUnwrap(Endpoint.json(ShoppingListRequest(
            meals: ["Rajma"], dayWiseMeals: ["monday": ["lunch": "Rajma"]],
            weekStartDate: "2026-08-03"
        )))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["portions"] as? Int, 1)
    }

    func testDeviceRegistrationIdentifiesAsIOS() throws {
        let data = try XCTUnwrap(Endpoint.json(
            RegisterDeviceRequest(token: "fcm-token", timezone: "Asia/Kolkata")
        ))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["platform"] as? String, "ios")
        XCTAssertEqual(object["timezone"] as? String, "Asia/Kolkata")
        XCTAssertNil(object["prepReminders"], "Unset optionals are omitted, not sent as null")
    }

    // MARK: - Guest identity

    func testGuestDeviceIDHasTheShapeTheServerRequires() {
        let id = GuestDeviceID.generate()
        XCTAssertTrue(id.hasPrefix("guest_"))
        XCTAssertTrue(GuestDeviceID.isGuest(id))
        let parts = id.split(separator: "_")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[2].count, 9)
    }

    // MARK: - Errors

    func testErrorCopyMatchesAndroidWordForWord() {
        XCTAssertEqual(
            APIError.offline.userMessage(fallback: "x"),
            "You're offline. Check your internet connection and try again."
        )
        XCTAssertEqual(
            APIError.timeout.userMessage(fallback: "x"),
            "The connection timed out. Please try again."
        )
        XCTAssertEqual(
            APIError.network("boom").userMessage(fallback: "x"),
            "Network problem. Check your connection and try again."
        )
        XCTAssertEqual(
            APIError.accountAlreadyExists.userMessage(fallback: "x"),
            "An account with this email already exists. Please sign in instead."
        )
    }

    func testServerMessageWinsOverTheFallback() {
        XCTAssertEqual(
            APIError.http(status: 400, message: "Invalid meals data").userMessage(fallback: "x"),
            "Invalid meals data"
        )
        XCTAssertEqual(
            APIError.http(status: 500, message: nil).userMessage(fallback: "Failed to load meals"),
            "Failed to load meals"
        )
    }

    func testGuestLimitInfoComputesWhatIsLeft()  {
        let info = GuestLimitInfo(usageLimit: 3, currentUsage: 3)
        XCTAssertEqual(info.remaining, 0)
        XCTAssertEqual(GuestLimitInfo(usageLimit: 3, currentUsage: 5).remaining, 0)
    }

    func testOnlyTransientFailuresAreRetryable() {
        XCTAssertTrue(APIError.offline.isRetryable)
        XCTAssertTrue(APIError.timeout.isRetryable)
        XCTAssertTrue(APIError.http(status: 503, message: nil).isRetryable)
        XCTAssertFalse(APIError.http(status: 400, message: nil).isRetryable)
        XCTAssertFalse(APIError.unauthorized.isRetryable)
    }
}
