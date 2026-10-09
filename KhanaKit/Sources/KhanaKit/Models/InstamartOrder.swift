import Foundation

/// One ingredient inside an Instamart order. `name` is normalized (the key the
/// shopping list joins on); `display` is for humans.
public struct OrderedItem: Codable, Hashable, Sendable {
    public var name: String
    public var display: String

    public init(name: String = "", display: String = "") {
        self.name = name
        self.display = display
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        display = (try? c.decode(String.self, forKey: .display)) ?? ""
    }
}

/// The three states an order can be in. See `StoredOrder.status` for the wire form.
public enum OrderStatus: String, Sendable, CaseIterable {
    case live
    /// Terminal: the items move into `haveAlready`.
    case delivered
    /// Terminal like `delivered`, but the opposite outcome: the items go back on
    /// the shopping list rather than into `haveAlready`.
    case cancelled

    /// Anything unrecognised reads as `.live` — the same rule as the webapp's
    /// `sanitizeOrders`. A live order is re-checked; a terminal one never is,
    /// so the guess that can still correct itself is the safe one.
    public init(wire: String?) {
        self = wire.flatMap(OrderStatus.init(rawValue:)) ?? .live
    }

    public var wire: String { rawValue }
}

/// One placed order, as stored on the week's shopping-list document.
///
/// Every field but `orderId` is defaulted so a partial or older record still
/// decodes: the list it rides on must never fail to load because of an order.
/// The id is the one thing a record cannot do without — the server's
/// `sanitizeOrders` refuses an order without one, so neither do we.
public struct StoredOrder: Codable, Hashable, Sendable, Identifiable {
    public var orderId: String
    /// ISO, `toISOString` form.
    public var placedAt: String
    /// Swiggy's display copy, e.g. "₹1,234.50". Never re-derived by us.
    public var total: String
    /// "live" | "delivered" | "cancelled". Kept as a string on the wire so a
    /// value this build has never heard of decodes rather than failing the whole
    /// shopping list; read it through `orderStatus`.
    public var status: String
    /// Swiggy's own words, as last fetched. Shown verbatim.
    public var statusLabel: String
    /// When the order is expected, as an ISO instant on *our* clock.
    ///
    /// Derived from Swiggy's `deliveryBy` minus its `serverNow` — a duration —
    /// then anchored to the moment we received it. Only the duration is trusted,
    /// which cancels both a skewed server clock and a skewed device one. Nil
    /// whenever Swiggy did not give a usable estimate, and then left off the
    /// wire entirely rather than sent as `null`.
    public var etaAt: String?
    /// ISO. Drives the refresh throttle.
    public var checkedAt: String
    public var items: [OrderedItem]

    public var id: String { orderId }
    public var orderStatus: OrderStatus { OrderStatus(wire: status) }

    public init(
        orderId: String,
        placedAt: String = "",
        total: String = "",
        status: String = OrderStatus.live.wire,
        statusLabel: String = "",
        etaAt: String? = nil,
        checkedAt: String = "",
        items: [OrderedItem] = []
    ) {
        self.orderId = orderId
        self.placedAt = placedAt
        self.total = total
        self.status = status
        self.statusLabel = statusLabel
        self.etaAt = etaAt
        self.checkedAt = checkedAt
        self.items = items
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let orderId = try? c.decode(String.self, forKey: .orderId), !orderId.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .orderId, in: c, debugDescription: "An order needs an id"
            )
        }
        self.orderId = orderId
        placedAt = (try? c.decode(String.self, forKey: .placedAt)) ?? ""
        total = (try? c.decode(String.self, forKey: .total)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? OrderStatus.live.wire
        statusLabel = (try? c.decode(String.self, forKey: .statusLabel)) ?? ""
        etaAt = try? c.decode(String.self, forKey: .etaAt)
        checkedAt = (try? c.decode(String.self, forKey: .checkedAt)) ?? ""
        items = c.decodeLossyArray(of: OrderedItem.self, forKey: .items) ?? []
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array element by element, skipping any element that fails.
    /// Nil when the key is absent, `null`, or not an array at all.
    ///
    /// `try? decode([T].self)` is all-or-nothing; for the order records riding
    /// on a shopping list, one bad record must not cost every other one.
    func decodeLossyArray<T: Decodable>(of type: T.Type, forKey key: Key) -> [T]? {
        guard var array = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var result: [T] = []
        while !array.isAtEnd {
            if let element = try? array.decode(T.self) {
                result.append(element)
            } else if (try? array.decode(SkippedElement.self)) == nil {
                // Could not even step past it; stop rather than spin.
                break
            }
        }
        return result
    }
}

/// Decodes anything without reading it — used to step an unkeyed container
/// past an element that failed to decode as the type we wanted.
private struct SkippedElement: Decodable {
    init(from decoder: any Decoder) throws {}
}
