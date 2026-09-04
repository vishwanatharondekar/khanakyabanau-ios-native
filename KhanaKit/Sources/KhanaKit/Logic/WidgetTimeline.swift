import Foundation

/// When the widget's timeline should have entries.
///
/// WidgetKit allows roughly 40–70 timeline *reloads* a day, but a timeline may
/// carry many entries, each with its own date. Anything that changes on a clock
/// therefore belongs here rather than in a reload — which is how this ends up
/// strictly better than Android's fixed 6-hour `WorkManager` tick.
public enum WidgetTimeline {

    /// Entries for the rest of today: now, anything the caller knows changes later
    /// today, and the next local midnight so the day rolls over on its own.
    ///
    /// - Parameters:
    ///   - extraBoundaries: moments later today that change what is rendered. The
    ///     evening pivot and each prep start time still ahead both arrive this
    ///     way, so the widget flips on time without spending refresh budget.
    ///     Values outside `(now, midnight)` are dropped: tomorrow's boundaries
    ///     belong to the timeline built after the rollover.
    ///   - limit: hard cap on entries. The head and the midnight entry are always
    ///     kept — without midnight the widget freezes on yesterday's menu.
    public static func entryDates(
        startingAt now: Date,
        extraBoundaries: [Date] = [],
        calendar: Calendar = .current,
        limit: Int = 40
    ) -> [Date] {
        let midnight = nextMidnight(after: now, calendar: calendar)
        let boundaries = Set(extraBoundaries.filter { $0 > now && $0 < midnight })
            .sorted()

        // Keep the head and the rollover; drop from the tail when capped. The
        // dropped ones are the furthest out, which are also the least urgent —
        // a prep step hours away is already legible on its own meal row.
        let room = max(0, limit - 2)
        return [now] + boundaries.prefix(room) + [midnight]
    }

    /// The next local midnight strictly after `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        // `startOfDay` of a date that *is* midnight returns that same instant, which
        // would schedule an entry for now and leave the widget with nothing after.
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? date.addingTimeInterval(24 * 3600)
    }
}
