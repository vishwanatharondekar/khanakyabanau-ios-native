import Foundation

/// Which weeks the planner offers, and what to call them.
///
/// Nobody pages backwards through a meal planner and nobody plans three weeks
/// out, so the old ◀ ▶ pager offered infinite navigation in both directions to
/// serve neither case. What replaces it is derived from data:
///
///   chips = {this week, next week} ∪ {future weeks that have a saved plan}
///
/// The union is not decoration. A nutritionist handing a client a four-week
/// plan is the core flow of the brand this app is being prepared for; with two
/// hardcoded chips, weeks three and four would exist on the server and be
/// unreachable in the UI.
///
/// Mirrors the webapp's `lib/week-chips.ts`.
public enum WeekChipKind: Hashable, Sendable {
    case thisWeek
    case nextWeek
    case dated
}

public struct WeekChip: Hashable, Sendable, Identifiable {
    /// ISO `yyyy-MM-dd` of the week's Monday.
    public let weekStartDate: String
    public let label: String
    public let kind: WeekChipKind

    public var id: String { weekStartDate }

    public init(weekStartDate: String, label: String, kind: WeekChipKind) {
        self.weekStartDate = weekStartDate
        self.label = label
        self.kind = kind
    }
}

public func buildWeekChips(
    today: PlanDate = WeekDates.today(),
    weeksWithPlans: [String] = []
) -> [WeekChip] {
    let monday = WeekDates.mondayOf(today)
    let thisWeek = WeekDates.format(monday)
    let nextWeek = WeekDates.format(monday.adding(days: 7))

    var seen = Set<String>()
    let dated = weeksWithPlans
        // A malformed value from the API must not take the whole strip down.
        .filter { PlanDate(iso: $0) != nil }
        // Forward only, and never a duplicate of the two fixed chips.
        .filter { $0 > nextWeek }
        .filter { seen.insert($0).inserted }
        .sorted()

    return [
        WeekChip(weekStartDate: thisWeek, label: "This week", kind: .thisWeek),
        WeekChip(weekStartDate: nextWeek, label: "Next week", kind: .nextWeek),
    ] + dated.compactMap { week in
        guard let date = PlanDate(iso: week) else { return nil }
        // Mixed labelling is deliberate: "This week"/"Next week" is how people
        // refer to the two weeks they care about, and a date is how they refer
        // to anything further out.
        return WeekChip(
            weekStartDate: week,
            label: "\(date.day) \(date.shortMonthName)",
            kind: .dated
        )
    }
}

/// Whether a week has no chip — someone arriving from a months-old reminder.
/// That week still renders; it just also needs a way back.
public func isOffRails(_ weekStartDate: String, in chips: [WeekChip]) -> Bool {
    !chips.contains { $0.weekStartDate == weekStartDate }
}
