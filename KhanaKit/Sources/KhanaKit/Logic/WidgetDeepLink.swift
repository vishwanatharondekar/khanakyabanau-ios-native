import Foundation

/// The widget's tap targets.
///
/// Built by the extension and parsed by the app — two binaries — so both sides
/// live here rather than one each. A drift between them is a tap that opens the
/// wrong screen, which is exactly the kind of bug nobody notices until a user
/// reports it.
public enum WidgetDeepLink {

    public static let scheme = "khanakyabanau"

    public enum Destination: Hashable, Sendable {
        case today
        case tomorrow
        case meal(day: DayOfWeek, type: MealType)
    }

    /// A whole-widget link. `target` is `"today"` or `"tomorrow"`.
    public static func url(target: String) -> URL {
        URL(string: "\(scheme)://\(target)") ?? URL(string: "\(scheme)://today")!
    }

    /// A single meal's link.
    ///
    /// Non-optional so the caller needs no fallback at the tap site: `Link`
    /// requires a destination, and there is no sensible UI for "this row is not
    /// tappable".
    public static func url(day: DayOfWeek, mealType: MealType) -> URL {
        URL(string: "\(scheme)://meal/\(day.key)/\(mealType.key)") ?? url(target: "today")
    }

    public static func parse(_ url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }

        // The host carries the first path component for custom schemes, so
        // "khanakyabanau://meal/friday/dinner" is host "meal" + two path parts.
        let parts = [url.host].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }

        switch parts.first {
        case "today": return .today
        case "tomorrow": return .tomorrow
        case "meal":
            guard parts.count >= 3,
                  let day = DayOfWeek.fromKey(parts[1]),
                  let type = MealType.fromKey(parts[2])
            else { return nil }
            return .meal(day: day, type: type)
        default: return nil
        }
    }
}
