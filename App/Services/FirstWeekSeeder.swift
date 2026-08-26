import Foundation
import KhanaKit

/// Builds the very first week for a user who has just finished onboarding.
///
/// Android does this inline as phase 2 of `OnboardingViewModel.complete()`; the web
/// client does it from the planner once the week has loaded
/// (`MealPlanner.tsx:246-280`). Here it is its own unit because the work spans two
/// repositories — the AI call and the meal-plan write — and neither is the natural
/// owner of the other.
///
/// Nothing here throws. By the time this runs, onboarding has already saved the
/// user's preferences and flipped `onboardingCompleted`, so a failure must not keep
/// them off Home. They land on an empty week instead, and the Week tab's AI button
/// — which does surface errors and guest limits — is there when they want it.
@MainActor
final class FirstWeekSeeder {
    private let ai: AiRepository
    private let meals: MealRepository
    private let prepReminders: PrepReminderScheduler

    init(ai: AiRepository, meals: MealRepository, prepReminders: PrepReminderScheduler) {
        self.ai = ai
        self.meals = meals
        self.prepReminders = prepReminders
    }

    /// Generates and saves the current week, but only if it is still empty.
    ///
    /// - Returns: the week key that was written, or nil when nothing was — which
    ///   covers "the week already had meals" as well as every failure.
    func seedCurrentWeek() async -> String? {
        let weekStartDate = WeekDates.format(WeekDates.currentMonday())

        // Read before generating. Android skips this and PUTs the AI grid straight
        // over whatever the week held, so a network blip during onboarding can
        // clobber an existing plan — most likely one just imported from the web
        // client. The web client guards the same way (`MealPlanner.tsx:480`).
        guard let existing = try? await meals.week(weekStartDate) else { return nil }

        // A week with anything in it is left alone: generating over it would both
        // discard dishes the user chose and spend one of a guest's three lifetime
        // AI credits.
        guard existing.allDishNames().isEmpty else { return nil }

        guard let generated = try? await ai.generateWeek(weekStartDate: weekStartDate) else {
            return nil
        }

        // Fill-empty-only — the same merge the Week tab's AI button uses. The week
        // was empty a moment ago, so this is belt-and-braces rather than load
        // bearing, and it keeps one rule for how generated dishes land in a plan.
        let plan = existing.mergingFillingEmpty(with: generated)
        guard !plan.allDishNames().isEmpty else { return nil }

        do {
            _ = try await meals.save(plan)
        } catch {
            return nil
        }
        return weekStartDate
    }

    /// Advance prep for a week that was just seeded, and the local reminders that
    /// depend on it.
    ///
    /// Split out from [seedCurrentWeek] so the caller decides whether to wait for
    /// it. Onboarding fires this detached: a second slow AI call would hold the user
    /// on the onboarding screen with nothing new to show them. Silent throughout —
    /// they are already on Home by the time it lands, and prep is a background
    /// nicety that `WeekViewModel.refreshPrep` treats exactly the same way.
    func fillPrep(weekStartDate: String) async {
        _ = try? await meals.generatePrep(weekStartDate: weekStartDate, wholeWeek: true)
        await prepReminders.reschedule()
    }
}
