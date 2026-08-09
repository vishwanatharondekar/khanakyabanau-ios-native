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

    init(api: APIClient) {
        self.api = api
    }

    /// Generates a week. The server does **not** save it — the caller merges the
    /// result into empty slots and PUTs the whole grid back.
    func generateWeek(
        weekStartDate: String,
        ingredients: [String] = [],
        moodCuisines: [String] = []
    ) async throws -> [String: DayMeals] {
        try await api.send(
            Endpoints.generateMeals(AIGenerateRequest(
                weekStartDate: weekStartDate,
                ingredients: ingredients,
                moodCuisines: moodCuisines
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
