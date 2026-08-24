import XCTest
@testable import KhanaKit

/// Ported case for case from the web app's `lib/recipe-video-keys.test.ts`, and
/// mirrored by Android's `RecipeVideoKeysTest`. The rule decides which saved video
/// belongs to which meal on every client, so the three suites are meant to be read
/// side by side; a case that changes in one has to change in the others.
final class RecipeVideoKeysTests: XCTestCase {

    /// A real multi-dish line, kept verbatim. A paraphrased meal name tests nothing.
    private let plate = "Gujarati dal, steamed rice, bhindi nu shaak and phulka"

    /// Distinct 11-character ids so a wrong pick is obvious in the failure output.
    private let map = [
        "gujarati dal": "https://youtu.be/aaaaaaaaaaa",
        "dal": "https://youtu.be/bbbbbbbbbbb",
        "fish fry": "https://youtu.be/ccccccccccc",
        "chicken sukka": "https://youtu.be/ddddddddddd",
    ]

    // MARK: - storageKey

    func testStorageKeyLowercasesAndTrimsLikeTheAPI() {
        XCTAssertEqual(RecipeVideoKeys.storageKey("  Gujarati Dal "), "gujarati dal")
    }

    func testStorageKeyLeavesInnerPunctuationAloneBecauseStorageDoes() {
        XCTAssertEqual(
            RecipeVideoKeys.storageKey("Fish Fry, Chicken Sukka"),
            "fish fry, chicken sukka"
        )
    }

    // MARK: - keyMatchesMeal

    func testATwoWordDishIsFoundInsideAWholePlate() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("gujarati dal", mealName: plate))
    }

    func testADishACommaSeparatesFromTheRestIsFound() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("fish fry", mealName: "Fish Fry, Chicken Sukka"))
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("chicken sukka", mealName: "Fish Fry, Chicken Sukka"))
    }

    func testAPluralInTheMealNameIsTolerated() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("idli", mealName: "Idlis with sambar"))
    }

    func testAPluralInTheKeyIsTolerated() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("dosas", mealName: "Dosa with chutney"))
    }

    func testAKeyThatIsOnlyPartOfAWordDoesNotMatch() {
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("dal", mealName: "Dalia Upma"))
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("aam", mealName: "Aamras with puri"))
    }

    func testTheKeyWordsHaveToBeContiguous() {
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("gujarati dal", mealName: "Gujarati style dal"))
    }

    /// Guards the 4-character floor: stemming "das" to "da" would match "Da Bhaji".
    func testThreeLetterTokensAreLeftUnstemmed() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal("dal", mealName: "Dal Makhani"))
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("das", mealName: "Da Bhaji"))
    }

    /// Documents the deliberate limit rather than a wish.
    func testEsPluralsDoNotMatch() {
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("fish fry", mealName: "Fish Fries with rice"))
    }

    func testAKeyThatIsTheWholeMealNameMatchesAsLegacyEntriesAre() {
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal(RecipeVideoKeys.storageKey(plate), mealName: plate))
    }

    func testABlankKeyOrABlankMealMatchesNothing() {
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("", mealName: plate))
        XCTAssertFalse(RecipeVideoKeys.keyMatchesMeal("dal", mealName: ""))
    }

    // MARK: - findDishSlice

    func testTheSliceComesBackInTheMealNamesOwnCasing() {
        XCTAssertEqual(
            RecipeVideoKeys.findDishSlice(candidate: "gujarati DAL", mealName: plate),
            "Gujarati dal"
        )
    }

    func testTheSliceStopsAtTheDishNotAtThePunctuationAfterIt() {
        XCTAssertEqual(
            RecipeVideoKeys.findDishSlice(candidate: "fish fry", mealName: "Fish Fry, Chicken Sukka"),
            "Fish Fry"
        )
    }

    func testTheSliceSpellsThePluralTheWayTheMealDoes() {
        XCTAssertEqual(
            RecipeVideoKeys.findDishSlice(candidate: "idli", mealName: "Idlis with sambar"),
            "Idlis"
        )
    }

    // The three ways a model can wander off, and the reason this function exists.

    func testATranslatedDishNameIsRejected() {
        XCTAssertNil(
            RecipeVideoKeys.findDishSlice(candidate: "Spinach Cottage Cheese", mealName: "Palak Paneer, roti")
        )
    }

    func testAReorderedDishNameIsRejected() {
        XCTAssertNil(
            RecipeVideoKeys.findDishSlice(candidate: "Dal Gujarati", mealName: "Gujarati style dal")
        )
    }

    func testADishThatIsNotInTheMealAtAllIsRejected() {
        XCTAssertNil(RecipeVideoKeys.findDishSlice(candidate: "Paneer Butter Masala", mealName: plate))
    }

    func testACandidateThatIsTheWholeNameComesBackWhole() {
        XCTAssertEqual(RecipeVideoKeys.findDishSlice(candidate: plate, mealName: plate), plate)
    }

    func testABlankCandidateHasNoSlice() {
        XCTAssertNil(RecipeVideoKeys.findDishSlice(candidate: "", mealName: plate))
    }

    /// Reachable whenever a model answers with two adjacent dishes, and the comma has
    /// to survive: the slice becomes the storage key, and `storageKey` keeps inner
    /// punctuation, so a slice that dropped it would not read back.
    func testPunctuationInsideASliceSpanningTwoDishesIsKept() {
        XCTAssertEqual(
            RecipeVideoKeys.findDishSlice(candidate: "fish fry chicken", mealName: "Fish Fry, Chicken Sukka"),
            "Fish Fry, Chicken"
        )
    }

    /// The central invariant, as a property rather than by example: what comes back is
    /// always a run of the meal name itself, which is what makes it safe to use as a
    /// storage key. Every resolving case here differs from its candidate in casing or
    /// in a plural, so an implementation that handed back the candidate's own words
    /// would fail this.
    func testASliceIsOnlyEverASubstringOfTheMealName() {
        let pairs: [(String, String)] = [
            ("gujarati DAL", plate),
            ("STEAMED RICE", plate),
            ("bhindi nu shaak", plate),
            ("idli", "Idlis with sambar"),
            ("dosas", "Dosa with chutney"),
            ("fish fry chicken", "Fish Fry, Chicken Sukka"),
            ("Spinach Cottage Cheese", "Palak Paneer, roti"),
            ("Dal Gujarati", "Gujarati style dal"),
            ("dal", "Dalia Upma"),
        ]

        let slices = pairs.map { candidate, mealName -> String? in
            let slice = RecipeVideoKeys.findDishSlice(candidate: candidate, mealName: mealName)
            if let slice {
                XCTAssertTrue(mealName.contains(slice), "\"\(mealName)\" should contain \"\(slice)\"")
            }
            return slice
        }

        // So the property cannot pass vacuously if findDishSlice started rejecting
        // everything: six of these nine pairs are expected to resolve.
        XCTAssertEqual(slices.compactMap { $0 }.count, 6)
    }

    // MARK: - matchSavedVideos

    func testBothDishesOfATwoDishMealAreFound() {
        // chicken sukka is longer, and length is the tie-break after token count
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideos(mealName: "Fish Fry, Chicken Sukka", videoURLs: map).map(\.key),
            ["chicken sukka", "fish fry"]
        )
    }

    func testMatchesAreOrderedByTokenCountBeforeCharacterLength() {
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideos(mealName: plate, videoURLs: map).map(\.key),
            ["gujarati dal", "dal"]
        )
    }

    func testAFullTieBreaksAlphabeticallySoPDFsAreReproducible() {
        let tied = [
            "aloo saag": "https://youtu.be/eeeeeeeeeee",
            "aloo gobi": "https://youtu.be/fffffffffff",
        ]
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideos(mealName: "Aloo Gobi and Aloo Saag", videoURLs: tied).map(\.key),
            ["aloo gobi", "aloo saag"]
        )
    }

    func testEntriesWithABlankURLAreSkippedWhichIsHowAPickIsCleared() {
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideos(
                mealName: "Dal Makhani",
                videoURLs: ["dal": "", "dal makhani": map["dal"]!]
            ),
            [SavedVideoMatch(key: "dal makhani", url: map["dal"]!)]
        )
    }

    func testALegacyEntryKeyedOnTheWholePlateStillResolves() {
        let legacy = [plate.lowercased(): map["gujarati dal"]!]
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideos(mealName: plate, videoURLs: legacy).map(\.key),
            [plate.lowercased()]
        )
    }

    func testABlankMealNameOrAMissingMapMatchesNothing() {
        XCTAssertTrue(RecipeVideoKeys.matchSavedVideos(mealName: "", videoURLs: map).isEmpty)
        XCTAssertTrue(RecipeVideoKeys.matchSavedVideos(mealName: plate, videoURLs: nil).isEmpty)
        XCTAssertTrue(RecipeVideoKeys.matchSavedVideos(mealName: plate, videoURLs: [:]).isEmpty)
    }

    // MARK: - matchSavedVideo

    func testTheSingleMatchIsTheMostSpecificOne() {
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideo(mealName: plate, videoURLs: map),
            map["gujarati dal"]
        )
    }

    func testThereIsNoSingleMatchWhenNothingMatches() {
        XCTAssertNil(RecipeVideoKeys.matchSavedVideo(mealName: "Poha", videoURLs: map))
        XCTAssertNil(RecipeVideoKeys.matchSavedVideo(mealName: plate, videoURLs: nil))
    }

    // MARK: - the write/read round trip

    func testASliceIsStoredUnderAKeyThatResolvesBackToTheMealItCameFrom() throws {
        let dish = RecipeVideoKeys.findDishSlice(candidate: "gujarati DAL", mealName: plate)
        XCTAssertEqual(dish, "Gujarati dal")

        let key = RecipeVideoKeys.storageKey(try XCTUnwrap(dish))
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal(key, mealName: plate))
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideo(mealName: plate, videoURLs: [key: map["gujarati dal"]!]),
            map["gujarati dal"]
        )
    }

    func testASliceCarryingPunctuationRoundTrips() throws {
        let mealName = "Fish Fry, Chicken Sukka"
        let slice = try XCTUnwrap(
            RecipeVideoKeys.findDishSlice(candidate: "fish fry chicken", mealName: mealName)
        )
        let key = RecipeVideoKeys.storageKey(slice)

        XCTAssertEqual(key, "fish fry, chicken")
        XCTAssertTrue(RecipeVideoKeys.keyMatchesMeal(key, mealName: mealName))
        XCTAssertEqual(
            RecipeVideoKeys.matchSavedVideo(mealName: mealName, videoURLs: [key: map["fish fry"]!]),
            map["fish fry"]
        )
    }

    // MARK: - resolveMainDish

    func testACachedAnswerIsReslicedIntoThisMealNamesOwnCasing() {
        XCTAssertEqual(
            RecipeVideoKeys.resolveMainDish(candidate: "gujarati dal", mealName: "Gujarati Dal, Steamed Rice"),
            "Gujarati Dal"
        )
    }

    func testAProposalThatIsNotARunOfWholeWordsInTheNameIsRefused() {
        XCTAssertNil(
            RecipeVideoKeys.resolveMainDish(candidate: "gujarati dal", mealName: "Palak Paneer, roti")
        )
    }

    func testABlankProposalIsRefusedSoTheCallerUsesTheFullName() {
        XCTAssertNil(RecipeVideoKeys.resolveMainDish(candidate: "", mealName: plate))
    }

    // MARK: - needsMainDishLookup

    func testANameOfTwoWordsOrFewerIsAlreadyADish() {
        XCTAssertFalse(RecipeVideoKeys.needsMainDishLookup("Palak Paneer"))
        XCTAssertFalse(RecipeVideoKeys.needsMainDishLookup("Poha"))
        XCTAssertFalse(RecipeVideoKeys.needsMainDishLookup(""))
    }

    func testALongerNameIsWorthNarrowing() {
        XCTAssertTrue(RecipeVideoKeys.needsMainDishLookup(plate))
        XCTAssertTrue(RecipeVideoKeys.needsMainDishLookup("Dal Makhani with rice"))
    }

    func testPaddingAndRepeatedSpacesDoNotMakeANameLongEnough() {
        XCTAssertFalse(RecipeVideoKeys.needsMainDishLookup("  Palak   Paneer  "))
    }
}
