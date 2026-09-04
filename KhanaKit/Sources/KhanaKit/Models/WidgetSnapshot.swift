import Foundation

/// What the home screen widget renders, as written by the app and read by the
/// extension.
///
/// This is a contract across a process boundary. The extension cannot ask the app
/// a question, cannot show a spinner worth looking at, and is killed if it dawdles
/// — so everything it needs is resolved here, at write time, in the app, where
/// there is a network and a user waiting anyway.
///
/// It carries **today and tomorrow**, always in that order, because the single
/// time-aware widget needs both: before the evening pivot it renders today, after
/// it renders tonight's remaining meals and then tomorrow. Resolving the two days
/// at write time is also what keeps the extension free of week-rollover
/// arithmetic — on a Sunday, tomorrow lives in a different plan document.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public var isAuthenticated: Bool
    public var writtenAt: Date
    /// Today first, tomorrow second.
    public var days: [WidgetDay]

    public init(isAuthenticated: Bool, writtenAt: Date, days: [WidgetDay]) {
        self.isAuthenticated = isAuthenticated
        self.writtenAt = writtenAt
        self.days = days
    }
}

public struct WidgetDay: Codable, Hashable, Sendable {
    public var day: DayOfWeek
    /// ISO `yyyy-MM-dd`, so the extension can tell a stale snapshot from a fresh
    /// one without recomputing a calendar.
    public var date: String
    /// Enabled types only, in canonical order, empty slots removed.
    public var meals: [WidgetMeal]

    public init(day: DayOfWeek, date: String, meals: [WidgetMeal]) {
        self.day = day
        self.date = date
        self.meals = meals
    }

    public var hasAnyMeal: Bool { !meals.isEmpty }
}

public struct WidgetMeal: Codable, Hashable, Sendable {
    public var type: MealType
    public var name: String
    public var calories: Int?
    /// A file name inside the shared container, never a URL.
    ///
    /// The extension must never be the thing that discovers it has to download an
    /// image: that is a network call on a render path with a hard time budget.
    public var thumbnailKey: String?
    /// `Meal.validPrep` only — prep left over from a dish that has since been
    /// renamed is dropped at write time, so the widget cannot tell the user to
    /// soak something for a meal they are no longer cooking.
    public var prep: MealPrep?

    public init(
        type: MealType,
        name: String,
        calories: Int?,
        thumbnailKey: String?,
        prep: MealPrep?
    ) {
        self.type = type
        self.name = name
        self.calories = calories
        self.thumbnailKey = thumbnailKey
        self.prep = prep
    }
}

public extension WidgetSnapshot {

    /// Build a snapshot for today and tomorrow.
    ///
    /// Two plans rather than one because they are not always the same document:
    /// on a Sunday, tomorrow is Monday of next week. The caller decides which
    /// plans those are; this only decides what to keep from them. Passing the
    /// same plan twice is correct for the other six days.
    ///
    /// - Parameter thumbnailKey: maps a meal's remote image URL to a file already
    ///   in the shared container. Returning `nil` is normal and simply means the
    ///   row renders without a thumbnail.
    static func build(
        today todayPlan: MealPlan,
        tomorrow tomorrowPlan: MealPlan,
        on now: Date,
        enabledTypes: [MealType],
        isAuthenticated: Bool,
        calendar: Calendar = .current,
        thumbnailKey: (Meal) -> String? = { _ in nil }
    ) -> WidgetSnapshot {
        let todayDate = PlanDate.today(timeZone: calendar.timeZone, now: now)
        let tomorrowDate = todayDate.adding(days: 1)

        return WidgetSnapshot(
            isAuthenticated: isAuthenticated,
            writtenAt: now,
            days: [
                day(from: todayPlan, on: todayDate, enabledTypes: enabledTypes, thumbnailKey: thumbnailKey),
                day(from: tomorrowPlan, on: tomorrowDate, enabledTypes: enabledTypes, thumbnailKey: thumbnailKey),
            ]
        )
    }

    private static func day(
        from plan: MealPlan,
        on date: PlanDate,
        enabledTypes: [MealType],
        thumbnailKey: (Meal) -> String?
    ) -> WidgetDay {
        let weekday = dayOfWeek(for: date)
        let meals = plan.meals[weekday.key] ?? DayMeals()

        // Iterate the canonical order rather than the caller's array, so the rows
        // are stable however `enabledTypes` was assembled — the same reasoning
        // `PrepAfternoon` applies to its own iteration.
        let rows = MealType.allCases.compactMap { type -> WidgetMeal? in
            guard enabledTypes.contains(type) else { return nil }
            let meal = meals[type]
            guard !meal.isEmpty else { return nil }

            return WidgetMeal(
                type: type,
                name: meal.name,
                calories: meal.calories,
                thumbnailKey: thumbnailKey(meal),
                prep: meal.validPrep
            )
        }

        return WidgetDay(day: weekday, date: date.isoString, meals: rows)
    }

    /// Monday-indexed, matching `DayOfWeek.index` and the plan's own keys.
    private static func dayOfWeek(for date: PlanDate) -> DayOfWeek {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let weekday = calendar.component(.weekday, from: date.date(in: calendar.timeZone))
        // Calendar's weekday is 1 = Sunday; DayOfWeek is 0 = Monday.
        return DayOfWeek.allCases[(weekday + 5) % 7]
    }
}
