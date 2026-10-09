import Foundation

/// The week's ingredients split three ways — see `InstamartOrders.deriveItemStates`.
public struct ItemStates: Hashable, Sendable {
    /// Normalized names on their way in a live order.
    public var ordered: Set<String>
    /// Display names still to buy, in the order they were given.
    public var toBuy: [String]

    public init(ordered: Set<String>, toBuy: [String]) {
        self.ordered = ordered
        self.toBuy = toBuy
    }
}

/// See `InstamartOrders.mergeDeliveredIntoHave`.
public struct MergedHave: Hashable, Sendable {
    public var haveAlready: Set<String>
    /// Write only when true, so re-opening on an already-merged order is free.
    public var changed: Bool

    public init(haveAlready: Set<String>, changed: Bool) {
        self.haveAlready = haveAlready
        self.changed = changed
    }
}

/// What one get_delivery_status response said — see `InstamartOrders.readOrderStatus`.
public struct StatusRead: Hashable, Sendable {
    public var status: OrderStatus
    public var statusLabel: String
    /// ISO instant on our clock, or nil when there is no believable estimate.
    public var etaAt: String?

    public init(status: OrderStatus, statusLabel: String, etaAt: String?) {
        self.status = status
        self.statusLabel = statusLabel
        self.etaAt = etaAt
    }
}

/// What the shopping list knows about orders already placed. Port of the
/// webapp's `lib/swiggy/orders.ts` and Android's `InstamartOrders.kt` — behavior
/// must stay in lockstep with both.
///
/// "Ordered" is a temporary state on the way to "have already", not a permanent
/// third category: when Swiggy says delivered, the items move into haveAlready
/// and the order goes quiet. That keeps every other consumer of the list —
/// exports, the cart builder, the counts — speaking the two-state vocabulary
/// they already speak.
///
/// Everything here is pure; time comes in as epoch milliseconds so tests pin it.
/// The I/O lives in the App target's view models and repository.
public enum InstamartOrders {

    /// How many orders one week's shopping list remembers. The server rejects a
    /// longer list, so `prependOrder` trims to this before anything is written.
    public static let maxStoredOrders = 20

    /// How stale a live order's status must be before we ask Swiggy again.
    public static let refreshThrottleMillis: Int64 = 60_000

    /// Longer than this and we do not believe the number. Instamart is 10–30 minutes.
    private static let maxPlausibleETAMillis: Double = 6 * 3_600_000

    /// The fields that make a get_delivery_status payload one we understand.
    /// Without this check an in-progress order and a payload from a tool we have
    /// never seen would both read as "live".
    private static let knownStatusFields = [
        "delivered", "cancelled", "statusText", "etaText", "deliveryBy", "serverNow", "pollIntervalSec",
    ]

    /// Add a just-placed order to the week's orders, newest first.
    ///
    /// Replaces rather than duplicates an order already recorded under the same
    /// id, so a retried write is harmless. Trims the oldest past `maxStoredOrders`.
    public static func prependOrder(_ existing: [StoredOrder], _ order: StoredOrder) -> [StoredOrder] {
        let rest = existing.filter { $0.orderId != order.orderId }
        return Array(([order] + rest).prefix(maxStoredOrders))
    }

    /// Split the week's ingredients three ways.
    ///
    /// `haveAlready` deliberately wins over ordered: ticking an item by hand is a
    /// statement about the user's own kitchen, and no delivery status should be
    /// allowed to argue with it.
    ///
    /// Only live orders count. A delivered order's items are already in (or on
    /// their way into) haveAlready; a cancelled order's never came, so they go
    /// back to "to buy".
    public static func deriveItemStates(
        ingredients: [String],
        haveAlready: Set<String>,
        orders: [StoredOrder]
    ) -> ItemStates {
        var ordered = Set<String>()
        for order in orders where order.orderStatus == .live {
            for item in order.items where !item.name.isEmpty && !haveAlready.contains(item.name) {
                ordered.insert(item.name)
            }
        }

        let toBuy = ingredients.filter { name in
            let key = ShoppingScope.normalizeIngredientName(name)
            return !haveAlready.contains(key) && !ordered.contains(key)
        }

        return ItemStates(ordered: ordered, toBuy: toBuy)
    }

    /// Fold delivered orders' items into haveAlready.
    ///
    /// `changed` is the whole point: the caller writes to the server only when it
    /// is true, so re-opening the pane on an already-merged order is free.
    public static func mergeDeliveredIntoHave(
        orders: [StoredOrder],
        haveAlready: Set<String>
    ) -> MergedHave {
        var next = haveAlready
        var changed = false

        for order in orders where order.orderStatus == .delivered {
            for item in order.items where !item.name.isEmpty && !next.contains(item.name) {
                next.insert(item.name)
                changed = true
            }
        }

        return MergedHave(haveAlready: next, changed: changed)
    }

    /// Whether this order is worth asking Swiggy about right now.
    ///
    /// False for an order whose checkedAt is "now" — which every order a status
    /// sync touches carries — so a refresh that re-runs when `orders` changes
    /// finds nothing due and cannot loop.
    public static func shouldRefresh(_ order: StoredOrder, nowMillis: Int64) -> Bool {
        guard order.orderStatus == .live else { return false }

        // An unreadable timestamp means we have no evidence it was ever checked.
        guard let checked = parseISOMillis(order.checkedAt) else { return true }

        return nowMillis - checked >= refreshThrottleMillis
    }

    /// Read a status out of a get_delivery_status response.
    ///
    /// The tool reports terminal states as boolean flags rather than an enum —
    /// `delivered` and `cancelled` — with `statusText` carrying the
    /// human-readable words and `etaText` the formatted ETA. Both flags are
    /// optional and absent while the order is simply on its way.
    ///
    /// Returns nil when nothing recognisable is present, so an unfamiliar
    /// payload leaves the stored status alone. Reporting "live" for an
    /// unreadable response would be a guess about an order that may already have
    /// arrived, and reporting "delivered" would claim groceries are in the
    /// kitchen when they are not.
    ///
    /// Swiggy's reference docs for this tool have been wrong three times on this
    /// integration, so the shape is treated as a lead: anything unrecognised
    /// falls through to nil rather than to an assumption.
    public static func readOrderStatus(
        _ raw: JSONValue?,
        nowMillis: Int64 = InstamartOrders.millis(Date())
    ) -> StatusRead? {
        guard let raw, case .object = raw else { return nil }

        // Presence, not value: the webapp's `!== undefined` counts an explicit
        // null as present, and so does the subscript (`.null`, not nil).
        guard knownStatusFields.contains(where: { raw[$0] != nil }) else { return nil }

        let label = ["statusText", "etaText"]
            .compactMap { raw[$0]?.stringValue }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // An order cannot be both. If Swiggy ever says so, "arrived" is the
        // safer reading of the contradiction than "written off". Only a real
        // JSON `true` counts, as with the webapp's `=== true`.
        let status: OrderStatus
        if raw["delivered"] == .bool(true) {
            status = .delivered
        } else if raw["cancelled"] == .bool(true) {
            status = .cancelled
        } else {
            status = .live
        }

        return StatusRead(status: status, statusLabel: label ?? "", etaAt: readETA(raw, nowMillis: nowMillis))
    }

    /// Apply a status read to a stored order, stamping `nowISO` as its checkedAt
    /// so the throttle holds. The ETA is replaced too, not merged: without it
    /// the countdown is dead code, and a stale estimate is worse than none.
    public static func withStatus(_ order: StoredOrder, read: StatusRead, nowISO: String) -> StoredOrder {
        var next = order
        next.status = read.status.wire
        next.statusLabel = read.statusLabel
        next.etaAt = read.etaAt
        next.checkedAt = nowISO
        return next
    }

    /// The countdown, or nil when there is nothing to count towards.
    ///
    /// Stops at zero rather than going negative: a strip reading "-4 min" looks
    /// broken, and Instamart ETAs slip often enough that it would be a common
    /// sight.
    public static func formatCountdown(etaAt: String?, nowMillis: Int64) -> String? {
        guard let etaAt, !etaAt.isEmpty, let eta = parseISOMillis(etaAt) else { return nil }

        let remaining = eta - nowMillis
        if remaining <= 0 { return "Arriving any moment" }
        if remaining < 60_000 { return "Arriving in under a minute" }

        // Math.round: half up. Positive here, where that and Swift's
        // schoolbook rounding agree.
        let minutes = Int64((Double(remaining) / 60_000).rounded(.toNearestOrAwayFromZero))
        return "Arriving in \(minutes) min"
    }

    // MARK: - Time

    /// `Date.prototype.toISOString` — always three fractional digits and a `Z`.
    /// The webapp writes placedAt / checkedAt / etaAt in this form, and the same
    /// documents are written from all three clients, so the app writes it too.
    public static func toISOString(epochMillis: Int64) -> String {
        // Floor, not truncate, so an instant before 1970 keeps a positive
        // millisecond part ("…59.999Z"), as JavaScript prints it.
        let seconds = epochMillis >= 0 ? epochMillis / 1000 : (epochMillis - 999) / 1000
        let millis = epochMillis - seconds * 1000
        let parts = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, Int(millis)
        )
    }

    /// Epoch millis of an ISO instant, with or without fractional seconds, `Z`
    /// or an offset; nil when it does not parse.
    public static func parseISOMillis(_ iso: String?) -> Int64? {
        guard let trimmed = iso?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        let date = (try? Date(trimmed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(trimmed, strategy: Date.ISO8601FormatStyle()))
        return date.map(millis)
    }

    /// Epoch milliseconds for a `Date` — the clock every function here takes.
    public static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Internals

    /// The ETA as an instant on our own clock.
    ///
    /// `deliveryBy` and `serverNow` are both epoch milliseconds *from Swiggy*, so
    /// the difference between them is a duration we can trust even when their
    /// clock — or the phone's — is wrong. Anchoring that duration to now is what
    /// makes the countdown correct on a device whose time is off, which is
    /// exactly where a countdown gives itself away.
    private static func readETA(_ record: JSONValue, nowMillis: Int64) -> String? {
        guard let deliveryBy = number(record["deliveryBy"]),
              let serverNow = number(record["serverNow"]) else { return nil }

        let remaining = deliveryBy - serverNow
        // Zero is "already due", which the countdown has its own words for; a
        // negative or absurd value is a bad payload, and showing nothing beats
        // showing a number we do not believe.
        guard remaining > 0, remaining <= maxPlausibleETAMillis else { return nil }

        // Truncated toward zero, as `new Date(ms)` clips a fractional time value.
        return toISOString(epochMillis: nowMillis + Int64(remaining))
    }

    /// The webapp's `Number(x)`, for the cases that matter: a JSON number or a
    /// numeric string. Narrower on junk: JavaScript reads an explicit null, a
    /// boolean or "" as 0 or 1; here they are simply "no number". With epoch
    /// values on the other side the webapp's bounds reject those anyway, so the
    /// clients agree on every payload that could plausibly arrive.
    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case let .number(number):
            return number.isFinite ? number : nil
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let number = Double(trimmed), number.isFinite else { return nil }
            return number
        default:
            return nil
        }
    }
}
