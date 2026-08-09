import Foundation

/// A reproducible random source, so suggestion shuffling can be asserted in tests
/// and so callers can opt into determinism. SplitMix64 — small, fast, good enough
/// for picking dish names.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Mirror of the web app's `lib/meal-suggestions.ts`.
///
/// Produces the list the replace-meal sheet shows the moment it opens — the user's
/// own meals for that slot in recent weeks, topped up with dishes from their cuisine
/// preferences — so the sheet has content without waiting on a network round trip.
/// Asking for fresh ideas goes to the server-side corpus instead.
public enum MealSuggestions {

    /// How much wider than `limit` the history pool is before random sampling.
    /// Bigger means more variety between opens, at the cost of surfacing
    /// lower-ranked items.
    private static let samplePoolFactor = 3

    public static let defaultLimit = 8

    /// The user's own meals for `type`, weighted by recency (index 0 of `history`
    /// is the most recent week) and frequency, then sampled from the top of that
    /// ranking so repeat opens don't show an identical list.
    public static func rankHistoryMeals(
        history: [MealPlan],
        type: MealType,
        limit: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [String] {
        guard !history.isEmpty, limit > 0 else { return [] }

        var order: [String] = []
        var weights: [String: Int] = [:]
        var displayNames: [String: String] = [:]

        for (index, plan) in history.enumerated() {
            let recencyWeight = max(history.count - index, 1)
            for dayMeals in plan.meals.values {
                let name = dayMeals[type].name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                if weights[key] == nil {
                    order.append(key)
                    displayNames[key] = name
                    weights[key] = recencyWeight
                } else {
                    weights[key]! += recencyWeight
                }
            }
        }

        // Stable descending sort: ties keep first-seen order, matching Kotlin's
        // `sortedByDescending` and JavaScript's `Array.prototype.sort`.
        let ranked = order.enumerated()
            .sorted { lhs, rhs in
                let lw = weights[lhs.element] ?? 0
                let rw = weights[rhs.element] ?? 0
                return lw == rw ? lhs.offset < rhs.offset : lw > rw
            }
            .map(\.element)

        return ranked
            .prefix(limit * samplePoolFactor)
            .shuffled(using: &generator)
            .prefix(limit)
            .compactMap { displayNames[$0] }
    }

    /// Cold-start pool for users with little or no history: dishes drawn from their
    /// selected cuisines (plus the universal set) for this slot.
    public static func coldStartMeals(
        cuisines: [String],
        vegetarian: Bool,
        type: MealType,
        limit: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [String] {
        guard limit > 0 else { return [] }
        let pool = CuisineData.dishesFor(cuisines, vegOnly: vegetarian)
        let dishes: [String] = switch type {
        case .breakfast: pool.breakfast
        case .morningSnack, .eveningSnack: pool.snacks
        case .lunch, .dinner: pool.lunchDinner
        }
        return Array(dishes.shuffled(using: &generator).prefix(limit))
    }

    /// Concatenates `lists` in order, dropping blanks and case-insensitive repeats.
    public static func merge(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for list in lists {
            for raw in list {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
                result.append(name)
            }
        }
        return result
    }

    public static func buildInitial(
        cuisines: [String],
        vegetarian: Bool,
        history: [MealPlan],
        type: MealType,
        limit: Int = MealSuggestions.defaultLimit,
        using generator: inout some RandomNumberGenerator
    ) -> [String] {
        let fromHistory = rankHistoryMeals(
            history: history, type: type, limit: limit, using: &generator
        )
        let fromCuisine = coldStartMeals(
            cuisines: cuisines, vegetarian: vegetarian, type: type,
            limit: limit * 2, using: &generator
        )
        // Cap history at ~half the slots. With a small history (say one filled week)
        // letting it fill the whole list means every open shows the same meals, only
        // reordered. Reserving slots for cuisine picks keeps the membership itself
        // changing between opens.
        let historyShare = min(fromHistory.count, Int((Double(limit) / 2).rounded(.up)))
        return Array(
            merge(
                Array(fromHistory.prefix(historyShare)),
                fromCuisine,
                // Backfill, in case the cuisine list runs short.
                fromHistory
            )
            .prefix(limit)
            .shuffled(using: &generator)
        )
    }

    /// Convenience overload using the system random source.
    public static func buildInitial(
        cuisines: [String],
        vegetarian: Bool,
        history: [MealPlan],
        type: MealType,
        limit: Int = MealSuggestions.defaultLimit
    ) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return buildInitial(
            cuisines: cuisines, vegetarian: vegetarian, history: history,
            type: type, limit: limit, using: &generator
        )
    }
}
