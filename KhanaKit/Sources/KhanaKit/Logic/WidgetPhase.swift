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
        /// What is still to come today.
        case today
        /// Today's remainder — usually just dinner — plus a look at tomorrow.
        case tonight
        /// Today is cooked. Tomorrow's plan, in full.
        case tomorrow
    }

    /// How long a meal stays on the widget past its nominal time.
    ///
    /// `nominalMealTimes` are when a meal is *assumed* to be cooked, not when
    /// anyone actually cooks it, and they exist to schedule prep rather than to
    /// decide what is on screen. Dropping dinner at 20:00 sharp would hide it
    /// from every household that eats at half past — so each meal is given an
    /// hour, and the widget errs towards showing a meal you have already eaten
    /// rather than hiding one you are about to.
    ///
    /// One hour lands the three main meals exactly on the intended boundaries:
    ///
    /// | Meal | Nominal | Leaves the widget |
    /// |---|---|---|
    /// | Breakfast | 08:00 | **09:00** |
    /// | Lunch | 13:00 | **14:00** |
    /// | Dinner | 20:00 | **21:00** |
    ///
    /// The two snack slots follow the same rule without being named: the morning
    /// snack goes at 12:00, the evening one at 18:00.
    public static let graceMinutes = 60

    /// 14:00 — the moment lunch leaves, and with it the last reason to be
    /// looking at today rather than ahead.
    ///
    /// A constant rather than a value derived from the user's enabled meal types.
    /// Someone who has turned lunch off still wants their afternoon to begin at
    /// the same hour, and deriving it would make the pivot jump when they edit
    /// their settings.
    public static let eveningPivotMinutes = 14 * 60

    /// When `type` stops being shown, as minutes from midnight.
    public static func showsUntil(_ type: MealType) -> Int? {
        PrepTonight.nominalMealTimes[type].map { $0 + graceMinutes }
    }

    /// Every instant on `date`'s day at which the widget's content changes.
    ///
    /// The pivot plus each meal's cutoff — 09:00, 14:00, 18:00, 21:00 and so on.
    /// These have to reach the timeline as entry dates or the widget simply does
    /// not update: nothing here polls, and a widget that decided at 08:00 what to
    /// show would still be offering breakfast at lunchtime.
    ///
    /// Times are set on the calendar rather than added as elapsed seconds, so a
    /// day on which the clock shifts still lands them on the right wall-clock
    /// hour.
    public static func boundaries(on date: Date, calendar: Calendar = .current) -> [Date] {
        let minutes = Set(MealType.allCases.compactMap(showsUntil) + [eveningPivotMinutes])

        return minutes.compactMap { minute in
            calendar.date(
                bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date
            )
        }
        .sorted()
    }

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

    /// Which phase `date` falls in, given what is still to be cooked today.
    ///
    /// Driven by what remains rather than by the clock alone. A household with
    /// only breakfast enabled is done by 08:00 and should be looking at tomorrow
    /// long before any fixed evening hour; one that eats late is still on today
    /// at 20:00. Asking "is there anything left?" answers both without either
    /// being a special case.
    ///
    /// The pivot only decides when tomorrow becomes worth *previewing* alongside
    /// what is left. Before it, dinner alone is still today's business; after it,
    /// the useful question has become what happens next.
    ///
    /// The pivot instant itself already counts as tonight, so the timeline entry
    /// scheduled *at* the pivot renders the thing it exists to show.
    public static func phase(
        remainingToday: [MealType],
        at date: Date,
        calendar: Calendar = .current
    ) -> Phase {
        guard !remainingToday.isEmpty else { return .tomorrow }
        return date < pivot(on: date, calendar: calendar) ? .today : .tonight
    }

    /// The meal types still worth showing on `date`'s day, in chronological order.
    ///
    /// A meal survives `graceMinutes` past its nominal time, so at 14:00 this is
    /// dinner, and breakfast has not been taking up a row since 09:00.
    ///
    /// Order comes from the nominal times rather than from the caller's array, so
    /// it is stable however the enabled types were assembled — the same reasoning
    /// `PrepAfternoon` applies to its own iteration.
    public static func upcoming(
        _ types: [MealType],
        at date: Date,
        calendar: Calendar = .current
    ) -> [MealType] {
        let startOfDay = calendar.startOfDay(for: date)
        let elapsed = calendar.dateComponents([.minute], from: startOfDay, to: date).minute ?? 0

        return types
            .compactMap { type -> (MealType, Int)? in
                guard let nominal = PrepTonight.nominalMealTimes[type],
                      let until = showsUntil(type),
                      until > elapsed
                else { return nil }
                return (type, nominal)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
