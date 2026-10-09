import Foundation

// The Instamart cart, as `POST api/groceries/cart` and `cart/rebuild` return it.
//
// Everything here is Swiggy's answer relayed by our server: the app never sees
// a Swiggy token, a price we computed, or a SKU it chose. Every field is
// defaulted so a field the server stops sending degrades a line rather than
// failing a payment screen outright.
//
// Mirrors the webapp's `lib/swiggy/types.ts`, `lib/swiggy/pricing.ts` and
// `lib/swiggy/cart-service.ts` (BuildCartResult), and Android's `InstamartCart.kt`.

/// A resolved line: one SKU, a pack count, and how much we trust it. This is
/// exactly what `cart/rebuild` accepts back, so every field is sent — the server
/// re-validates each one before turning a spinId into a purchase.
public struct CartPlanLine: Codable, Hashable, Sendable {
    /// Normalized ingredient name. The key everything joins on.
    public var ingredient: String
    /// Title-cased, for the review screen.
    public var display: String
    public var spinId: String
    /// Carried with spinId: the live tool asks for both, and it is cheap.
    public var skuId: String
    /// The variation's own words, shown verbatim so the user sees the real pack.
    public var packDescription: String
    public var packLabel: String
    public var quantity: Int
    public var unitPrice: Double
    /// The variation's pack shot, when Instamart sent one. Absent is normal.
    /// Not vetted here: the view shows it only when it is `https://`.
    public var imageUrl: String?
    /// "high" | "low". A string on the wire; anything but "high" is low.
    public var confidence: String
    /// Human-readable repairs applied, shown under the line.
    public var notes: [String]

    public var isLowConfidence: Bool { confidence != "high" }

    public init(
        ingredient: String = "",
        display: String = "",
        spinId: String = "",
        skuId: String = "",
        packDescription: String = "",
        packLabel: String = "",
        quantity: Int = 0,
        unitPrice: Double = 0,
        imageUrl: String? = nil,
        confidence: String = "low",
        notes: [String] = []
    ) {
        self.ingredient = ingredient
        self.display = display
        self.spinId = spinId
        self.skuId = skuId
        self.packDescription = packDescription
        self.packLabel = packLabel
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.imageUrl = imageUrl
        self.confidence = confidence
        self.notes = notes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ingredient = (try? c.decode(String.self, forKey: .ingredient)) ?? ""
        display = (try? c.decode(String.self, forKey: .display)) ?? ""
        spinId = (try? c.decode(String.self, forKey: .spinId)) ?? ""
        skuId = (try? c.decode(String.self, forKey: .skuId)) ?? ""
        packDescription = (try? c.decode(String.self, forKey: .packDescription)) ?? ""
        packLabel = (try? c.decode(String.self, forKey: .packLabel)) ?? ""
        quantity = (try? c.decode(Int.self, forKey: .quantity)) ?? 0
        unitPrice = (try? c.decode(Double.self, forKey: .unitPrice)) ?? 0
        imageUrl = try? c.decode(String.self, forKey: .imageUrl)
        confidence = (try? c.decode(String.self, forKey: .confidence)) ?? "low"
        notes = (try? c.decode([String].self, forKey: .notes)) ?? []
    }
}

/// A `CartPlanLine` with Swiggy's own price and quantity attached.
///
/// A line Swiggy has no price for is a line Swiggy did not put in the cart, so
/// it gets no price at all rather than an estimate of ours: the integration
/// agreement forbids showing prices that differ from what Swiggy sent, and a
/// figure for something that will not be delivered was misleading anyway.
///
/// Flattened rather than wrapping a `CartPlanLine` because that is the wire
/// shape (`{...line, inCart, ...}`); `toPlanLine()` recovers the plan half.
public struct PricedCartLine: Codable, Hashable, Sendable {
    public var ingredient: String
    public var display: String
    public var spinId: String
    public var skuId: String
    public var packDescription: String
    public var packLabel: String
    public var quantity: Int
    public var unitPrice: Double
    public var imageUrl: String?
    public var confidence: String
    public var notes: [String]
    /// False when Swiggy's cart has no such line, so it will not be delivered.
    public var inCart: Bool
    /// Swiggy's price for the whole line, or nil when it is not in the cart.
    public var chargedPrice: Double?
    /// The quantity Swiggy actually holds, which may not be the one we asked for.
    public var chargedQuantity: Int
    /// Swiggy capping or dropping part of a line is not something to find out at the door.
    public var quantityMismatch: Bool

    public var isLowConfidence: Bool { confidence != "high" }

    public init(
        ingredient: String = "",
        display: String = "",
        spinId: String = "",
        skuId: String = "",
        packDescription: String = "",
        packLabel: String = "",
        quantity: Int = 0,
        unitPrice: Double = 0,
        imageUrl: String? = nil,
        confidence: String = "low",
        notes: [String] = [],
        inCart: Bool = false,
        chargedPrice: Double? = nil,
        chargedQuantity: Int = 0,
        quantityMismatch: Bool = false
    ) {
        self.ingredient = ingredient
        self.display = display
        self.spinId = spinId
        self.skuId = skuId
        self.packDescription = packDescription
        self.packLabel = packLabel
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.imageUrl = imageUrl
        self.confidence = confidence
        self.notes = notes
        self.inCart = inCart
        self.chargedPrice = chargedPrice
        self.chargedQuantity = chargedQuantity
        self.quantityMismatch = quantityMismatch
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ingredient = (try? c.decode(String.self, forKey: .ingredient)) ?? ""
        display = (try? c.decode(String.self, forKey: .display)) ?? ""
        spinId = (try? c.decode(String.self, forKey: .spinId)) ?? ""
        skuId = (try? c.decode(String.self, forKey: .skuId)) ?? ""
        packDescription = (try? c.decode(String.self, forKey: .packDescription)) ?? ""
        packLabel = (try? c.decode(String.self, forKey: .packLabel)) ?? ""
        quantity = (try? c.decode(Int.self, forKey: .quantity)) ?? 0
        unitPrice = (try? c.decode(Double.self, forKey: .unitPrice)) ?? 0
        imageUrl = try? c.decode(String.self, forKey: .imageUrl)
        confidence = (try? c.decode(String.self, forKey: .confidence)) ?? "low"
        notes = (try? c.decode([String].self, forKey: .notes)) ?? []
        inCart = (try? c.decode(Bool.self, forKey: .inCart)) ?? false
        chargedPrice = try? c.decode(Double.self, forKey: .chargedPrice)
        chargedQuantity = (try? c.decode(Int.self, forKey: .chargedQuantity)) ?? 0
        quantityMismatch = (try? c.decode(Bool.self, forKey: .quantityMismatch)) ?? false
    }

    public func toPlanLine() -> CartPlanLine {
        CartPlanLine(
            ingredient: ingredient,
            display: display,
            spinId: spinId,
            skuId: skuId,
            packDescription: packDescription,
            packLabel: packLabel,
            quantity: quantity,
            unitPrice: unitPrice,
            imageUrl: imageUrl,
            confidence: confidence,
            notes: notes
        )
    }
}

public struct CartPlan: Codable, Hashable, Sendable {
    public var lines: [CartPlanLine]
    /// Display names we could not match. Always shown, never silently dropped.
    public var misses: [String]

    public init(lines: [CartPlanLine] = [], misses: [String] = []) {
        self.lines = lines
        self.misses = misses
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = (try? c.decode([CartPlanLine].self, forKey: .lines)) ?? []
        misses = (try? c.decode([String].self, forKey: .misses)) ?? []
    }
}

/// One row of Swiggy's bill, both halves display copy, e.g. "₹1,234.50".
public struct BillRow: Codable, Hashable, Sendable {
    public var label: String
    public var value: String

    public init(label: String = "", value: String = "") {
        self.label = label
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
    }
}

public struct BillBreakdown: Codable, Hashable, Sendable {
    public var lineItems: [BillRow]
    public var toPay: BillRow

    public init(lineItems: [BillRow] = [], toPay: BillRow = BillRow()) {
        self.lineItems = lineItems
        self.toPay = toPay
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineItems = (try? c.decode([BillRow].self, forKey: .lineItems)) ?? []
        toPay = (try? c.decode(BillRow.self, forKey: .toPay)) ?? BillRow()
    }
}

public struct UnserviceableItem: Codable, Hashable, Sendable {
    public var itemName: String

    public init(itemName: String = "") { self.itemName = itemName }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemName = (try? c.decode(String.self, forKey: .itemName)) ?? ""
    }
}

/// Swiggy's cart, narrowed to what the review screen reads.
public struct InstamartCart: Codable, Hashable, Sendable {
    /// Set when Swiggy has expired or dropped the cart underneath us.
    public var cartAbsent: Bool
    public var cartTotalAmount: String
    public var billBreakdown: BillBreakdown
    public var addressWarning: String?
    public var unserviceableItems: [UnserviceableItem]

    public init(
        cartAbsent: Bool = false,
        cartTotalAmount: String = "",
        billBreakdown: BillBreakdown = BillBreakdown(),
        addressWarning: String? = nil,
        unserviceableItems: [UnserviceableItem] = []
    ) {
        self.cartAbsent = cartAbsent
        self.cartTotalAmount = cartTotalAmount
        self.billBreakdown = billBreakdown
        self.addressWarning = addressWarning
        self.unserviceableItems = unserviceableItems
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cartAbsent = (try? c.decode(Bool.self, forKey: .cartAbsent)) ?? false
        cartTotalAmount = (try? c.decode(String.self, forKey: .cartTotalAmount)) ?? ""
        billBreakdown = (try? c.decode(BillBreakdown.self, forKey: .billBreakdown)) ?? BillBreakdown()
        addressWarning = try? c.decode(String.self, forKey: .addressWarning)
        unserviceableItems = (try? c.decode([UnserviceableItem].self, forKey: .unserviceableItems)) ?? []
    }
}

/// The saved Swiggy address the server chose to shop against. `addressLine`
/// and `addressTag` are get_addresses' live names, not the reference docs'.
public struct InstamartAddress: Codable, Hashable, Sendable {
    public var id: String
    public var addressLine: String
    public var addressTag: String?

    public init(id: String = "", addressLine: String = "", addressTag: String? = nil) {
        self.id = id
        self.addressLine = addressLine
        self.addressTag = addressTag
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        addressLine = (try? c.decode(String.self, forKey: .addressLine)) ?? ""
        addressTag = try? c.decode(String.self, forKey: .addressTag)
    }
}

/// The response of `POST api/groceries/cart` and `api/groceries/cart/rebuild`.
public struct CartBuild: Codable, Hashable, Sendable {
    public var address: InstamartAddress
    public var plan: CartPlan
    public var cart: InstamartCart
    /// Plan lines carrying Swiggy's own price, for the review screen.
    public var priced: [PricedCartLine]
    /// The build route's ingredient cap. Rebuild does not send it: 0.
    public var maxIngredients: Int

    public init(
        address: InstamartAddress = InstamartAddress(),
        plan: CartPlan = CartPlan(),
        cart: InstamartCart = InstamartCart(),
        priced: [PricedCartLine] = [],
        maxIngredients: Int = 0
    ) {
        self.address = address
        self.plan = plan
        self.cart = cart
        self.priced = priced
        self.maxIngredients = maxIngredients
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = (try? c.decode(InstamartAddress.self, forKey: .address)) ?? InstamartAddress()
        plan = (try? c.decode(CartPlan.self, forKey: .plan)) ?? CartPlan()
        cart = (try? c.decode(InstamartCart.self, forKey: .cart)) ?? InstamartCart()
        priced = (try? c.decode([PricedCartLine].self, forKey: .priced)) ?? []
        maxIngredients = (try? c.decode(Int.self, forKey: .maxIngredients)) ?? 0
    }
}

/// `POST api/groceries/checkout`'s answer.
///
/// A 2xx is a placed order, always. `recorded` true means `order` is already
/// saved on the week's list; false means the order is still real but the app
/// must PATCH it on itself (`InstamartOrders.prependOrder`). Everything but
/// `orderId` is defaulted so a decode can never turn a placed order into an
/// apparent failure over a missing field — a malformed `order` simply reads as
/// nil, and the app records the order itself.
///
/// Without an id there is nothing to show or record, so that 2xx does not
/// decode; the repository reports it as an unconfirmed checkout.
public struct CheckoutResponse: Decodable, Hashable, Sendable {
    public var orderId: String
    public var total: String
    public var order: StoredOrder?
    public var recorded: Bool

    public init(orderId: String, total: String = "", order: StoredOrder? = nil, recorded: Bool = false) {
        self.orderId = orderId
        self.total = total
        self.order = order
        self.recorded = recorded
    }

    private enum CodingKeys: String, CodingKey {
        case orderId, total, order, recorded
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Swiggy's ids are numeric strings; a bare number is read too rather
        // than losing a placed order to a type change upstream.
        let id = (try? c.decode(String.self, forKey: .orderId))
            ?? (try? c.decode(Int64.self, forKey: .orderId)).map(String.init)
        guard let id, !id.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .orderId, in: c, debugDescription: "A placed order needs an id"
            )
        }
        orderId = id
        total = (try? c.decode(String.self, forKey: .total)) ?? ""
        order = try? c.decode(StoredOrder.self, forKey: .order)
        recorded = (try? c.decode(Bool.self, forKey: .recorded)) ?? false
    }
}
