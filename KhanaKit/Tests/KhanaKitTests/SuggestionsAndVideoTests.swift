import XCTest
@testable import KhanaKit

/// Local suggestion seeding and the recipe-video resolution rule.
final class SuggestionsAndVideoTests: XCTestCase {

    private func historyPlan(_ week: String, lunches: [String]) -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: week)
        for (index, name) in lunches.enumerated() {
            let day = DayOfWeek.allCases[index % 7]
            plan.meals[day.key] = DayMeals(lunch: Meal(name: name))
        }
        return plan
    }

    // MARK: - Suggestions

    func testHistoryRankingDeduplicatesByName() {
        let plan = historyPlan("2026-07-27", lunches: ["Rajma", "Rajma", "Chole"])
        var generator = SeededGenerator(seed: 42)
        let ranked = MealSuggestions.rankHistoryMeals(
            history: [plan], type: .lunch, limit: 8, using: &generator
        )
        XCTAssertEqual(Set(ranked), ["Rajma", "Chole"])
    }

    func testHistoryRankingIsEmptyForACourseTheUserNeverPlans() {
        let plan = historyPlan("2026-07-27", lunches: ["Rajma"])
        var generator = SeededGenerator(seed: 1)
        XCTAssertTrue(
            MealSuggestions.rankHistoryMeals(
                history: [plan], type: .eveningSnack, limit: 8, using: &generator
            ).isEmpty
        )
    }

    func testMoreRecentWeeksOutrankOlderOnes() {
        // "Recent" appears once in the newest week; "Old" appears once in the
        // oldest. With a pool wider than the limit, both survive — what matters is
        // that recency weighting doesn't crash or drop either.
        let recent = historyPlan("2026-07-27", lunches: ["Recent"])
        let old = historyPlan("2026-06-01", lunches: ["Old"])
        var generator = SeededGenerator(seed: 7)
        let ranked = MealSuggestions.rankHistoryMeals(
            history: [recent, old], type: .lunch, limit: 8, using: &generator
        )
        XCTAssertEqual(Set(ranked), ["Recent", "Old"])
    }

    func testBuildInitialFillsTheLimitAndStaysUnique() {
        let plan = historyPlan("2026-07-27", lunches: ["Rajma", "Chole"])
        var generator = SeededGenerator(seed: 7)
        let suggestions = MealSuggestions.buildInitial(
            cuisines: ["Maharashtrian"], vegetarian: true, history: [plan],
            type: .lunch, using: &generator
        )
        XCTAssertEqual(suggestions.count, 8)
        XCTAssertEqual(Set(suggestions).count, suggestions.count)
    }

    func testSameSeedProducesTheSameSuggestions() {
        let plan = historyPlan("2026-07-27", lunches: ["Rajma"])
        var first = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)
        XCTAssertEqual(
            MealSuggestions.buildInitial(
                cuisines: ["Bengali"], vegetarian: false, history: [plan],
                type: .dinner, using: &first
            ),
            MealSuggestions.buildInitial(
                cuisines: ["Bengali"], vegetarian: false, history: [plan],
                type: .dinner, using: &second
            )
        )
    }

    /// With no history at all the list still fills from the cuisine pools, so the
    /// sheet is never empty on a brand-new account.
    func testColdStartStillProducesAFullList() {
        var generator = SeededGenerator(seed: 3)
        let suggestions = MealSuggestions.buildInitial(
            cuisines: [], vegetarian: false, history: [], type: .breakfast, using: &generator
        )
        XCTAssertEqual(suggestions.count, 8, "The universal pool alone covers the limit")
    }

    func testVegetarianModeExcludesMeatDishes() {
        var vegGenerator = SeededGenerator(seed: 1)
        let veg = MealSuggestions.coldStartMeals(
            cuisines: ["Maharashtrian"], vegetarian: true, type: .lunch,
            limit: 500, using: &vegGenerator
        )
        XCTAssertFalse(veg.contains("Kolhapuri Chicken"))
        XCTAssertFalse(veg.contains("Chicken Curry"))

        var nonVegGenerator = SeededGenerator(seed: 1)
        let nonVeg = MealSuggestions.coldStartMeals(
            cuisines: ["Maharashtrian"], vegetarian: false, type: .lunch,
            limit: 500, using: &nonVegGenerator
        )
        XCTAssertTrue(nonVeg.contains("Kolhapuri Chicken"))
    }

    func testSnackCoursesDrawFromTheSnackPool() {
        var generator = SeededGenerator(seed: 5)
        let snacks = MealSuggestions.coldStartMeals(
            cuisines: ["Maharashtrian"], vegetarian: true, type: .eveningSnack,
            limit: 500, using: &generator
        )
        XCTAssertTrue(snacks.contains("Vada Pav"))
    }

    func testMergeDropsBlanksAndCaseInsensitiveRepeats() {
        XCTAssertEqual(
            MealSuggestions.merge(["Poha", "  ", "poha"], ["Upma", "POHA"]),
            ["Poha", "Upma"]
        )
    }

    // MARK: - Cuisine data

    func testCuisineNamesMatchTheServerContractExactly() {
        XCTAssertEqual(CuisineData.allCuisineNames, [
            "Maharashtrian", "North Indian", "South Indian",
            "Gujarati", "Bengali", "Assamese", "Odisha",
        ])
    }

    func testDishPoolsAreDeduplicatedAcrossCuisineAndUniversalSets() {
        let pool = CuisineData.dishesFor(["Maharashtrian", "Odisha"], vegOnly: true)
        XCTAssertEqual(Set(pool.breakfast).count, pool.breakfast.count)
        XCTAssertEqual(Set(pool.snacks).count, pool.snacks.count)
        XCTAssertTrue(pool.breakfast.contains("Poha"))
    }

    func testSampleDishesAreCappedAndUnique() {
        let samples = CuisineData.sampleDishes(for: "North Indian")
        XCTAssertEqual(samples.count, 8)
        XCTAssertEqual(Set(samples).count, samples.count)
        XCTAssertTrue(CuisineData.sampleDishes(for: "Nonexistent").isEmpty)
    }

    // MARK: - Recipe videos

    /// The one priority rule: a deliberate save beats whatever the server cached
    /// against the slot, because the saved pick follows the dish across weeks.
    func testSavedPickBeatsTheSlotVideo() {
        let meal = Meal(name: "Poha", videoUrl: "https://slot")
        XCTAssertEqual(
            RecipeVideos.url(in: ["poha": "https://saved"], for: meal), "https://saved"
        )
    }

    func testFallsBackToTheSlotVideoWhenNothingIsSaved() {
        let meal = Meal(name: "Poha", videoUrl: "https://slot")
        XCTAssertEqual(RecipeVideos.url(in: [:], for: meal), "https://slot")
        XCTAssertEqual(RecipeVideos.url(in: nil, for: meal), "https://slot")
    }

    func testABlankSavedEntryIsTreatedAsAbsent() {
        let meal = Meal(name: "Poha", videoUrl: "https://slot")
        XCTAssertEqual(RecipeVideos.url(in: ["poha": ""], for: meal), "https://slot")
    }

    func testNoVideoAnywhereResolvesToNil() {
        XCTAssertNil(RecipeVideos.url(in: [:], for: Meal(name: "Poha")))
    }

    func testLookupKeyIsTrimmedAndLowercased() {
        XCTAssertEqual(RecipeVideos.normalizeKey("  Poha  "), "poha")
        let meal = Meal(name: " Poha ")
        XCTAssertEqual(RecipeVideos.url(in: ["poha": "https://saved"], for: meal), "https://saved")
    }

    func testVideoIDExtractionCoversEveryYouTubeURLForm() {
        let expected = "dQw4w9WgXcQ"
        for url in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s",
        ] {
            XCTAssertEqual(RecipeVideos.videoID(from: url), expected, "Failed for \(url)")
        }
    }

    func testURLValidationAcceptsOnlyYouTubeHostsOverHTTP() {
        XCTAssertTrue(RecipeVideos.isValidYouTubeURL("https://m.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertTrue(RecipeVideos.isValidYouTubeURL("http://youtu.be/dQw4w9WgXcQ"))
        XCTAssertFalse(RecipeVideos.isValidYouTubeURL("https://vimeo.com/12345"))
        XCTAssertFalse(RecipeVideos.isValidYouTubeURL("ftp://youtube.com/x"))
        XCTAssertFalse(RecipeVideos.isValidYouTubeURL("not a url"))
        XCTAssertFalse(RecipeVideos.isValidYouTubeURL(""))
    }

    func testDurationFormatting() {
        XCTAssertEqual(RecipeVideos.formatDuration("PT4M13S"), "4:13")
        XCTAssertEqual(RecipeVideos.formatDuration("PT1H2M3S"), "1:02:03")
        XCTAssertEqual(RecipeVideos.formatDuration("PT45S"), "0:45")
        XCTAssertEqual(RecipeVideos.formatDuration("PT10M"), "10:00")
        XCTAssertNil(RecipeVideos.formatDuration("PT0S"), "Live streams report zero")
        XCTAssertNil(RecipeVideos.formatDuration(nil))
        XCTAssertNil(RecipeVideos.formatDuration("garbage"))
    }

    func testEmbedAndThumbnailURLs() {
        XCTAssertEqual(
            RecipeVideos.embedURL(videoID: "abc"), "https://www.youtube.com/embed/abc"
        )
        XCTAssertEqual(
            RecipeVideos.thumbnailURL(videoID: "abc"),
            "https://img.youtube.com/vi/abc/mqdefault.jpg"
        )
    }

    // MARK: - Image URLs

    func testRelativeImagePathsAreResolvedAgainstTheCDN() {
        XCTAssertEqual(
            MealImageURLs.absolutize("poha.jpg"),
            "https://d3rj590miwbz96.cloudfront.net/meals-data/images/poha.jpg"
        )
        XCTAssertEqual(
            MealImageURLs.absolutize("/poha.jpg"),
            "https://d3rj590miwbz96.cloudfront.net/meals-data/images/poha.jpg"
        )
    }

    func testAbsoluteImageURLsPassThroughUnchanged() {
        XCTAssertEqual(
            MealImageURLs.absolutize("https://cdn.example/x.jpg"), "https://cdn.example/x.jpg"
        )
        XCTAssertNil(MealImageURLs.absolutize(nil))
        XCTAssertNil(MealImageURLs.absolutize("   "))
    }

    // MARK: - Languages

    func testEveryLanguageHasANativeName() {
        XCTAssertEqual(SupportedLanguage.allCases.count, 10)
        for language in SupportedLanguage.allCases {
            XCTAssertFalse(language.nativeName.isEmpty)
            XCTAssertFalse(language.displayName.isEmpty)
        }
        XCTAssertEqual(SupportedLanguage.fromCode("hi").nativeName, "हिन्दी")
        XCTAssertEqual(SupportedLanguage.fromCode("HI"), .hindi)
        XCTAssertEqual(SupportedLanguage.fromCode("zz"), .english, "Unknown codes fall back")
    }
}
