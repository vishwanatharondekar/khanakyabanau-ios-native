import Foundation

/// One day's five slots. Every field defaults to `.empty` so a partial day map
/// (the common case — most users only enable breakfast/lunch/dinner) decodes cleanly.
public struct DayMeals: Codable, Hashable, Sendable {
    public var breakfast: Meal
    public var morningSnack: Meal
    public var lunch: Meal
    public var eveningSnack: Meal
    public var dinner: Meal

    public init(
        breakfast: Meal = .empty,
        morningSnack: Meal = .empty,
        lunch: Meal = .empty,
        eveningSnack: Meal = .empty,
        dinner: Meal = .empty
    ) {
        self.breakfast = breakfast
        self.morningSnack = morningSnack
        self.lunch = lunch
        self.eveningSnack = eveningSnack
        self.dinner = dinner
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        breakfast = try c.decodeIfPresent(Meal.self, forKey: .breakfast) ?? .empty
        morningSnack = try c.decodeIfPresent(Meal.self, forKey: .morningSnack) ?? .empty
        lunch = try c.decodeIfPresent(Meal.self, forKey: .lunch) ?? .empty
        eveningSnack = try c.decodeIfPresent(Meal.self, forKey: .eveningSnack) ?? .empty
        dinner = try c.decodeIfPresent(Meal.self, forKey: .dinner) ?? .empty
    }

    public subscript(type: MealType) -> Meal {
        get {
            switch type {
            case .breakfast: breakfast
            case .morningSnack: morningSnack
            case .lunch: lunch
            case .eveningSnack: eveningSnack
            case .dinner: dinner
            }
        }
        set {
            switch type {
            case .breakfast: breakfast = newValue
            case .morningSnack: morningSnack = newValue
            case .lunch: lunch = newValue
            case .eveningSnack: eveningSnack = newValue
            case .dinner: dinner = newValue
            }
        }
    }

    public func setting(_ type: MealType, to meal: Meal) -> DayMeals {
        var copy = self
        copy[type] = meal
        return copy
    }

    public var isEmpty: Bool {
        MealType.allCases.allSatisfy { self[$0].isEmpty }
    }
}

public struct MealPlan: Codable, Hashable, Sendable {
    public var id: String?
    public var userId: String?
    public var weekStartDate: String
    /// Keyed by `DayOfWeek.key` — lowercase English day names.
    public var meals: [String: DayMeals]

    public init(
        id: String? = nil,
        userId: String? = nil,
        weekStartDate: String,
        meals: [String: DayMeals] = [:]
    ) {
        self.id = id
        self.userId = userId
        self.weekStartDate = weekStartDate
        self.meals = meals
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decode(String.self, forKey: .id)
        userId = try? c.decode(String.self, forKey: .userId)
        weekStartDate = (try? c.decode(String.self, forKey: .weekStartDate)) ?? ""
        meals = (try? c.decode([String: DayMeals].self, forKey: .meals)) ?? [:]
    }

    public static func empty(weekStartDate: String) -> MealPlan {
        MealPlan(
            weekStartDate: weekStartDate,
            meals: Dictionary(uniqueKeysWithValues: DayOfWeek.allCases.map { ($0.key, DayMeals()) })
        )
    }

    public func meals(for day: DayOfWeek) -> DayMeals { meals[day.key] ?? DayMeals() }

    public subscript(day: DayOfWeek, type: MealType) -> Meal { meals(for: day)[type] }

    /// Returns this plan with one slot's dish replaced.
    ///
    /// Editing the name forfeits any cached `imageUrl` — the next GET re-resolves
    /// images for the new name. Callers that already hold one (suggestion cards
    /// ship with a resolved thumbnail) pass it through so the card the user tapped
    /// doesn't shimmer back to a placeholder.
    ///
    /// An unchanged name is not an edit, though: opening the edit dialog and
    /// tapping Save must not discard calories or advance prep, which cost an AI
    /// call apiece to produce. A genuine rename still drops prep, matching the
    /// server's staleness rule.
    public func withMeal(
        day: DayOfWeek,
        type: MealType,
        name: String,
        imageUrl: String? = nil
    ) -> MealPlan {
        let existing = meals(for: day)[type]
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let updated: Meal
        if !trimmed.isEmpty, existing.name.trimmingCharacters(in: .whitespaces) == trimmed {
            var kept = existing
            kept.imageUrl = imageUrl ?? existing.imageUrl
            updated = kept
        } else {
            updated = Meal(name: name, imageUrl: imageUrl)
        }
        var copy = self
        copy.meals[day.key] = meals(for: day).setting(type, to: updated)
        return copy
    }

    /// Returns this plan with prep copied from `other` onto slots holding the same
    /// dish, leaving every other field alone.
    ///
    /// Used after asking the server to generate prep: adopting the freshly fetched
    /// plan wholesale would strip the image URLs resolved in this session and make
    /// the whole week shimmer, so only prep crosses over.
    public func withPrepFrom(_ other: MealPlan) -> MealPlan {
        var copy = self
        for (dayKey, day) in meals {
            guard let source = other.meals[dayKey] else { continue }
            var working = day
            for type in MealType.allCases {
                let meal = working[type]
                guard !meal.isEmpty else { continue }
                let incoming = source[type]
                guard incoming.name.trimmingCharacters(in: .whitespaces)
                    == meal.name.trimmingCharacters(in: .whitespaces) else { continue }
                guard let prep = incoming.prep else { continue }
                var merged = meal
                merged.prep = prep
                merged.prepFor = incoming.prepFor
                working[type] = merged
            }
            copy.meals[dayKey] = working
        }
        return copy
    }

    /// Merges `images` (lowercased meal name → URL) onto cells that lack one.
    public func withImages(_ images: [String: String]) -> MealPlan {
        guard !images.isEmpty else { return self }
        var copy = self
        for (dayKey, day) in meals {
            var working = day
            for type in MealType.allCases {
                let meal = working[type]
                guard meal.imageUrl == nil, !meal.isEmpty else { continue }
                let image = images[meal.name.lowercased()] ?? images[meal.name]
                if let image, !image.isEmpty {
                    var updated = meal
                    updated.imageUrl = image
                    working[type] = updated
                }
            }
            copy.meals[dayKey] = working
        }
        return copy
    }

    /// Puts every non-nil `imageUrl` through `transform`, used to absolutize
    /// relative URLs returned by the server.
    public func normalizingImageURLs(_ transform: (String) -> String?) -> MealPlan {
        var copy = self
        for (dayKey, day) in meals {
            var working = day
            for type in MealType.allCases {
                let meal = working[type]
                guard let current = meal.imageUrl, !current.isEmpty,
                      let normalized = transform(current), normalized != current else { continue }
                var updated = meal
                updated.imageUrl = normalized
                working[type] = updated
            }
            copy.meals[dayKey] = working
        }
        return copy
    }

    /// Distinct meal names in this plan that don't have a thumbnail yet.
    public func mealNamesMissingImages() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for day in DayOfWeek.allCases {
            let dayMeals = meals(for: day)
            for type in MealType.allCases {
                let meal = dayMeals[type]
                guard !meal.isEmpty, meal.imageUrl?.isEmpty ?? true else { continue }
                if seen.insert(meal.name).inserted { names.append(meal.name) }
            }
        }
        return names
    }

    /// Incoming AI suggestions land only in slots that are currently empty.
    /// Mirrors `WeekViewModel.mergeFillEmpty` — generation never overwrites a
    /// dish the user chose.
    public func mergingFillingEmpty(with incoming: [String: DayMeals]) -> MealPlan {
        var copy = self
        for day in DayOfWeek.allCases {
            guard let source = incoming[day.key] else { continue }
            var working = meals(for: day)
            for type in MealType.allCases where working[type].isEmpty {
                let candidate = source[type]
                if !candidate.isEmpty { working[type] = candidate }
            }
            copy.meals[day.key] = working
        }
        return copy
    }

    /// Every non-blank dish name in the week, in day-then-course order.
    public func allDishNames() -> [String] {
        DayOfWeek.allCases.flatMap { day in
            MealType.allCases.compactMap { type in
                let meal = meals(for: day)[type]
                return meal.isEmpty ? nil : meal.name
            }
        }
    }
}
