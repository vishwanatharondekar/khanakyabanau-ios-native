import Foundation

/// Whether filling the week in one go is the obvious thing to offer.
///
/// The hero used to appear only on a wholly empty week, which made it vanish the
/// moment anyone typed a single dish — and "Fill empty days" then lived in the
/// overflow, where nobody staring at six blank days is going to look for it.
///
/// Measured in days rather than slots because that is the unit the action names
/// and the grid shows. A week with dinner on every day is planned; a week with
/// four days holding nothing is not, whatever the slot count says.
///
/// More than half is the line, so it needs no magic number: this asks "is most of
/// what is left unplanned?" and answers yes or no.
///
/// Days already gone are excluded on both sides. They cannot be filled — the
/// generator starts from today — so counting them would keep the hero on screen
/// all week for a Thursday signup whose Monday to Wednesday are blank and always
/// will be.
public func isMostlyUnplanned(
    plannedDays: Set<DayOfWeek>,
    pastDays: Set<DayOfWeek>
) -> Bool {
    let plannable = DayOfWeek.allCases.filter { !pastDays.contains($0) }
    // A week that has wholly happened has nothing to offer filling.
    guard !plannable.isEmpty else { return false }
    let unplanned = plannable.filter { !plannedDays.contains($0) }.count
    return unplanned * 2 > plannable.count
}
