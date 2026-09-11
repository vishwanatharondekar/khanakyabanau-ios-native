import Foundation

/// What Today should be leading with, right now.
///
/// Today used to render every enabled course in a fixed order whatever the hour,
/// so at nine in the evening the screen still opened on breakfast. The widget
/// has known better since it shipped: `WidgetPhase` already decides what is
/// still worth showing, with a grace hour so a meal survives past its nominal
/// time rather than vanishing the minute it is due.
///
/// This is that same clock, applied to the screen — deliberately composed from
/// `WidgetPhase` rather than re-deriving it, because a widget and an app that
/// disagreed about when dinner stops mattering would be worse than either rule
/// on its own.
///
/// Where it parts company with the widget is what to do with the meals that have
/// gone. A widget hides them because it has no room and no taps; the screen has
/// both, and "what did I plan for breakfast?" is a fair question at ten in the
/// morning. So they are demoted rather than dropped — the same answer the week
/// grid gives for days already gone.
public struct TodayAgenda: Equatable, Sendable {
    /// Meals whose hour has passed, in day order. Collapsed, not removed.
    public let earlier: [MealType]
    /// Meals still to come, in day order.
    public let upcoming: [MealType]
    /// The one to lead with, or nil once the day is cooked.
    public let upNext: MealType?
    public let phase: WidgetPhase.Phase

    /// Nothing left to cook today — Today should be looking at tomorrow.
    public var isDayDone: Bool { upcoming.isEmpty }
}

public func todayAgenda(
    enabledTypes: [MealType],
    at date: Date = Date(),
    calendar: Calendar = .current
) -> TodayAgenda {
    let upcoming = WidgetPhase.upcoming(enabledTypes, at: date, calendar: calendar)
    let stillToCome = Set(upcoming)
    // Taken from the enum rather than from `enabledTypes`, so the order is the
    // day's order however the caller assembled its list — the same reasoning
    // WidgetPhase.upcoming applies to its own sort.
    let earlier = MealType.allCases.filter {
        enabledTypes.contains($0) && !stillToCome.contains($0)
    }

    return TodayAgenda(
        earlier: earlier,
        upcoming: upcoming,
        upNext: upcoming.first,
        phase: WidgetPhase.phase(remainingToday: upcoming, at: date, calendar: calendar)
    )
}
