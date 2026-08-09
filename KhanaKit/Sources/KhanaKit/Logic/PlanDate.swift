import Foundation

/// A calendar date with no time and no time zone — the equivalent of Kotlin's
/// `LocalDate`, which is what the Android client uses for all week arithmetic.
///
/// Deliberately not `Foundation.Date`: week keys are plain `yyyy-MM-dd` strings
/// that the server treats as opaque, and doing the arithmetic on instants would
/// introduce DST and time-zone bugs the other clients don't have. The conversions
/// use the standard civil-calendar algorithm, so they're exact and testable
/// without a `Calendar` or a `TimeZone`.
public struct PlanDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: - Epoch conversion (days since 1970-01-01)

    /// Days from civil date — Howard Hinnant's `days_from_civil`.
    public var epochDays: Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                   // [0, 399]
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy           // [0, 146096]
        return era * 146097 + doe - 719468
    }

    /// Civil date from days — Hinnant's `civil_from_days`.
    public init(epochDays: Int) {
        let z = epochDays + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097                                // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)         // [0, 365]
        let mp = (5 * doy + 2) / 153                              // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                      // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)                           // [1, 12]
        self.init(year: y + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    // MARK: - Arithmetic

    public func adding(days: Int) -> PlanDate { PlanDate(epochDays: epochDays + days) }

    public static func - (lhs: PlanDate, rhs: PlanDate) -> Int {
        lhs.epochDays - rhs.epochDays
    }

    public static func < (lhs: PlanDate, rhs: PlanDate) -> Bool {
        lhs.epochDays < rhs.epochDays
    }

    /// Monday-based. 1970-01-01 was a Thursday, i.e. index 3 in a Monday-first week.
    public var dayOfWeek: DayOfWeek {
        let index = ((epochDays + 3) % 7 + 7) % 7
        return DayOfWeek.allCases[index]
    }

    // MARK: - ISO string

    /// `"yyyy-MM-dd"` — exactly what every API path segment and week key uses.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    // MARK: - Bridging

    /// Today in the given time zone. Defaults to the device's current zone, matching
    /// Android's `Clock.System.todayIn(TimeZone.currentSystemDefault())`.
    public static func today(
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> PlanDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return PlanDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Noon in the given zone, so formatting can never slip a day across a DST edge.
    public func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return calendar.date(from: c) ?? Date()
    }

    /// `"Aug"` — three-letter English month, matching the other clients' labels
    /// (`month.name.take(3)` on Android, `format(date, 'MMM')` on web). Deliberately
    /// not localized: these strings appear in shared text and PDFs alongside the
    /// server's own English day names.
    public var shortMonthName: String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard (1...12).contains(month) else { return "" }
        return names[month - 1]
    }

    /// `"August"` — full English month name.
    public var fullMonthName: String {
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        guard (1...12).contains(month) else { return "" }
        return names[month - 1]
    }
}
