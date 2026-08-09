import Foundation

/// Week arithmetic. The week starts on **Monday** everywhere in this product —
/// the server keys meal plans by `startOfWeek(date, { weekStartsOn: 1 })`
/// (`lib/utils.ts:23`) and Android does the same, so nothing here is configurable.
public enum WeekDates {

    public static func today(timeZone: TimeZone = .current, now: Date = Date()) -> PlanDate {
        PlanDate.today(timeZone: timeZone, now: now)
    }

    /// The Monday of the week containing `date`.
    public static func mondayOf(_ date: PlanDate) -> PlanDate {
        date.adding(days: -date.dayOfWeek.index)
    }

    public static func currentMonday(timeZone: TimeZone = .current, now: Date = Date()) -> PlanDate {
        mondayOf(today(timeZone: timeZone, now: now))
    }

    /// The week key sent to the API: ISO `yyyy-MM-dd`.
    public static func format(_ date: PlanDate) -> String { date.isoString }

    /// The seven days of the week beginning at `weekStart`, paired with their dates.
    public static func daysOfWeek(from weekStart: PlanDate) -> [(day: DayOfWeek, date: PlanDate)] {
        DayOfWeek.allCases.enumerated().map { index, day in
            (day, weekStart.adding(days: index))
        }
    }

    public static func date(of day: DayOfWeek, in weekStart: PlanDate) -> PlanDate {
        weekStart.adding(days: day.index)
    }

    /// Moves a week key forward or back by whole weeks, preserving the ISO format.
    public static func shift(weekStartDate: String, byWeeks weeks: Int) -> String {
        guard let start = PlanDate(iso: weekStartDate) else { return weekStartDate }
        return start.adding(days: weeks * 7).isoString
    }

    /// `"Aug 4–10, 2026"` within one month, `"Jul 28 – Aug 3, 2026"` across two.
    /// Spacing differs between the two forms; that is intentional and matches
    /// `WeekViewModel.kt:1175-1185`.
    public static func rangeLabel(weekStartDate: String) -> String {
        guard let start = PlanDate(iso: weekStartDate) else { return "" }
        let end = start.adding(days: 6)
        if start.month == end.month {
            return "\(start.shortMonthName) \(start.day)–\(end.day), \(end.year)"
        }
        return "\(start.shortMonthName) \(start.day) – \(end.shortMonthName) \(end.day), \(end.year)"
    }

    /// The day of `weekStartDate`'s week that is today, or nil when today falls
    /// outside it.
    public static func todayIndex(
        in weekStartDate: String,
        today: PlanDate = WeekDates.today()
    ) -> Int? {
        guard let start = PlanDate(iso: weekStartDate) else { return nil }
        let offset = today - start
        return (0...6).contains(offset) ? offset : nil
    }

    /// As `todayIndex`, for tomorrow. Nil on a Sunday of the displayed week —
    /// tomorrow's plan then lives in next week's menu.
    public static func tomorrowIndex(
        in weekStartDate: String,
        today: PlanDate = WeekDates.today()
    ) -> Int? {
        guard let start = PlanDate(iso: weekStartDate) else { return nil }
        let offset = today.adding(days: 1) - start
        return (0...6).contains(offset) ? offset : nil
    }

    public static func day(at index: Int) -> DayOfWeek? {
        (0...6).contains(index) ? DayOfWeek.allCases[index] : nil
    }
}
