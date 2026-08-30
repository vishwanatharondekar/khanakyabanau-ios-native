import Foundation
import KhanaKit

/// The AI-backed operations: week generation, shopping lists and fresh suggestions.
///
/// None of these stream — the server returns a complete JSON body — and a meal plan
/// or shopping list can take most of a minute, which is why they run on the long
/// timeout profile and every caller shows a blocking loader.
@MainActor
final class AiRepository {
    private let api: APIClient

    /// Answers per meal name, lowercased. The answer for a name never changes and
    /// meal names repeat across a plan, so one lookup per name per session is enough.
    /// A definite "no narrowing" is cached too; a failed call is not, so a flaky
    /// network doesn't decide the whole session.
    private var mainDishCache: [String: String?] = [:]

    init(api: APIClient) {
        self.api = api
    }

    /// The dish inside `mealName` that a recipe video should be filed under, or nil
    /// to use the meal name as it stands.
    ///
    /// Nil covers every "no better answer" alike: a name too short to narrow, a model
    /// answer that wasn't a run of whole words in the name, an unconfigured AI
    /// provider, and a failed request. Callers fall back to the full meal name, which
    /// is what they did before this existed — so this never throws.
    ///
    /// What comes back is re-sliced locally as well as server-side: this string
    /// becomes a storage key, and the key has to be a substring of the meal name for
    /// the video to resolve back to it (`RecipeVideoKeys.findDishSlice`).
    func mainDish(for mealName: String) async -> String? {
        let name = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RecipeVideoKeys.needsMainDishLookup(name) else { return nil }

        let cacheKey = name.lowercased()
        if let cached = mainDishCache[cacheKey] { return cached }

        do {
            let response = try await api.send(
                Endpoints.mainDish(MainDishRequest(mealName: name)),
                as: MainDishResponse.self
            )
            let candidate = (response.mainDish ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let dish: String?
            if !response.identified || candidate.caseInsensitiveCompare(name) == .orderedSame {
                dish = nil
            } else {
                dish = RecipeVideoKeys.resolveMainDish(candidate: candidate, mealName: name)
            }

            mainDishCache[cacheKey] = dish
            return dish
        } catch {
            // Not cached: a transient failure should not stick for the session.
            return nil
        }
    }

    /// Generates a week. The server does **not** save it — the caller merges the
    /// result into empty slots and PUTs the whole grid back.
    func generateWeek(
        weekStartDate: String,
        ingredients: [String] = [],
        moodCuisines: [String] = [],
        restrictToIngredients: Bool = false
    ) async throws -> [String: DayMeals] {
        try await api.send(
            Endpoints.generateMeals(AIGenerateRequest(
                weekStartDate: weekStartDate,
                ingredients: ingredients,
                moodCuisines: moodCuisines,
                restrictToIngredients: restrictToIngredients
            )),
            as: [String: DayMeals].self
        )
    }

    /// One full-week list. The server caches it against a hash of the plan, so an
    /// unchanged week costs no AI call and no guest quota.
    func shoppingList(for plan: MealPlan) async throws -> ShoppingList {
        var flatNames: [String] = []
        var dayWise: [String: [String: String]] = [:]

        for day in DayOfWeek.allCases {
            let meals = plan.meals(for: day)
            var courses: [String: String] = [:]
            for type in MealType.allCases {
                let meal = meals[type]
                guard !meal.isEmpty else { continue }
                courses[type.key] = meal.name
                flatNames.append(meal.name)
            }
            if !courses.isEmpty { dayWise[day.key] = courses }
        }

        return try await api.send(
            Endpoints.shoppingList(ShoppingListRequest(
                meals: flatNames,
                dayWiseMeals: dayWise,
                portions: 1,
                weekStartDate: plan.weekStartDate
            )),
            as: ShoppingList.self
        )
    }

    /// Persists the ticked-off items. Debounced by the caller; the server dedupes
    /// and lowercases, and caps the list at 500 entries.
    func updateHaveAlready(weekStartDate: String, names: [String]) async throws {
        _ = try await api.send(Endpoints.updateHaveAlready(
            weekStartDate, UpdateHaveAlreadyRequest(haveAlready: names)
        ))
    }

    /// "Fresh ideas" — scored from the server-side corpus, no LLM involved, so it
    /// is fast, free, and outside the guest quota.
    func freshSuggestions(for type: MealType, excluding exclude: [String]) async throws -> [String] {
        try await api.send(
            Endpoints.corpusSuggestions(
                CorpusSuggestionsRequest(mealType: type.key, exclude: exclude)
            ),
            as: CorpusSuggestionsResponse.self
        ).suggestions
    }
}
