import Foundation
import KhanaKit
import SwiftUI

/// A generated shopping list, wrapped so it can drive `.sheet(item:)`.
struct ShoppingSession: Identifiable {
    let id = UUID()
    var list: ShoppingList
    var weekStartDate: String
}

/// Which slot a dialog or sheet is acting on.
struct SlotTarget: Identifiable, Hashable {
    var day: DayOfWeek
    var type: MealType
    var id: String { "\(day.key)-\(type.key)" }
}

@MainActor
@Observable
final class WeekViewModel {
    // Load state.
    private(set) var isLoading = true
    private(set) var isRefreshing = false
    private(set) var isSaving = false
    private(set) var isResolvingImages = false

    // Content.
    private(set) var weekStartDate: String = WeekDates.format(WeekDates.currentMonday())
    private(set) var plan: MealPlan = .empty(weekStartDate: WeekDates.format(WeekDates.currentMonday()))
    private(set) var history: [MealPlan] = []

    // Long-running AI work.
    private(set) var isGenerating = false
    private(set) var isBuildingShoppingList = false

    // Messages.
    var errorMessage: String?
    var toast: String?

    // Sheets and dialogs.
    var editing: SlotTarget?
    var suggesting: SlotTarget?
    var isAIPromptOpen = false
    var isClearConfirmOpen = false
    var shoppingSession: ShoppingSession?
    var guestLimitPrompt: String?

    /// Names already offered for a slot, so "fresh ideas" keeps producing new ones.
    private var seenSuggestions: [String: Set<String>] = [:]

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var weekRangeLabel: String { WeekDates.rangeLabel(weekStartDate: weekStartDate) }
    var enabledTypes: [MealType] { env.settings.enabledTypes }
    var showCalories: Bool { env.settings.showCalories }

    var todayIndex: Int? { WeekDates.todayIndex(in: weekStartDate) }
    var tomorrowIndex: Int? { WeekDates.tomorrowIndex(in: weekStartDate) }

    // MARK: - Loading

    private var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await env.settings.ensureMealSettings()
        await fetchWeek(showSpinner: true)
        await loadHistory()
    }

    func pullToRefresh() async {
        isRefreshing = true
        await env.videos.refresh()
        await fetchWeek(showSpinner: false)
        isRefreshing = false
    }

    private func fetchWeek(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        do {
            plan = try await env.meals.week(weekStartDate)
            errorMessage = nil
            // Show the grid now; thumbnails shimmer in behind it. Awaiting image
            // resolution here would hold the full-screen spinner over a complete
            // week for the duration of a second round trip.
            isLoading = false
            await resolveImages()
        } catch let error as APIError {
            // Keep an empty grid on screen rather than a blank page — the user can
            // still plan offline-ish and retry.
            plan = .empty(weekStartDate: weekStartDate)
            errorMessage = error.userMessage(fallback: "Failed to load meals")
            // Let the next appearance retry rather than living with an empty grid.
            hasLoaded = false
        } catch {
            plan = .empty(weekStartDate: weekStartDate)
            errorMessage = "Failed to load meals"
            hasLoaded = false
        }
        isLoading = false
    }

    private func loadHistory() async {
        history = (try? await env.meals.history(targetWeek: weekStartDate)) ?? []
    }

    private func resolveImages() async {
        let names = plan.mealNamesMissingImages()
        guard !names.isEmpty else {
            isResolvingImages = false
            return
        }
        isResolvingImages = true
        let images = await env.meals.resolveImages(for: names)
        plan = plan.withImages(images)
        isResolvingImages = false
    }

    // MARK: - Week navigation

    func goToPreviousWeek() async { await changeWeek(by: -1, direction: "prev") }
    func goToNextWeek() async { await changeWeek(by: 1, direction: "next") }

    private func changeWeek(by weeks: Int, direction: String) async {
        weekStartDate = WeekDates.shift(weekStartDate: weekStartDate, byWeeks: weeks)
        seenSuggestions.removeAll()
        env.analytics.track(
            AnalyticsEvents.Navigation.weekChange,
            category: AnalyticsEvents.Category.navigation,
            parameters: [
                AnalyticsProperties.direction: direction,
                AnalyticsProperties.weekStart: weekStartDate,
            ]
        )
        await fetchWeek(showSpinner: true)
        await loadHistory()
    }

    // MARK: - Editing

    func meal(_ day: DayOfWeek, _ type: MealType) -> Meal { plan[day, type] }

    /// A tap on an empty slot opens suggestions; a filled slot opens the rename
    /// dialog. Replacing a filled slot is the explicit swap button.
    func confirmEdit(target: SlotTarget, name: String, imageUrl: String? = nil) async {
        let previous = plan[target.day, target.type]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasEmpty = previous.isEmpty
        let isEmpty = trimmed.isEmpty

        let action: String? = switch (wasEmpty, isEmpty) {
        case (true, false): AnalyticsEvents.Meal.add
        case (false, false): AnalyticsEvents.Meal.update
        case (false, true): AnalyticsEvents.Meal.delete
        case (true, true): nil
        }
        if let action {
            env.analytics.track(
                action,
                category: AnalyticsEvents.Category.mealPlanning,
                label: "\(target.day.key)_\(target.type.key)",
                parameters: [
                    AnalyticsProperties.day: target.day.key,
                    AnalyticsProperties.mealType: target.type.key,
                    AnalyticsProperties.mealName: trimmed,
                    AnalyticsProperties.isNewMeal: wasEmpty,
                    AnalyticsProperties.weekStart: weekStartDate,
                ] as [String: Any]
            )
        }

        plan = plan.withMeal(
            day: target.day, type: target.type, name: trimmed, imageUrl: imageUrl
        )

        // Prep only needs regenerating when the dish genuinely changed. Saving an
        // unchanged name must not burn an AI call.
        let dishChanged = !isEmpty
            && trimmed != previous.name.trimmingCharacters(in: .whitespacesAndNewlines)
        await save(prepTargets: dishChanged ? [target] : [])

        if imageUrl == nil, !isEmpty {
            if let resolved = await env.meals.image(for: trimmed) {
                plan = plan.withImages([trimmed.lowercased(): resolved])
            }
        }
    }

    /// Picking from the suggestion sheet. Carries the resolved thumbnail through so
    /// the tapped card doesn't shimmer back to a placeholder.
    func applySuggestion(target: SlotTarget, name: String, imageUrl: String?) async {
        let wasEmpty = plan[target.day, target.type].isEmpty
        env.analytics.track(
            wasEmpty ? AnalyticsEvents.Meal.add : AnalyticsEvents.Meal.update,
            category: AnalyticsEvents.Category.mealPlanning,
            label: "\(target.day.key)_\(target.type.key)",
            parameters: [
                AnalyticsProperties.day: target.day.key,
                AnalyticsProperties.mealType: target.type.key,
                AnalyticsProperties.mealName: name,
                AnalyticsProperties.isNewMeal: wasEmpty,
                AnalyticsProperties.weekStart: weekStartDate,
                AnalyticsProperties.source: "suggestion",
            ] as [String: Any]
        )
        plan = plan.withMeal(day: target.day, type: target.type, name: name, imageUrl: imageUrl)
        await save(prepTargets: [target])

        // "Write your own" picks arrive without a thumbnail.
        if imageUrl == nil, let resolved = await env.meals.image(for: name) {
            plan = plan.withImages([name.lowercased(): resolved])
        }
    }

    func clearWeek() async {
        env.analytics.track(
            AnalyticsEvents.Meal.clearWeek,
            category: AnalyticsEvents.Category.mealPlanning,
            parameters: [AnalyticsProperties.weekStart: weekStartDate]
        )
        // There is no DELETE route — clearing is a PUT of the empty grid.
        plan = .empty(weekStartDate: weekStartDate)
        await save(prepTargets: [])
        toast = "All meals cleared for this week!"
    }

    // MARK: - Saving

    private func save(prepTargets: [SlotTarget], prepWholeWeek: Bool = false) async {
        // Captured up front: prep generation is a slow AI call, and the user can
        // page to another week while it runs. Reading the live property afterwards
        // would POST prep against — and merge it into — the wrong week.
        let savedWeek = plan.weekStartDate
        isSaving = true
        do {
            // Only the identifiers are taken from the response. Adopting the echoed
            // plan would strip every cached imageUrl — PUT does not enhance images.
            let ids = try await env.meals.save(plan)
            if plan.id == nil { plan.id = ids.id }
            if plan.userId == nil { plan.userId = ids.userId }
            errorMessage = nil

            if prepWholeWeek || !prepTargets.isEmpty {
                await refreshPrep(
                    week: savedWeek, targets: prepTargets, wholeWeek: prepWholeWeek
                )
            }
            // What needs soaking tonight just changed. Re-laying the local
            // reminders is cheap and keeps them honest.
            Task { await env.prepReminders.reschedule() }
        } catch let error as APIError {
            errorMessage = error.userMessage(fallback: "Failed to update meal")
        } catch {
            errorMessage = "Failed to update meal"
        }
        isSaving = false
    }

    /// Prep generation is deliberately silent — no spinner, no error, no toast.
    /// It is a background nicety, and a failed prep call must not look like a
    /// failed save.
    private func refreshPrep(week: String, targets: [SlotTarget], wholeWeek: Bool) async {
        let pairs = targets.map { (day: $0.day, type: $0.type) }
        guard let refreshed = try? await env.meals.generatePrep(
            weekStartDate: week, targets: pairs, wholeWeek: wholeWeek
        ) else { return }
        // The user may have navigated away while the AI worked; merging then would
        // graft one week's prep onto another.
        guard plan.weekStartDate == week else { return }
        // Only prep crosses over; adopting `refreshed` wholesale would drop images.
        plan = plan.withPrepFrom(refreshed)
    }

    // MARK: - AI generation

    func generateWithAI(ingredients: [String], moodCuisines: [String]) async {
        isAIPromptOpen = false
        isGenerating = true

        // Fired at request time rather than on success, matching the other clients,
        // so abandoned and failed attempts still show up in the funnel.
        env.analytics.track(
            AnalyticsEvents.AI.generateMeals,
            category: AnalyticsEvents.Category.aiFeatures,
            parameters: [
                AnalyticsProperties.weekStart: weekStartDate,
                AnalyticsProperties.hasIngredients: !ingredients.isEmpty,
                AnalyticsProperties.ingredientCount: ingredients.count,
                AnalyticsProperties.moodCuisineCount: moodCuisines.count,
            ] as [String: Any]
        )
        if !moodCuisines.isEmpty {
            env.analytics.track(
                AnalyticsEvents.Mood.submit,
                category: AnalyticsEvents.Category.mood,
                parameters: [AnalyticsProperties.moodCuisineCount: moodCuisines.count]
            )
        }

        do {
            let generated = try await env.ai.generateWeek(
                weekStartDate: weekStartDate,
                ingredients: ingredients,
                moodCuisines: moodCuisines
            )
            // Fill-empty-only: generation never overwrites a dish the user chose.
            plan = plan.mergingFillingEmpty(with: generated)
            await save(prepTargets: [], prepWholeWeek: true)
            await resolveImages()
            if !moodCuisines.isEmpty {
                env.analytics.track(
                    AnalyticsEvents.Mood.applySuggestion, category: AnalyticsEvents.Category.mood
                )
            }
            toast = "AI suggestions added to empty slots"
        } catch let APIError.guestLimitReached(message, info) {
            guestLimitPrompt = message ?? guestLimitCopy(remaining: info?.remaining ?? 0)
        } catch let error as APIError {
            errorMessage = error.userMessage(fallback: "Failed to generate AI suggestions")
        } catch {
            errorMessage = "Failed to generate AI suggestions"
        }
        isGenerating = false
    }

    private func guestLimitCopy(remaining: Int) -> String {
        "You've used your free AI generations. Create a free account for unlimited access."
    }

    // MARK: - Shopping list

    func buildShoppingList() async {
        guard !plan.allDishNames().isEmpty else {
            errorMessage = "Please add some meals to your plan first"
            return
        }
        isBuildingShoppingList = true
        env.analytics.track(
            AnalyticsEvents.AI.extractIngredients,
            category: AnalyticsEvents.Category.aiFeatures,
            parameters: [AnalyticsProperties.weekStart: weekStartDate]
        )
        do {
            let list = try await env.ai.shoppingList(for: plan)
            shoppingSession = ShoppingSession(list: list, weekStartDate: weekStartDate)
        } catch let APIError.guestLimitReached(message, _) {
            guestLimitPrompt = message
                ?? "You've used your free shopping lists. Create a free account for unlimited access."
        } catch let error as APIError {
            errorMessage = error.userMessage(fallback: "Failed to generate shopping list")
        } catch {
            errorMessage = "Failed to generate shopping list"
        }
        isBuildingShoppingList = false
    }

    // MARK: - Suggestions

    /// The user's cuisine preferences, mirrored from the profile that `SessionStore`
    /// owns so suggestion building can stay synchronous.
    var cuisinePreferences: [String] = []

    /// The list shown the moment the sheet opens: the user's own meals for this
    /// slot in recent weeks, topped up from their cuisine preferences. No network,
    /// so the sheet has content immediately.
    func initialSuggestions(for target: SlotTarget) -> [String] {
        MealSuggestions.buildInitial(
            cuisines: cuisinePreferences,
            vegetarian: env.settings.isVegetarian,
            history: history,
            type: target.type
        )
    }

    func freshSuggestions(for target: SlotTarget, current: [String]) async -> [String] {
        var seen = seenSuggestions[target.id] ?? []
        seen.formUnion(current.map { $0.lowercased() })
        seenSuggestions[target.id] = seen

        env.analytics.track(
            AnalyticsEvents.AI.suggestMeal,
            category: AnalyticsEvents.Category.aiFeatures,
            parameters: [AnalyticsProperties.mealType: target.type.key]
        )

        do {
            let fresh = try await env.ai.freshSuggestions(
                for: target.type, excluding: Array(seen)
            )
            if fresh.isEmpty {
                toast = "No new ideas — try editing your cuisine preferences."
                return current
            }
            seenSuggestions[target.id]?.formUnion(fresh.map { $0.lowercased() })
            return fresh
        } catch {
            toast = "Could not fetch suggestions. Please try again."
            return current
        }
    }
}
