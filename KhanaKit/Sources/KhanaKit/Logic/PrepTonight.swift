import Foundation

/// One advance-prep step that genuinely has to be started tonight.
public struct PrepTonightItem: Hashable, Sendable, Identifiable {
    public var mealType: MealType
    public var dish: String
    public var step: PrepStep
    /// When the step has to start, as minutes from midnight of the target day.
    /// Negative means the evening before — a 24-hour ferment for tomorrow's lunch
    /// lands at -660, i.e. 13:00 today.
    public var startByMinutes: Int

    public var id: String { "\(mealType.key)-\(dish)-\(step.text)" }

    public init(mealType: MealType, dish: String, step: PrepStep, startByMinutes: Int) {
        self.mealType = mealType
        self.dish = dish
        self.step = step
        self.startByMinutes = startByMinutes
    }
}

/// Which of tomorrow's advance prep genuinely has to be started tonight.
///
/// Port of `lib/prep-tonight.ts`. The server owns the notification — this exists so
/// the Tomorrow card can show the user exactly what they were (or will be) reminded
/// about, without a round-trip. The two implementations must agree.
public enum PrepTonight {

    /// When each course is assumed to be cooked, as minutes from midnight.
    ///
    /// Nominal, not per-user: knowing dinner is "evening" is enough to decide
    /// whether an 8-hour soak can start after breakfast tomorrow or has to go in
    /// water tonight, and asking every user when they eat would buy very little
    /// accuracy for a lot of friction.
    public static let nominalMealTimes: [MealType: Int] = [
        .breakfast: 8 * 60,
        .morningSnack: 11 * 60,
        .lunch: 13 * 60,
        .eveningSnack: 17 * 60,
        .dinner: 20 * 60,
    ]

    /// Anything that must be underway before this time on the target day can't
    /// reasonably be started that morning, so it belongs in tonight's reminder.
    public static let morningCutoffMinutes = 7 * 60

    /// The steps to start tonight for `tomorrow`'s meals.
    ///
    /// Takes no clock — everything is relative to the target day — so this is free
    /// of time-zone and DST arithmetic and trivially testable.
    ///
    /// Absent prep and empty prep both yield nothing, for different reasons: a slot
    /// with no prep has never been through generation and we don't know what it
    /// needs, while a slot with an empty step list has and genuinely needs nothing.
    public static func itemsForTomorrow(
        _ tomorrow: DayMeals,
        enabledTypes: [MealType] = MealType.allCases
    ) -> [PrepTonightItem] {
        var items: [PrepTonightItem] = []

        // Iterate the canonical order rather than the caller's list, so output
        // order is stable however `enabledTypes` was assembled.
        for type in MealType.allCases where enabledTypes.contains(type) {
            let meal = tomorrow[type]
            guard !meal.isEmpty,
                  let prep = meal.validPrep,
                  !prep.steps.isEmpty,
                  let mealTimeMinutes = nominalMealTimes[type]
            else { continue }

            for step in prep.steps {
                let startByMinutes = mealTimeMinutes - step.leadTimeMinutes
                // Strictly before the cutoff: a step that can start exactly at
                // 07:00 is a morning job, not a tonight job.
                guard startByMinutes < morningCutoffMinutes else { continue }
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

        // Most urgent first, matching the order the notification lists them in.
        // A stable sort keeps ties in course order.
        return items.enumerated()
            .sorted { ($0.element.startByMinutes, $0.offset) < ($1.element.startByMinutes, $1.offset) }
            .map(\.element)
    }

    /// Notification wording for a set of items.
    ///
    /// Port of `buildReminderCopy` in `lib/prep-tonight.ts`. It lives beside the
    /// selector for the same reason it does there: the wording depends on the same
    /// single-versus-many distinction, and both the server's push and the phone's
    /// own reminder have to read identically.
    public static func buildReminderCopy(
        items: [PrepTonightItem],
        tomorrowDayLabel: String
    ) -> (title: String, body: String, lines: [String]) {
        let lines = items.map { "\($0.step.text) — \($0.dish)" }

        if items.count == 1, let only = items.first {
            return (
                title: "Prep tonight for tomorrow",
                body: "\(only.dish): \(only.step.text)",
                lines: lines
            )
        }
        return (
            title: "\(items.count) things to prep tonight",
            body: "For \(tomorrowDayLabel): \(lines.first ?? "")",
            lines: lines
        )
    }
}
