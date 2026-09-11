import Foundation

/// What opening the Shopping tab should do, once the free probe has answered.
public enum ShoppingOpen: Hashable, Sendable {
    case show
    case generate
    case empty
    case past
    case limit
}

/// Opening the tab is the request to build a list — with three exceptions.
///
/// A week with no dishes has nothing to derive a list from. A week that has
/// already happened is never worth generating for: the shop is over, and since
/// this tab builds on open, browsing history would otherwise fire an AI call —
/// and spend a guest's allowance — for every past week someone looked at. And a
/// guest with nothing left to spend gets told, rather than shown an error from
/// a call that cannot succeed.
///
/// Mirrors the webapp's `lib/use-shopping-list.ts`.
public func shoppingOpenOutcome(
    weekStartDate: String,
    cached: Bool,
    hasDishes: Bool,
    isGuestAtLimit: Bool,
    today: PlanDate = WeekDates.today()
) -> ShoppingOpen {
    if cached { return .show }
    if !hasDishes { return .empty }
    if isPastWeek(weekStartDate, today: today) { return .past }
    if isGuestAtLimit { return .limit }
    return .generate
}
