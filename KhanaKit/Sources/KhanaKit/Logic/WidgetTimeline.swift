import Foundation

/// When the widget's timeline should have entries.
///
/// WidgetKit allows roughly 40–70 timeline *reloads* a day, but a timeline may
/// carry many entries, each with its own date. Anything that changes on a clock
/// therefore belongs here rather than in a reload — which is how this ends up
/// strictly better than Android's fixed 6-hour `WorkManager` tick.
public enum WidgetTimeline {

    /// Entries for the rest of today: now, the evening pivot if it is still ahead,
    /// anything else the caller knows changes later today, and the next local
    /// midnight so the day rolls over on its own.
    ///
    /// The pivot is added here rather than left to the caller. A provider that
    /// forgot to pass it would leave the widget showing today's plan all evening,
    /// and nothing would fail loudly — the timeline would simply be wrong.
    ///
    /// - Parameters:
    ///   - extraBoundaries: moments later today that change what is rendered. Each
    ///     prep start time still ahead arrives this way, so the urgency banner
    ///     flips on time without spending refresh budget. Values outside
    ///     `(now, midnight)` are dropped: tomorrow's boundaries belong to the
    ///     timeline built after the rollover.
    ///   - limit: hard cap on entries, so a week with unusually heavy prep cannot
    ///     generate an unbounded timeline. `now`, the pivot and midnight are never
    ///     dropped; the furthest-out prep boundaries go first, because those are
    ///     already legible on their own meal's row whereas the other three are not
    ///     recoverable from anywhere else.
    public static func entryDates(
        startingAt now: Date,
        extraBoundaries: [Date] = [],
        calendar: Calendar = .current,
        limit: Int = 12
    ) -> [Date] {
        let midnight = nextMidnight(after: now, calendar: calendar)
        let pivot = WidgetPhase.pivot(on: now, calendar: calendar)
        let pivotIsAhead = pivot > now && pivot < midnight

        // Reserve room for the entries that cannot be reconstructed from anything
        // else on screen, then keep the earliest boundaries that still fit.
        let reserved = 2 + (pivotIsAhead ? 1 : 0)
        let boundaries = Set(extraBoundaries.filter { $0 > now && $0 < midnight })
            .subtracting(pivotIsAhead ? [pivot] : [])
            .sorted()
            .prefix(max(0, limit - reserved))

        var dates = [now] + boundaries
        if pivotIsAhead { dates.append(pivot) }
        // A caller may pass a prep boundary that lands exactly on the pivot, and
        // WidgetKit rejects duplicate entry dates.
        return Array(Set(dates)).sorted() + [midnight]
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
