import Foundation

/// Looking at weeks that have already happened.
///
/// The planner is forward-only by design — a pager that walks backwards forever
/// was the thing the week strip replaced. But "what did we eat in July?" is a
/// real question and the plans are already stored, so the answer is to let
/// someone step back deliberately rather than build a second feature that
/// re-derives it.
///
/// A past week is read-only, which is not a restriction so much as the truth:
/// you cannot change what you already ate. That reuses the same `canEditPlan`
/// path the coming nutrition brand needs, and is what finally exercises it with
/// real users.
///
/// Mirrors the webapp's `lib/week-history.ts`.

/// How far back a single step can look for a week that has a plan.
public let earlierHorizon = 12

public func isPastWeek(_ weekStartDate: String, today: PlanDate = WeekDates.today()) -> Bool {
    weekStartDate < WeekDates.format(WeekDates.mondayOf(today))
}

/// The `count` week-starts immediately before `weekStartDate`, nearest first.
public func earlierWeekStarts(_ weekStartDate: String, count: Int = earlierHorizon) -> [String] {
    guard let start = PlanDate(iso: weekStartDate) else { return [] }
    let monday = WeekDates.mondayOf(start)
    return (1...max(count, 1)).prefix(count).map { WeekDates.format(monday.adding(days: -$0 * 7)) }
}

/// The nearest earlier week that actually holds a plan, or nil.
///
/// Skipping over empty weeks is the point: stepping back one at a time would
/// strand someone on a blank week that happens to sit between two they cooked,
/// and an arrow that lands on nothing is worse than no arrow.
public func nearestEarlierWeekWithPlan(
    _ weekStartDate: String,
    in weeksWithPlans: [String]
) -> String? {
    weeksWithPlans.filter { $0 < weekStartDate }.max()
}
