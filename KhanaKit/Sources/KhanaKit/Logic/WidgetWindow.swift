import Foundation

/// Which weeks the widget can be showing right now.
///
/// The snapshot carries `WidgetSnapshot.windowDays` starting today, so only a
/// week holding one of those days is worth rebuilding a snapshot for. Every other
/// week the app loads — history, whatever the user is browsing three weeks out —
/// must not spend a widget reload on data nobody can see.
///
/// An eight-day window always spans exactly this week and next.
public enum WidgetWindow {

    public static func covers(weekStartDate: String, today: PlanDate) -> Bool {
        guard let weekStart = PlanDate(iso: weekStartDate) else { return false }
        return weeks(from: today).contains(weekStart)
    }

    /// The Mondays of every week the window touches, earliest first.
    public static func weeks(from today: PlanDate) -> [PlanDate] {
        var mondays: [PlanDate] = []
        for offset in 0..<WidgetSnapshot.windowDays {
            let monday = WeekDates.mondayOf(today.adding(days: offset))
            if mondays.last != monday { mondays.append(monday) }
        }
        return mondays
    }
}
