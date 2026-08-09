import Foundation

/// One reminder, resolved to the evening it fires and the words it will show.
public struct PrepReminder: Equatable, Sendable {
    /// The day being prepped *for*.
    public var targetDate: PlanDate
    /// The evening before — when the notification fires.
    public var fireDate: PlanDate
    public var title: String
    public var body: String
    public var lines: [String]

    public init(
        targetDate: PlanDate,
        fireDate: PlanDate,
        title: String,
        body: String,
        lines: [String]
    ) {
        self.targetDate = targetDate
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.lines = lines
    }
}

/// Decides which prep reminders a phone should have pending, given the plans it
/// already holds.
///
/// Separate from the scheduler that hands these to `UNUserNotificationCenter`, so
/// all of the date arithmetic and the skip rules can be tested with `swift test` —
/// no simulator, and no system permission prompt that nothing can dismiss.
public enum PrepReminderPlanner {
    /// How far ahead to lay reminders down. A week means opening the app once every
    /// seven days is enough, which is roughly the cadence of planning a week.
    public static let horizonDays = 7

    /// The week keys needed to cover every target day inside the horizon — at most
    /// two, and exactly one when the horizon does not straddle a Monday.
    public static func weekKeys(
        from now: PlanDate,
        horizonDays: Int = horizonDays
    ) -> [String] {
        guard horizonDays > 0 else { return [] }
        var keys: [String] = []
        for offset in 1...horizonDays {
            let key = WeekDates.format(WeekDates.mondayOf(now.adding(days: offset)))
            if !keys.contains(key) { keys.append(key) }
        }
        return keys
    }

    /// The reminders to have pending right now.
    ///
    /// - Parameters:
    ///   - currentHour: the hour of day on `now`, used only to decide whether
    ///     tonight's reminder has already been missed. Passed in rather than read
    ///     from the clock so this stays a pure function.
    public static func reminders(
        plans: [MealPlan],
        from now: PlanDate,
        hour: Int,
        currentHour: Int,
        enabledTypes: [MealType] = MealType.allCases,
        horizonDays: Int = horizonDays
    ) -> [PrepReminder] {
        var reminders: [PrepReminder] = []
        var seen: Set<Int> = []

        for plan in plans {
            guard let weekStart = PlanDate(iso: plan.weekStartDate) else { continue }

            for (day, targetDate) in WeekDates.daysOfWeek(from: weekStart) {
                // The reminder fires the *evening before* the day it describes.
                let fireDate = targetDate.adding(days: -1)
                let offset = fireDate - now
                guard offset >= 0, offset < horizonDays else { continue }

                // Tonight's is only worth setting if its hour has not gone by.
                if offset == 0, currentHour >= hour { continue }

                let items = PrepTonight.itemsForTomorrow(
                    plan.meals(for: day), enabledTypes: enabledTypes
                )
                guard !items.isEmpty else { continue }

                // Two plans overlapping on a day would otherwise stack two
                // notifications on the same evening.
                guard seen.insert(targetDate.epochDays).inserted else { continue }

                let copy = PrepTonight.buildReminderCopy(
                    items: items, tomorrowDayLabel: day.displayName
                )
                reminders.append(
                    PrepReminder(
                        targetDate: targetDate,
                        fireDate: fireDate,
                        title: copy.title,
                        body: copy.body,
                        lines: copy.lines
                    )
                )
            }
        }

        // Chronological, so the pending list reads the way the week does.
        return reminders.sorted { $0.fireDate.epochDays < $1.fireDate.epochDays }
    }
}
