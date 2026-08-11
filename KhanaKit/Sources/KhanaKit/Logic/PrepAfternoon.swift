import Foundation

/// Which of today's advance prep for the evening meals has to be started this
/// afternoon.
///
/// Port of `lib/prep-afternoon.ts`, and companion to `PrepTonight`. That one
/// answers "what can't wait until tomorrow morning?" against tomorrow's plan;
/// this answers "what can't wait until I start cooking dinner?" against today's.
/// The two are disjoint by construction — `PrepTonight` takes steps starting
/// strictly before its cutoff, this takes steps starting at or after it — so no
/// step is ever shown or scheduled twice.
public enum PrepAfternoon {

    /// The meals a midday reminder can still help with, in chronological order.
    ///
    /// An explicit list, not derived from the bounds below, because lunch would
    /// otherwise leak through: a 5-hour lead for a 13:00 lunch starts at 08:00,
    /// which satisfies both bounds but has already passed by the time the reminder
    /// fires. `breakfast` and `morningSnack` do self-exclude — any lead over
    /// `minAfternoonLeadMinutes` puts them before the morning cutoff — but leaning
    /// on that for lunch too would be wrong.
    public static let afternoonMealTypes: [MealType] = [.eveningSnack, .dinner]

    /// Below this, a step is just cooking.
    ///
    /// A two-hour marinade for a 20:00 dinner starts at 18:00, by which time the
    /// user is home and about to cook anyway. Compared strictly, so prep needing
    /// exactly four hours is excluded.
    public static let minAfternoonLeadMinutes = 240

    /// The steps to start this afternoon for `today`'s meals.
    ///
    /// Takes no clock — everything is relative to the target day — so this is free
    /// of time-zone and DST arithmetic and trivially testable.
    ///
    /// Absent prep and empty prep both yield nothing, for different reasons: a
    /// slot with no prep has never been through generation and we don't know what
    /// it needs, while a slot with an empty step list has and needs nothing.
    public static func itemsForThisAfternoon(
        _ today: DayMeals,
        enabledTypes: [MealType] = MealType.allCases
    ) -> [PrepTonightItem] {
        var items: [PrepTonightItem] = []

        // Iterate the canonical list rather than the caller's, so output order is
        // stable however `enabledTypes` was assembled.
        for type in afternoonMealTypes where enabledTypes.contains(type) {
            let meal = today[type]
            guard !meal.isEmpty,
                  let prep = meal.validPrep,
                  !prep.steps.isEmpty,
                  let mealTimeMinutes = PrepTonight.nominalMealTimes[type]
            else { continue }

            for step in prep.steps {
                // Strictly greater: exactly four hours is cooking-time prep.
                guard step.leadTimeMinutes > minAfternoonLeadMinutes else { continue }

                let startByMinutes = mealTimeMinutes - step.leadTimeMinutes

                // At or after the cutoff. Below it, last night's reminder already
                // covered this step and the start time has passed regardless.
                guard startByMinutes >= PrepTonight.morningCutoffMinutes else { continue }

                items.append(
                    PrepTonightItem(
                        mealType: type,
                        dish: meal.name,
                        step: step,
                        startByMinutes: startByMinutes
                    )
                )
            }
        }

        // Most urgent first, matching the order the reminder lists them in.
        // A stable sort keeps ties in course order.
        return items.enumerated()
            .sorted { ($0.element.startByMinutes, $0.offset) < ($1.element.startByMinutes, $1.offset) }
            .map(\.element)
    }

    /// Notification wording for a set of afternoon items.
    ///
    /// Carries no day label, unlike `PrepTonight.buildReminderCopy`: the evening
    /// reminder needs one because it describes another day, this is about today.
    public static func buildAfternoonReminderCopy(
        items: [PrepTonightItem]
    ) -> (title: String, body: String, lines: [String]) {
        let lines = items.map { "\($0.step.text) — \($0.dish)" }

        if items.count == 1, let only = items.first {
            return (
                title: "Prep this afternoon",
                body: "\(only.dish): \(only.step.text)",
                lines: lines
            )
        }
        return (
            title: "\(items.count) things to prep this afternoon",
            body: lines.first ?? "",
            lines: lines
        )
    }
}
