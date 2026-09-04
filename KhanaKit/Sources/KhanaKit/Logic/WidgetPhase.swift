import Foundation

/// Whether the widget is showing you today or tomorrow, and when it switches.
///
/// The iOS widget is a single kind that decides this for itself, rather than the
/// two Glance widgets Android ships. A Tomorrow widget is dead space for most of
/// the day, and WidgetKit makes the alternative cheap: a timeline is a list of
/// dated entries, so the pivot is one more boundary handed to
/// `WidgetTimeline.entryDates` — not a reload, and not a clock read at render
/// time, which a widget cannot do anyway.
///
/// Pure and calendar-injected, like the prep selectors it sits beside, so the
/// awkward cases are testable without a simulator.
public enum WidgetPhase {

    public enum Phase: String, Sendable, Hashable {
        /// Today's plan.
        case day
        /// Tonight's remaining meals, then tomorrow's plan.
        case evening
    }

    /// 17:00 — the same wall-clock time as `nominalMealTimes[.eveningSnack]`.
    ///
    /// A constant rather than a value derived from the user's enabled meal types:
    /// someone who has turned the evening snack off still wants their evening to
    /// begin at the same hour, and deriving it would make the pivot jump around
    /// when they edit their settings.
    public static let eveningPivotMinutes = 17 * 60

    /// The pivot instant on `date`'s local day.
    ///
    /// Set on the calendar, never `startOfDay + n * 3600`. On a day the clock
    /// shifts, elapsed-time arithmetic lands at the wrong wall-clock hour — an
    /// hour late in spring, an hour early in autumn — and the widget switches to
    /// tomorrow at the wrong time or, if the hour is skipped entirely, not at all.
    public static func pivot(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: eveningPivotMinutes / 60,
            minute: eveningPivotMinutes % 60,
            second: 0,
            of: date
        ) ?? calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(eveningPivotMinutes * 60))
    }

    /// Which phase `date` falls in. The pivot instant itself is already evening,
    /// so the timeline entry scheduled *at* the pivot renders what it exists for.
    public static func phase(at date: Date, calendar: Calendar = .current) -> Phase {
        date < pivot(on: date, calendar: calendar) ? .day : .evening
    }

    /// The meal types on `date`'s day whose nominal time has not yet passed,
    /// in chronological order.
    ///
    /// Used for the evening phase's "tonight" section, so a widget at 19:00 offers
    /// dinner rather than reminding you about breakfast. Order comes from the
    /// nominal times rather than from the caller's array, so it is stable however
    /// the enabled types were assembled — the same reasoning `PrepAfternoon`
    /// applies to its own iteration.
    public static func upcoming(
        _ types: [MealType],
        at date: Date,
        calendar: Calendar = .current
    ) -> [MealType] {
        let startOfDay = calendar.startOfDay(for: date)
        let elapsed = calendar.dateComponents([.minute], from: startOfDay, to: date).minute ?? 0

        return types
            .compactMap { type -> (MealType, Int)? in
                guard let minutes = PrepTonight.nominalMealTimes[type] else { return nil }
                return minutes > elapsed ? (type, minutes) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
