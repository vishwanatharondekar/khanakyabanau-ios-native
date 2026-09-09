import Foundation

/// Which days of a week have already gone.
///
/// Generating from today leaves the earlier days of the current week empty —
/// onboard on a Thursday and Monday to Wednesday have no meals. They are not
/// missing data, they are days that have passed, and the planner was showing
/// them as empty slots offering "Add a meal": an action that cannot mean
/// anything, since you cannot cook Monday's dinner on Thursday.
///
/// Same idea as a past week being read-only, one level down.
///
/// Mirrors the webapp's `lib/past-days.ts`.

/// The days of `weekStartDate` that are already over, in week order.
///
/// Empty for a future week; every day for a week that has wholly passed; and
/// for the current week, the days before today. Today itself is never past —
/// there is still dinner to cook.
public func pastDaysInWeek(
    _ weekStartDate: String,
    today: PlanDate = WeekDates.today()
) -> [DayOfWeek] {
    let thisWeek = WeekDates.format(WeekDates.mondayOf(today))

    if weekStartDate > thisWeek { return [] }
    if weekStartDate < thisWeek { return DayOfWeek.allCases }

    // `dayOfWeek.index` is Monday-based, which is what DayOfWeek.allCases is
    // ordered by — deriving this from Calendar.weekday instead would be
    // Sunday-based and off by one.
    return Array(DayOfWeek.allCases.prefix(today.dayOfWeek.index))
}

/// Whether a specific day of a specific week has gone.
public func isPastDay(
    _ weekStartDate: String,
    day: DayOfWeek,
    today: PlanDate = WeekDates.today()
) -> Bool {
    pastDaysInWeek(weekStartDate, today: today).contains(day)
}
