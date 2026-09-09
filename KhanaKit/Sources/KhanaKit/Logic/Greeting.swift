import Foundation

/// The top of Today.
///
/// With the brand header gone, Today opens straight onto meal cards with
/// nothing addressing the person looking at them — which reads as a page with
/// its chrome chopped off rather than as an app. A greeting is the cheapest
/// fix: it is content, not chrome, so it costs nothing in the vertical budget
/// the header was eating.
///
/// Takes an hour rather than a `Date` — the view already reads the clock, and
/// the hour is the whole of what the rule depends on.
///
/// Mirrors the webapp's `components/today/Greeting.tsx`.
public func greeting(forHour hour: Int) -> String {
    switch hour {
    case ..<12: "Good morning"
    case ..<17: "Good afternoon"
    default: "Good evening"
    }
}

/// First word only — "Good evening, Vishwanath Arondekar" is a form letter.
public func firstName(_ name: String?) -> String? {
    guard let first = name?
        .split(whereSeparator: \.isWhitespace)
        .first
        .map(String.init),
        !first.isEmpty
    else { return nil }
    return first
}
