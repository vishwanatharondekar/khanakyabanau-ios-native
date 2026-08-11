import Foundation
import KhanaKit
import SwiftUI

/// One day's worth of the Today screen.
struct DaySection: Equatable {
    var day: DayOfWeek = .monday
    var date: PlanDate = WeekDates.today()
    var meals: DayMeals = DayMeals()

    var weekStartDate: String { WeekDates.format(WeekDates.mondayOf(date)) }
}

/// Backs "Today's Menu", the Tomorrow screen and the meal detail page — all three
/// only ever show today or tomorrow, so they share one source of truth.
@MainActor
@Observable
final class TodayViewModel {
    private(set) var isLoading = true
    private(set) var isResolvingImages = false
    private(set) var today = DaySection()
    private(set) var tomorrow = DaySection()
    var errorMessage: String?
    var toast: String?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var enabledTypes: [MealType] { env.settings.enabledTypes }
    var showCalories: Bool { env.settings.showCalories }

    /// Derived rather than stored: `tomorrow` and `enabledTypes` arrive from two
    /// independent sources, and caching this would let them disagree for a frame.
    var tomorrowPrep: [PrepTonightItem] {
        PrepTonight.itemsForTomorrow(tomorrow.meals, enabledTypes: enabledTypes)
    }

    /// Today's prep that still has to be started this afternoon — the same set the
    /// midday reminder covers.
    var afternoonPrep: [PrepTonightItem] {
        PrepAfternoon.itemsForThisAfternoon(today.meals, enabledTypes: enabledTypes)
    }

    private var hasLoaded = false

    /// First load only. Re-entering a screen must not refetch — Tomorrow asks for
    /// an explicit `refresh()` when it genuinely needs fresh data.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await env.settings.ensureMealSettings()
        await refresh(showSpinner: true)
        // A cancelled or failed first load must not latch — otherwise `.task`
        // never retries and the screen is stuck on its placeholder day.
        if errorMessage != nil || Task.isCancelled { hasLoaded = false }
    }

    func pullToRefresh() async {
        await env.videos.refresh()
        await refresh(showSpinner: false)
    }

    func refresh(showSpinner: Bool = false) async {
        if showSpinner { isLoading = true }

        let todayDate = WeekDates.today()
        let tomorrowDate = todayDate.adding(days: 1)
        let todayMonday = WeekDates.mondayOf(todayDate)
        let tomorrowMonday = WeekDates.mondayOf(tomorrowDate)

        do {
            let todayPlan = try await env.meals.week(WeekDates.format(todayMonday))
            // On a Sunday, tomorrow's Monday belongs to next week — fetch it rather
            // than showing an empty card.
            let tomorrowPlan: MealPlan
            if tomorrowMonday == todayMonday {
                tomorrowPlan = todayPlan
            } else {
                tomorrowPlan = (try? await env.meals.week(WeekDates.format(tomorrowMonday)))
                    ?? .empty(weekStartDate: WeekDates.format(tomorrowMonday))
            }

            today = DaySection(
                day: todayDate.dayOfWeek,
                date: todayDate,
                meals: todayPlan.meals(for: todayDate.dayOfWeek)
            )
            tomorrow = DaySection(
                day: tomorrowDate.dayOfWeek,
                date: tomorrowDate,
                meals: tomorrowPlan.meals(for: tomorrowDate.dayOfWeek)
            )
            errorMessage = nil
            isLoading = false
            await resolveImages()
        } catch let error as APIError {
            seedEmptySections(today: todayDate, tomorrow: tomorrowDate)
            errorMessage = error.userMessage(fallback: "Failed to load today's meals")
        } catch {
            seedEmptySections(today: todayDate, tomorrow: tomorrowDate)
            errorMessage = "Failed to load today's meals"
        }
        isLoading = false
    }

    /// Without this a failed fetch leaves both sections at their default
    /// `DaySection()` — which says Monday, and dates today as tomorrow.
    private func seedEmptySections(today todayDate: PlanDate, tomorrow tomorrowDate: PlanDate) {
        today = DaySection(day: todayDate.dayOfWeek, date: todayDate, meals: DayMeals())
        tomorrow = DaySection(day: tomorrowDate.dayOfWeek, date: tomorrowDate, meals: DayMeals())
    }

    private func resolveImages() async {
        var names: [String] = []
        for type in MealType.allCases {
            let todayMeal = today.meals[type]
            if !todayMeal.isEmpty, todayMeal.imageUrl == nil { names.append(todayMeal.name) }
            let tomorrowMeal = tomorrow.meals[type]
            if !tomorrowMeal.isEmpty, tomorrowMeal.imageUrl == nil { names.append(tomorrowMeal.name) }
        }
        guard !names.isEmpty else {
            isResolvingImages = false
            return
        }
        isResolvingImages = true
        let images = await env.meals.resolveImages(for: names)
        today.meals = applyImages(images, to: today.meals)
        tomorrow.meals = applyImages(images, to: tomorrow.meals)
        isResolvingImages = false
    }

    private func applyImages(_ images: [String: String], to meals: DayMeals) -> DayMeals {
        var updated = meals
        for type in MealType.allCases {
            let meal = updated[type]
            guard meal.imageUrl == nil, !meal.isEmpty,
                  let image = images[meal.name.lowercased()] else { continue }
            var copy = meal
            copy.imageUrl = image
            updated[type] = copy
        }
        return updated
    }

    /// Today and tomorrow are the only two days the detail page can resolve, which
    /// is exactly what Android does — a slot from any other day has no route here.
    func section(for day: DayOfWeek) -> DaySection? {
        if day == today.day { return today }
        if day == tomorrow.day { return tomorrow }
        return nil
    }

    /// The week a given day belongs to. Today and tomorrow straddle a week boundary
    /// when today is Sunday, so this cannot assume the current week.
    func weekStart(for day: DayOfWeek) -> String {
        section(for: day)?.weekStartDate ?? WeekDates.format(WeekDates.currentMonday())
    }
}
