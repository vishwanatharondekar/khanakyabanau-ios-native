import Foundation

/// A quantity with its unit, as summed and displayed by the shopping list.
public struct IngredientAmount: Hashable, Sendable {
    public var amount: Double
    public var unit: String

    public init(amount: Double, unit: String) {
        self.amount = amount
        self.unit = unit
    }
}

/// One category's worth of the scoped list. An array of these rather than a
/// dictionary because presentation order is part of the contract.
public struct CategorySection: Hashable, Sendable, Identifiable {
    public var name: String
    public var items: [Ingredient]

    public var id: String { name }

    public init(name: String, items: [Ingredient]) {
        self.name = name
        self.items = items
    }
}

/// The shopping list recomposed for a day scope — see `ShoppingScope.aggregateScopedList`.
public struct ScopedShoppingList: Hashable, Sendable {
    /// Ordered: `ShoppingScope.categoryOrder` first, unknown categories after.
    public var categorized: [CategorySection]
    public var ingredients: [String]
    public var weights: [String: IngredientAmount]

    public init(
        categorized: [CategorySection] = [],
        ingredients: [String] = [],
        weights: [String: IngredientAmount] = [:]
    ) {
        self.categorized = categorized
        self.ingredients = ingredients
        self.weights = weights
    }

    public var isEmpty: Bool { categorized.allSatisfy(\.items.isEmpty) }
}

/// Pure scope/prune/export logic for the shopping list. Port of the web app's
/// `lib/shopping-list-scope.ts` and Android's `ShoppingScope.kt` — behavior must
/// stay in lockstep with both.
///
/// The AI generates one full-week list (categorized + per-day breakdown) which is
/// cached server-side. Everything scoped — "next 3 days", pruning items the user
/// already has, share/copy text — is recomposed here on the client from that
/// cached data, so narrowing the scope never costs another AI call.
public enum ShoppingScope {

    /// Presentation order for categories; unknown categories go after these.
    public static let categoryOrder = [
        "Vegetables",
        "Fruits",
        "Dairy & Eggs",
        "Meat & Seafood",
        "Grains & Pulses",
        "Spices & Herbs",
        "Pantry Items",
        "Other",
    ]

    /// Canonical key for an ingredient. `categorized` and `dayWise` drift in casing
    /// for the same ingredient, and `haveAlready` / `newItems` marks must survive
    /// that, so every lookup goes through this.
    public static func normalizeIngredientName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func titleCaseIngredient(_ name: String) -> String {
        name.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    /// Default day scope: people shop for the next couple of days, not the week.
    /// Week containing today → today + next 2 days (clamped to Sunday); a future
    /// week → its first 3 days; a past week → all of it.
    public static func computeDefaultScopeDays(
        weekStartDate: String,
        today: PlanDate = WeekDates.today()
    ) -> [DayOfWeek] {
        guard let weekStart = PlanDate(iso: weekStartDate) else { return DayOfWeek.allCases }
        let todayIndex = today - weekStart
        if (0...6).contains(todayIndex) {
            return Array(DayOfWeek.allCases[todayIndex..<min(todayIndex + 3, 7)])
        }
        return weekStart > today ? Array(DayOfWeek.allCases.prefix(3)) : DayOfWeek.allCases
    }

    /// Sums ingredient amounts across entries. Grams and kilograms are combined in
    /// grams and displayed as kg from 1000 g; the first non-weight unit (ml,
    /// pieces, …) switches to plain summing under that unit.
    public static func sumAmounts(_ entries: [IngredientAmount]) -> IngredientAmount? {
        var total = 0.0
        var hasAnyData = false
        var detectedUnit = "g"
        var isWeightUnit = true

        for entry in entries {
            hasAnyData = true
            switch entry.unit.lowercased() {
            case "g", "gram", "grams":
                total += entry.amount
                detectedUnit = "g"
            case "kg", "kilogram", "kilograms":
                total += entry.amount * 1000
                detectedUnit = "kg"
            case let unit:
                if isWeightUnit {
                    isWeightUnit = false
                    total = entry.amount
                } else {
                    total += entry.amount
                }
                detectedUnit = unit
            }
        }

        guard hasAnyData else { return nil }

        if isWeightUnit, detectedUnit == "g" || detectedUnit == "kg" {
            return total >= 1000
                ? IngredientAmount(amount: roundTo2(total / 1000), unit: "kg")
                : IngredientAmount(amount: total, unit: "g")
        }
        return IngredientAmount(amount: total, unit: detectedUnit)
    }

    /// `"600 g"` / `"1.2 kg"` — the same g→kg display rollover the list rows use.
    public static func formatAmount(_ weight: IngredientAmount?) -> String {
        guard let weight else { return "" }
        if weight.unit.lowercased() == "g", weight.amount >= 1000 {
            return "\(displayNumber(roundTo2(weight.amount / 1000))) kg"
        }
        return "\(displayNumber(weight.amount)) \(weight.unit)"
    }

    /// Normalized ingredient name → category, walking categories in presentation
    /// order so an ingredient the AI put in two categories lands in the first.
    public static func buildIngredientCategoryMap(
        _ categorized: [String: [Ingredient]]
    ) -> [String: String] {
        var map: [String: String] = [:]
        for category in orderedCategoryKeys(Array(categorized.keys), include: {
            !(categorized[$0]?.isEmpty ?? true)
        }) {
            for item in categorized[category] ?? [] {
                let key = normalizeIngredientName(item.name)
                guard !key.isEmpty else { continue }
                if map[key] == nil { map[key] = category }
            }
        }
        return map
    }

    /// Recomposes the list for a set of selected days from the per-day breakdown:
    /// quantities re-summed across the scope, categories re-bucketed via the
    /// full-week categorized map.
    ///
    /// Legacy cached docs have no `dayWise` — those fall back to the full-week
    /// `categorized` untouched (callers hide the day chips in that case).
    public static func aggregateScopedList(
        dayWise: [String: [String: MealIngredients]],
        selectedDays: Set<DayOfWeek>,
        categorized: [String: [Ingredient]]
    ) -> ScopedShoppingList {
        if dayWise.isEmpty {
            var sections: [CategorySection] = []
            var ingredients: [String] = []
            var weights: [String: IngredientAmount] = [:]
            for category in orderedCategoryKeys(Array(categorized.keys), include: { _ in true }) {
                guard let items = categorized[category], !items.isEmpty else { continue }
                sections.append(CategorySection(name: category, items: items))
                for item in items {
                    guard !item.name.isEmpty, !ingredients.contains(item.name) else { continue }
                    ingredients.append(item.name)
                    weights[item.name] = IngredientAmount(amount: item.amount, unit: item.unit)
                }
            }
            return ScopedShoppingList(
                categorized: sections, ingredients: ingredients, weights: weights
            )
        }

        let categoryMap = buildIngredientCategoryMap(categorized)

        // normalized name → (first-seen display name, every scoped occurrence),
        // kept in first-seen order.
        var order: [String] = []
        var displayNames: [String: String] = [:]
        var occurrences: [String: [IngredientAmount]] = [:]

        for day in DayOfWeek.allCases where selectedDays.contains(day) {
            for mealData in orderedMealValues(dayWise[day.key]) {
                for ingredient in mealData.ingredients {
                    let key = normalizeIngredientName(ingredient.name)
                    guard !key.isEmpty else { continue }
                    if displayNames[key] == nil {
                        order.append(key)
                        displayNames[key] = ingredient.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    occurrences[key, default: []]
                        .append(IngredientAmount(amount: ingredient.amount, unit: ingredient.unit))
                }
            }
        }

        var bucketOrder: [String] = []
        var buckets: [String: [Ingredient]] = [:]
        var ingredients: [String] = []
        var weights: [String: IngredientAmount] = [:]

        for key in order {
            guard let displayName = displayNames[key],
                  let total = sumAmounts(occurrences[key] ?? []) else { continue }
            let category = categoryMap[key] ?? "Other"
            if buckets[category] == nil { bucketOrder.append(category) }
            buckets[category, default: []]
                .append(Ingredient(name: displayName, amount: total.amount, unit: total.unit))
            ingredients.append(displayName)
            weights[displayName] = total
        }

        var sections: [CategorySection] = []
        for category in orderedCategoryKeys(bucketOrder, include: { _ in true }) {
            guard let items = buckets[category], !items.isEmpty else { continue }
            sections.append(CategorySection(name: category, items: items))
        }
        return ScopedShoppingList(categorized: sections, ingredients: ingredients, weights: weights)
    }

    /// Normalized ingredient name → dish names it's needed for, in day order and
    /// deduplicated. Scoped to `selectedDays` when given, the whole week when not.
    /// Powers the "for Poha · Dal Tadka" context lines in the sheet and the PDF.
    public static func buildIngredientMealMap(
        dayWise: [String: [String: MealIngredients]],
        selectedDays: Set<DayOfWeek>? = nil
    ) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for day in DayOfWeek.allCases {
            if let selectedDays, !selectedDays.contains(day) { continue }
            for mealData in orderedMealValues(dayWise[day.key]) {
                guard !mealData.name.isEmpty else { continue }
                for ingredient in mealData.ingredients {
                    let key = normalizeIngredientName(ingredient.name)
                    guard !key.isEmpty else { continue }
                    if !(map[key]?.contains(mealData.name) ?? false) {
                        map[key, default: []].append(mealData.name)
                    }
                }
            }
        }
        return map
    }

    /// `"Aug 4 – Aug 6"` for a contiguous scope, `"Aug 4, Aug 6"` otherwise.
    public static func formatScopeLabel(
        weekStartDate: String,
        selectedDays: Set<DayOfWeek>
    ) -> String {
        guard let weekStart = PlanDate(iso: weekStartDate) else { return "" }
        let indexes = DayOfWeek.allCases.enumerated()
            .filter { selectedDays.contains($0.element) }
            .map(\.offset)
        guard let first = indexes.first, let last = indexes.last else { return "" }

        func label(_ index: Int) -> String {
            let date = weekStart.adding(days: index)
            return "\(date.shortMonthName) \(date.day)"
        }

        if indexes.count == 1 { return label(first) }
        if last - first == indexes.count - 1 { return "\(label(first)) – \(label(last))" }
        return indexes.map(label).joined(separator: ", ")
    }

    /// Grouped, human-readable list for the system share sheet (WhatsApp etc.).
    /// Pruned items and emptied categories are omitted.
    public static func buildShareText(
        scoped: ScopedShoppingList,
        haveAlready: Set<String>,
        scopeLabel: String
    ) -> String {
        var lines = ["Shopping list" + (scopeLabel.isEmpty ? "" : " · \(scopeLabel)")]
        for section in scoped.categorized {
            let needed = section.items.filter {
                !haveAlready.contains(normalizeIngredientName($0.name))
            }
            guard !needed.isEmpty else { continue }
            lines.append("")
            lines.append(section.name)
            for item in needed {
                let amount = formatAmount(IngredientAmount(amount: item.amount, unit: item.unit))
                lines.append(
                    "- \(titleCaseIngredient(item.name))" + (amount.isEmpty ? "" : " — \(amount)")
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Flat one-item-per-line text: pasting it into Apple Reminders (or Google
    /// Keep) creates one entry per line, so no headers or bullets.
    public static func buildCopyText(
        scoped: ScopedShoppingList,
        haveAlready: Set<String>
    ) -> String {
        var lines: [String] = []
        for section in scoped.categorized {
            for item in section.items {
                guard !haveAlready.contains(normalizeIngredientName(item.name)) else { continue }
                let amount = formatAmount(IngredientAmount(amount: item.amount, unit: item.unit))
                lines.append(titleCaseIngredient(item.name) + (amount.isEmpty ? "" : " \(amount)"))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    /// `categoryOrder` entries passing `include`, then unknown keys.
    ///
    /// Note the asymmetry, which matches the other clients: `include` gates only
    /// the known categories, never the unknown tail. Unknown keys are sorted
    /// alphabetically because Swift dictionaries have no insertion order to
    /// preserve — the server only ever emits the eight known categories, so this
    /// branch exists for robustness rather than for a shape we actually see.
    private static func orderedCategoryKeys(
        _ keys: [String],
        include: (String) -> Bool
    ) -> [String] {
        let known = categoryOrder.filter { keys.contains($0) && include($0) }
        let unknown = keys.filter { !categoryOrder.contains($0) }
        return known + (unknown.count > 1 ? unknown.sorted() : unknown)
    }

    /// Meal entries for one day in a stable order: canonical course order first,
    /// then anything unrecognised, alphabetically.
    private static func orderedMealValues(
        _ meals: [String: MealIngredients]?
    ) -> [MealIngredients] {
        guard let meals else { return [] }
        let known = MealType.allCases.compactMap { meals[$0.key] }
        let unknownKeys = meals.keys
            .filter { MealType.fromKey($0) == nil }
            .sorted()
        return known + unknownKeys.compactMap { meals[$0] }
    }

    /// Java's `Math.round(x * 100) / 100.0` — half-up, matching the web app's kg
    /// rounding. Amounts are non-negative, where half-up and half-away agree.
    private static func roundTo2(_ value: Double) -> Double {
        (value * 100 + 0.5).rounded(.down) / 100
    }

    /// Renders like JavaScript number-to-string: no `.0` on whole values, else
    /// trimmed decimals. Amounts are pre-rounded to 2 dp wherever fractions arise.
    private static func displayNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
