import Foundation

/// Which weeks the widget can be showing right now.
///
/// The widget renders today and tomorrow, so only the week containing one of
/// those two days is worth rebuilding a snapshot for. Every other week the app
/// loads — history, whatever the user is browsing three weeks out — must not
/// spend a widget reload on data nobody can see.
///
/// Six days a week that is one week. On a Sunday it is two, because tomorrow is
/// Monday and Monday starts a new plan document.
public enum WidgetWindow {

    public static func covers(weekStartDate: String, today: PlanDate) -> Bool {
        guard let weekStart = PlanDate(iso: weekStartDate) else { return false }

        let tomorrow = today.adding(days: 1)
        return weekStart == WeekDates.mondayOf(today)
            || weekStart == WeekDates.mondayOf(tomorrow)
    }
}
