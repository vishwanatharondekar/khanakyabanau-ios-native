import Foundation

public struct Ingredient: Codable, Hashable, Sendable {
    public var name: String
    public var amount: Double
    public var unit: String

    public init(name: String, amount: Double = 0, unit: String = "") {
        self.name = name
        self.amount = amount
        self.unit = unit
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
    }
}

/// One meal's contribution to the day-wise breakdown.
public struct MealIngredients: Codable, Hashable, Sendable {
    public var name: String
    public var ingredients: [Ingredient]

    public init(name: String = "", ingredients: [Ingredient] = []) {
        self.name = name
        self.ingredients = ingredients
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        ingredients = (try? c.decode([Ingredient].self, forKey: .ingredients)) ?? []
    }
}

/// The AI-generated full-week list, cached server-side against a hash of the plan.
/// Everything scoped — day selection, pruning, share/copy text — is recomposed on
/// the client from this by `ShoppingScope`, so narrowing scope costs no AI call.
public struct ShoppingList: Codable, Hashable, Sendable {
    /// Category name → items. Presentation order comes from `ShoppingScope.categoryOrder`,
    /// not from this dictionary.
    public var categorized: [String: [Ingredient]]
    /// day key → meal type key → that meal's ingredients. Absent on legacy cached docs.
    public var dayWise: [String: [String: MealIngredients]]
    /// Normalized (trimmed + lowercased) names the user has ticked off.
    public var haveAlready: [String]
    public var newItems: [String]
    /// True when the server served this from cache without an AI call.
    public var cached: Bool

    public init(
        categorized: [String: [Ingredient]] = [:],
        dayWise: [String: [String: MealIngredients]] = [:],
        haveAlready: [String] = [],
        newItems: [String] = [],
        cached: Bool = false
    ) {
        self.categorized = categorized
        self.dayWise = dayWise
        self.haveAlready = haveAlready
        self.newItems = newItems
        self.cached = cached
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categorized = (try? c.decode([String: [Ingredient]].self, forKey: .categorized)) ?? [:]
        dayWise = (try? c.decode([String: [String: MealIngredients]].self, forKey: .dayWise)) ?? [:]
        haveAlready = (try? c.decode([String].self, forKey: .haveAlready)) ?? []
        newItems = (try? c.decode([String].self, forKey: .newItems)) ?? []
        cached = (try? c.decode(Bool.self, forKey: .cached)) ?? false
    }

    public var isEmpty: Bool { categorized.values.allSatisfy(\.isEmpty) }
}
