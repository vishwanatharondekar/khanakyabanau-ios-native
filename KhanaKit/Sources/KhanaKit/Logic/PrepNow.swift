import Foundation

/// One prep step that has to be started now, or soon.
///
/// `startAt` is a wall-clock instant rather than the raw `startByMinutes`,
/// because that field is relative to a target midnight which differs between the
/// two selectors — see `PrepNow.due`.
public struct PrepDue: Hashable, Sendable {
    public var item: PrepTonightItem
    public var startAt: Date
    public var isOverdue: Bool

    public init(item: PrepTonightItem, startAt: Date, isOverdue: Bool) {
        self.item = item
        self.startAt = startAt
        self.isOverdue = isOverdue
    }
}

/// What the widget's urgency banner shows.
///
/// Composes the two existing selectors rather than reimplementing their rules —
/// whatever the reminders say, the widget says. They are disjoint by
/// construction (`PrepTonight` takes steps starting strictly before the morning
/// cutoff, `PrepAfternoon` at or after it), so nothing is ever counted twice.
///
/// Takes both days on purpose. Urgency is a property of the moment, not of the
/// day being shown: at 19:00 the thing that has to go in water is tomorrow's
/// breakfast batter, and a banner that stayed silent because the step belongs to
/// tomorrow would withhold the only time-critical fact on the screen.
///
/// Mirrors `PrepNow` in the Android `core:model` module; the worked examples in
/// both test suites must stay in step.
public enum PrepNow {

    /// Beyond this a step is not urgent — it is already legible on its meal's row.
    public static let defaultHorizon: TimeInterval = 3 * 3600

    /// Steps due now or within `horizon`, ordered by start time.
    ///
    /// Takes `WidgetMeal` lists rather than `DayMeals` so the widget can ask
    /// against the snapshot it already holds, without rehydrating a plan.
    public static func due(
        today: [WidgetMeal],
        tomorrow: [WidgetMeal],
        now: Date,
        calendar: Calendar = .current,
        horizon: TimeInterval = defaultHorizon
    ) -> [PrepDue] {
        let todayMidnight = calendar.startOfDay(for: now)
        guard let tomorrowMidnight = calendar.date(byAdding: .day, value: 1, to: todayMidnight)
        else { return [] }

        let candidates =
            items(from: today, source: .afternoon).map { ($0, todayMidnight) }
            + items(from: tomorrow, source: .tonight).map { ($0, tomorrowMidnight) }

        return candidates
            .compactMap { item, midnight -> PrepDue? in
                let startAt = midnight.addingTimeInterval(TimeInterval(item.startByMinutes * 60))
                let overdue = startAt <= now

                if overdue {
                    // Once the meal itself has passed, a step that should have
                    // started hours ago is no longer advice, it is nagging.
                    guard let mealMinutes = PrepTonight.nominalMealTimes[item.mealType] else {
                        return nil
                    }
                    let mealAt = midnight.addingTimeInterval(TimeInterval(mealMinutes * 60))
                    guard mealAt > now else { return nil }
                } else if startAt > now.addingTimeInterval(horizon) {
                    return nil
                }

                return PrepDue(item: item, startAt: startAt, isOverdue: overdue)
            }
            .sorted { $0.startAt < $1.startAt }
    }

    private enum Source { case afternoon, tonight }

    /// Rebuild a `DayMeals` from snapshot rows so the existing selectors can be
    /// reused unchanged. Only the fields they read are populated.
    private static func items(from meals: [WidgetMeal], source: Source) -> [PrepTonightItem] {
        var day = DayMeals()
        for meal in meals {
            var rebuilt = Meal(name: meal.name)
            rebuilt.prep = meal.prep
            // The snapshot stores `validPrep` only, so prepFor already matched
            // when it was written; restating it keeps `validPrep` true here.
            rebuilt.prepFor = meal.prep == nil ? nil : meal.name
            day[meal.type] = rebuilt
        }

        let enabled = meals.map(\.type)
        switch source {
        case .afternoon: return PrepAfternoon.itemsForThisAfternoon(day, enabledTypes: enabled)
        case .tonight: return PrepTonight.itemsForTomorrow(day, enabledTypes: enabled)
        }
    }
}
