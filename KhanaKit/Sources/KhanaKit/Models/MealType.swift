import Foundation

/// The five courses the planner knows about.
///
/// `key` is the wire format — camelCase, matching the server's `ALL_MEAL_TYPES`
/// (`lib/utils.ts:67`). There is no generic "snacks" key; legacy `snack`/`snack1`/
/// `snack2` exist only in old documents and are never written.
///
/// Declaration order is chronological and load-bearing: the server re-sorts
/// enabled meal types into this order on save, and prep/suggestion output is
/// ordered by it so results are stable however the caller assembled its list.
public enum MealType: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast
    case morningSnack
    case lunch
    case eveningSnack
    case dinner

    public var id: String { rawValue }

    /// The wire key. Identical to `rawValue`; named for parity with Android's `MealType.key`.
    public var key: String { rawValue }

    public var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .morningSnack: "Morning Snack"
        case .lunch: "Lunch"
        case .eveningSnack: "Evening Snack"
        case .dinner: "Dinner"
        }
    }

    public var emoji: String {
        switch self {
        case .breakfast: "🥐"
        case .morningSnack: "🍵"
        case .lunch: "🌮"
        case .eveningSnack: "🍪"
        case .dinner: "🍽"
        }
    }

    public static func fromKey(_ key: String) -> MealType? { MealType(rawValue: key) }

    /// The server's `DEFAULT_MEAL_SETTINGS.enabledMealTypes` (`lib/utils.ts:79`).
    public static let defaultEnabled: [MealType] = [.breakfast, .lunch, .dinner]

    /// Re-orders an arbitrary selection into chronological order, matching the
    /// server's `sortMealTypes` (`lib/utils.ts:123`).
    public static func sorted(_ types: [MealType]) -> [MealType] {
        allCases.filter { types.contains($0) }
    }
}

/// Monday-first, always. The week key sent to the API is the Monday of the week,
/// and every day map on the wire is keyed by these lowercase English names.
public enum DayOfWeek: String, CaseIterable, Codable, Sendable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: String { rawValue }
    public var key: String { rawValue }

    public var displayName: String { rawValue.capitalized }

    public static func fromKey(_ key: String) -> DayOfWeek? { DayOfWeek(rawValue: key) }

    /// 0 for Monday … 6 for Sunday.
    public var index: Int { Self.allCases.firstIndex(of: self)! }
}
