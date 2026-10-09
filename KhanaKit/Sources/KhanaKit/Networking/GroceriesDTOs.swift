import Foundation

// Wire shapes for the `api/groceries` routes, `api/geo` and the shopping-list
// PATCH. The cart and order models themselves live in `Models/` (CartBuild,
// StoredOrder, …) because the logic layer reasons about them; only the
// envelopes are here. Mirrors Android's `GroceriesDto.kt` / `ShoppingListDto.kt`.

/// `GET api/groceries/status`. Only meaningful on a 200 — a 404 (feature off for
/// this user or deployment) is `InstamartAvailability.unavailable`, not a body.
/// `expiresAt` is epoch millis, nil when no token is held.
public struct GroceriesStatusResponse: Decodable, Hashable, Sendable {
    public var connected: Bool
    public var expiresAt: Int64?

    public init(connected: Bool = false, expiresAt: Int64? = nil) {
        self.connected = connected
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey { case connected, expiresAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        expiresAt = try? c.decode(Int64.self, forKey: .expiresAt)
    }
}

/// `GET api/groceries/connect`: the Swiggy consent URL to open in an
/// `ASWebAuthenticationSession`.
public struct ConnectResponse: Decodable, Hashable, Sendable {
    public var authorizeUrl: String

    public init(authorizeUrl: String) { self.authorizeUrl = authorizeUrl }
}

/// `GET api/geo`: the caller's country as Vercel's edge saw it. Nil off Vercel
/// or when the edge did not say; `canOrderInstamart` fails closed on nil.
public struct GeoResponse: Decodable, Hashable, Sendable {
    public var country: String?

    public init(country: String? = nil) { self.country = country }

    private enum CodingKeys: String, CodingKey { case country }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = try? c.decode(String.self, forKey: .country)
    }
}

/// `POST api/groceries/cart`. Match the scoped list to SKUs and write Swiggy's
/// cart; places nothing.
///
/// `haveAlready` should already include the names on live orders — the
/// webapp's `haveAlready ∪ ordered` — so a second cart in a week cannot re-buy
/// what is on its way.
///
/// Not `Encodable`, deliberately. `scoped` must go out exactly as the webapp's
/// `ScopedShoppingList` does: `categorized` an object whose keys are in
/// presentation order, because that is the order the server's ingredient cap
/// and the review screen both walk. `JSONEncoder` does not keep keyed-container
/// order, so the body is written by `jsonData` through the order-keeping
/// `JSONValue` instead — and there is no `Encodable` path to reach for by mistake.
public struct BuildCartRequest: Hashable, Sendable {
    public var scoped: ScopedShoppingList
    public var haveAlready: [String]
    public var isVegetarian: Bool

    public init(scoped: ScopedShoppingList, haveAlready: [String], isVegetarian: Bool) {
        self.scoped = scoped
        self.haveAlready = haveAlready
        self.isVegetarian = isVegetarian
    }

    /// `{"scoped":{"categorized":{…},"ingredients":[…],"weights":{name:{amount,unit}}},
    /// "haveAlready":[…],"isVegetarian":…}`. The server rejects a body without
    /// `categorized` and `weights`, so both are always present, even empty.
    public var jsonData: Data {
        JSONValue.object([
            ("scoped", .object([
                ("categorized", .object(scoped.categorized.map { section in
                    (section.name, .array(section.items.map { item in
                        .object([
                            ("name", .string(item.name)),
                            ("amount", .number(item.amount)),
                            ("unit", .string(item.unit)),
                        ])
                    }))
                })),
                ("ingredients", .array(scoped.ingredients.map(JSONValue.string))),
                ("weights", .object(orderedWeights.map { name, weight in
                    (name, .object([("amount", .number(weight.amount)), ("unit", .string(weight.unit))]))
                })),
            ])),
            ("haveAlready", .array(haveAlready.map(JSONValue.string))),
            ("isVegetarian", .bool(isVegetarian)),
        ]).jsonData
    }

    /// `weights` in `ingredients` order — the order the webapp builds it in —
    /// then any stragglers alphabetically, so the body is deterministic.
    private var orderedWeights: [(String, IngredientAmount)] {
        var seen = Set<String>()
        var result: [(String, IngredientAmount)] = []
        for name in scoped.ingredients {
            guard let weight = scoped.weights[name], seen.insert(name).inserted else { continue }
            result.append((name, weight))
        }
        for name in scoped.weights.keys.sorted() where !seen.contains(name) {
            result.append((name, scoped.weights[name]!))
        }
        return result
    }
}

/// `POST api/groceries/cart/rebuild`: the kept lines, sent back exactly as
/// received (the server re-validates every field), plus the misses to carry over.
public struct RebuildCartRequest: Encodable, Hashable, Sendable {
    public var lines: [CartPlanLine]
    public var misses: [String]

    public init(lines: [CartPlanLine], misses: [String]) {
        self.lines = lines
        self.misses = misses
    }
}

/// `POST api/groceries/checkout`. `expectedTotal` is the To-pay the user
/// confirmed, read with `InstamartCartLogic.parseRupees`; the server refuses
/// (409 `repriced`) rather than charge anything else. `weekStartDate` and
/// `items` (`InstamartCartLogic.orderedItems`) let the server record the order
/// itself.
public struct CheckoutRequest: Encodable, Hashable, Sendable {
    public var expectedTotal: Double
    public var weekStartDate: String
    public var items: [OrderedItem]

    public init(expectedTotal: Double, weekStartDate: String, items: [OrderedItem]) {
        self.expectedTotal = expectedTotal
        self.weekStartDate = weekStartDate
        self.items = items
    }
}

/// `PATCH api/shopping-list/{week}` with either or both fields.
///
/// The server treats a *present* field as an update and 400s on a body
/// carrying neither, so both are optional and a nil is left off the wire
/// entirely (synthesized `Encodable` uses `encodeIfPresent`). An empty array is
/// not nil: it is sent, and clears the field. A haveAlready-only request
/// encodes byte-for-byte like `UpdateHaveAlreadyRequest`.
public struct UpdateShoppingListRequest: Encodable, Hashable, Sendable {
    /// Server caps at 500 items, 120 chars each.
    public var haveAlready: [String]?
    /// At most `InstamartOrders.maxStoredOrders`; the server 400s on more.
    public var orders: [StoredOrder]?

    public init(haveAlready: [String]? = nil, orders: [StoredOrder]? = nil) {
        self.haveAlready = haveAlready
        self.orders = orders
    }
}
