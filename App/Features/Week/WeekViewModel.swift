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

/// Which view of a week is showing. Both are children of the same week.
enum WeekPane: Hashable {
    case meals, shopping
}

/// Every state the Shopping pane can be in. All seven are real, and they want
/// different UI — a guest at their ceiling needs an account, not a retry.
enum ShoppingPaneState: Hashable {
    /// Asking whether a list exists. Cheap, and spends nothing.
    case probing
    /// Actually building one. The slow, AI-backed path.
    case loading
    case ready
    case error(String)
    /// Guest out of free generations — offer an upgrade, not a retry.
    case limit
    /// The week has no dishes to derive a list from.
    case empty
    /// A week that has already happened, with no list stored from the time.
    case past
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
    /// The weeks on offer: this week, next week, and any further week with a plan.
    private(set) var chips: [WeekChip] = []
    /// Earlier weeks that hold a plan, for stepping back through history.
    private(set) var earlierWeeks: [String] = []
    /// Which view of the week is showing.
    var pane: WeekPane = .meals

    // Long-running AI work.
    private(set) var isGenerating = false
    private(set) var shoppingState: ShoppingPaneState = .probing
    /// The in-flight probe-or-generate, so a second open cannot start a second one.
    private var shoppingTask: Task<Void, Never>?

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

    /// At least one enabled slot on some day has no dish.
    var hasEmptySlots: Bool {
        DayOfWeek.allCases.contains { day in
            enabledTypes.contains { plan[day, $0].isEmpty }
        }
    }

    /// No dish anywhere in the week — this is what promotes the hero.
    var isEmptyWeek: Bool {
        DayOfWeek.allCases.allSatisfy { day in
            enabledTypes.allSatisfy { plan[day, $0].isEmpty }
        }
    }

    func trackOverflowOpen() {
        env.analytics.track(
            AnalyticsEvents.Navigation.overflowOpen,
            category: AnalyticsEvents.Category.navigation,
            parameters: [
                AnalyticsProperties.weekStart: weekStartDate,
                "is_empty_week": isEmptyWeek,
            ]
        )
    }

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
        await refreshChips()
    }

    func pullToRefresh() async {
        isRefreshing = true
        await env.videos.refresh()
        await refreshChips()
        await fetchWeek(showSpinner: false)
        isRefreshing = false
    }

    /// Both directions of the week strip.
    ///
    /// Separate from the week load because an imported multi-week plan can
    /// create weeks that need chips without changing the displayed week, so a
    /// week-keyed fetch would not notice. `weeksWithPlans` swallows failure: the
    /// strip falls back to this-week/next-week, which is what almost everyone
    /// sees anyway, and a missing chip must not take the week itself down.
    func refreshChips() async {
        let thisWeek = WeekDates.format(WeekDates.currentMonday())
        async let forward = env.meals.weeksWithPlans(from: thisWeek)
        async let back = env.meals.weeksWithPlans(from: thisWeek, direction: "back")
        let (upcoming, earlier) = await (forward, back)
        chips = buildWeekChips(weeksWithPlans: upcoming)
        earlierWeeks = earlier
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

    /// Go to a week by name rather than by direction.
    ///
    /// The old previous/next pager offered infinite navigation in both
    /// directions to serve neither case — nobody pages backwards through a meal
    /// planner and nobody plans three weeks out.
    func selectWeek(_ target: String) async {
        guard target != weekStartDate else { return }
        // Which chip was tapped, or that the week is off the strip entirely —
        // someone arriving from a months-old reminder.
        let kind = chips.first { $0.weekStartDate == target }.map { chip -> String in
            switch chip.kind {
            case .thisWeek: "this"
            case .nextWeek: "next"
            case .dated: "dated"
            }
        } ?? "off_rails"

        weekStartDate = target
        seenSuggestions.removeAll()
        // A late response from a week the user has already left must not
        // overwrite what they are looking at now.
        shoppingTask?.cancel()
        shoppingSession = nil
        shoppingState = .probing
        env.analytics.track(
            AnalyticsEvents.Navigation.weekChange,
            category: AnalyticsEvents.Category.navigation,
            parameters: [
                AnalyticsProperties.weekStart: weekStartDate,
                "chip_kind": kind,
            ]
        )
        await fetchWeek(showSpinner: true)
        await loadHistory()
        await refreshChips()
    }

    /// Changing week keeps you on the view you were already using, and vice versa.
    func selectPane(_ next: WeekPane) { pane = next }

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

    func generateWithAI(
        ingredients: [String],
        moodCuisines: [String],
        restrictToIngredients: Bool = false
    ) async {
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
                AnalyticsProperties.restrictToIngredients: restrictToIngredients,
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
                moodCuisines: moodCuisines,
                restrictToIngredients: restrictToIngredients
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

    /// The week's shopping list, fetched the moment the tab opens.
    ///
    /// Two steps, deliberately. A `cachedOnly` probe answers "is there already a
    /// list for this week?" for free — no AI call, no guest allowance spent —
    /// and only a miss starts a real generation. Without that split the tab
    /// could not open itself: firing the generating call on navigation would
    /// charge a guest for walking past.
    ///
    /// Nothing here blocks navigation: the loader renders inside the pane while
    /// the tab bar stays live, and a generation the user walks away from still
    /// finishes and still writes the server's cache, so coming back finds it.
    func openShopping(isGuestAtLimit: Bool) async {
        // Already showing this week's list — reopening the tab is not a reason
        // to re-probe, let alone regenerate.
        if shoppingSession?.weekStartDate == weekStartDate, shoppingState == .ready { return }
        if let shoppingTask, !shoppingTask.isCancelled { _ = await shoppingTask.value; return }

        let task = Task { @MainActor in
            shoppingState = .probing

            let probe = try? await env.ai.shoppingList(for: plan, cachedOnly: true)
            let cached = probe.map { !$0.absent } ?? false

            switch shoppingOpenOutcome(
                weekStartDate: weekStartDate,
                cached: cached,
                hasDishes: !plan.allDishNames().isEmpty,
                isGuestAtLimit: isGuestAtLimit
            ) {
            case .show:
                if let probe { apply(probe) }
            case .empty:
                shoppingState = .empty
            case .past:
                shoppingState = .past
            case .limit:
                shoppingState = .limit
            case .generate:
                await generateShoppingList()
            }
        }
        shoppingTask = task
        await task.value
        shoppingTask = nil
    }

    /// An explicit retry after a failure. Skips the probe — it already missed.
    func retryShopping() async {
        await generateShoppingList()
    }

    private func generateShoppingList() async {
        shoppingState = .loading
        // Fire at request time, not response, to mirror the webapp's behaviour
        // and capture attempts that fail server-side.
        env.analytics.track(
            AnalyticsEvents.AI.extractIngredients,
            category: AnalyticsEvents.Category.aiFeatures,
            parameters: [AnalyticsProperties.weekStart: weekStartDate]
        )
        do {
            apply(try await env.ai.shoppingList(for: plan))
        } catch APIError.guestLimitReached {
            // The ceiling and a real failure want different UI: an account, not
            // a retry.
            shoppingState = .limit
        } catch let error as APIError {
            shoppingState = .error(
                error.userMessage(fallback: "Failed to generate shopping list")
            )
        } catch {
            shoppingState = .error("Failed to generate shopping list")
        }
    }

    private func apply(_ list: ShoppingList) {
        shoppingSession = ShoppingSession(list: list, weekStartDate: weekStartDate)
        shoppingState = .ready
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
