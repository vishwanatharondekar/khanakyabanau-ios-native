import XCTest
@testable import KhanaKit

/// What goes over the wire to `api/groceries/*`, `api/geo` and the
/// shopping-list PATCH. Port of Android's `GroceriesDtoTest.kt`, plus the
/// endpoint table (paths, auth, timeout budgets).
final class GroceriesCodingTests: XCTestCase {

    private func string(_ data: Data?) -> String {
        String(decoding: data ?? Data(), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Cart request

    /// Deliberately not alphabetical, and a category order JSONEncoder would
    /// scramble: the scope builder's order is what the server walks.
    func testCartRequestMatchesTheWebShapeAndKeepsCategoryOrder() {
        let scoped = ScopedShoppingList(
            categorized: [
                CategorySection(name: "Vegetables", items: [Ingredient(name: "onion", amount: 2, unit: "kg")]),
                CategorySection(name: "Dairy", items: [Ingredient(name: "paneer", amount: 200, unit: "g")]),
                CategorySection(name: "Grains & Pulses", items: [Ingredient(name: "rice", amount: 1.5, unit: "kg")]),
                CategorySection(name: "Other", items: [Ingredient(name: "say \"hi\"\n", amount: 0, unit: "")]),
            ],
            ingredients: ["onion", "paneer", "rice", "say \"hi\"\n"],
            weights: [
                "onion": IngredientAmount(amount: 2, unit: "kg"),
                "paneer": IngredientAmount(amount: 200, unit: "g"),
                "rice": IngredientAmount(amount: 1.5, unit: "kg"),
                "say \"hi\"\n": IngredientAmount(amount: 0, unit: ""),
            ]
        )
        let request = BuildCartRequest(scoped: scoped, haveAlready: ["salt"], isVegetarian: true)

        XCTAssertEqual(
            string(request.jsonData),
            #"{"scoped":{"categorized":{"Vegetables":[{"name":"onion","amount":2,"unit":"kg"}],"#
                + #""Dairy":[{"name":"paneer","amount":200,"unit":"g"}],"#
                + #""Grains & Pulses":[{"name":"rice","amount":1.5,"unit":"kg"}],"#
                + #""Other":[{"name":"say \"hi\"\n","amount":0,"unit":""}]},"#
                + #""ingredients":["onion","paneer","rice","say \"hi\"\n"],"#
                + #""weights":{"onion":{"amount":2,"unit":"kg"},"paneer":{"amount":200,"unit":"g"},"#
                + #""rice":{"amount":1.5,"unit":"kg"},"say \"hi\"\n":{"amount":0,"unit":""}}},"#
                + #""haveAlready":["salt"],"isVegetarian":true}"#
        )
    }

    /// Whatever order is written, it must still be JSON a parser accepts.
    func testCartRequestIsValidJSON() throws {
        let request = BuildCartRequest(
            scoped: ScopedShoppingList(
                categorized: [CategorySection(name: "Spices & Herbs", items: [Ingredient(name: "jeera\u{1}", amount: 0.1 + 0.2, unit: "g")])],
                ingredients: ["jeera\u{1}"],
                weights: [:]
            ),
            haveAlready: [],
            isVegetarian: false
        )
        let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.jsonData)) as? [String: Any]
        let scoped = object?["scoped"] as? [String: Any]
        let items = (scoped?["categorized"] as? [String: Any])?["Spices & Herbs"] as? [[String: Any]]
        XCTAssertEqual(items?.first?["name"] as? String, "jeera\u{1}")
        XCTAssertEqual(items?.first?["amount"] as? Double, 0.1 + 0.2)
        XCTAssertEqual(object?["isVegetarian"] as? Bool, false)
    }

    func testBuildCartEndpointSendsTheOrderedBodyOnTheAIBudget() {
        let request = BuildCartRequest(scoped: ScopedShoppingList(), haveAlready: [], isVegetarian: false)
        let endpoint = Endpoints.buildCart(request)
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.path, "api/groceries/cart")
        XCTAssertEqual(endpoint.profile, .ai)
        XCTAssertTrue(endpoint.requiresAuth)
        XCTAssertEqual(
            string(endpoint.body),
            #"{"scoped":{"categorized":{},"ingredients":[],"weights":{}},"haveAlready":[],"isVegetarian":false}"#
        )
    }

    // MARK: - Rebuild and checkout requests

    func testRebuildRequestSendsTheLinesBackAsReceived() throws {
        let line = CartPlanLine(
            ingredient: "onion", display: "Onion", spinId: "S1", skuId: "K1",
            packDescription: "1 kg", packLabel: "Fresho Onion", quantity: 2, unitPrice: 40,
            imageUrl: "https://img/x.png", confidence: "high", notes: ["n"]
        )
        let endpoint = Endpoints.rebuildCart(RebuildCartRequest(lines: [line], misses: ["Saffron"]))
        XCTAssertEqual(endpoint.path, "api/groceries/cart/rebuild")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.profile, .ai)

        let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(endpoint.body)) as? [String: Any]
        XCTAssertEqual(object?["misses"] as? [String], ["Saffron"])
        let sent = try XCTUnwrap((object?["lines"] as? [[String: Any]])?.first)
        let roundTripped = try JSONDecoder().decode(
            CartPlanLine.self, from: JSONSerialization.data(withJSONObject: sent)
        )
        XCTAssertEqual(roundTripped, line)
    }

    func testCheckoutRequestCarriesTheConfirmedTotalAndTheOrderedItems() throws {
        let request = CheckoutRequest(
            expectedTotal: 412.5,
            weekStartDate: "2026-10-05",
            items: [OrderedItem(name: "onion", display: "Onion")]
        )
        let endpoint = Endpoints.checkout(request)
        XCTAssertEqual(endpoint.path, "api/groceries/checkout")
        XCTAssertEqual(endpoint.method, .post)
        // Checkout must outlast the server, or a placed order reads as a timeout.
        XCTAssertEqual(endpoint.profile, .ai)

        let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(endpoint.body)) as? [String: Any]
        XCTAssertEqual(object?["expectedTotal"] as? Double, 412.5)
        XCTAssertEqual(object?["weekStartDate"] as? String, "2026-10-05")
        XCTAssertEqual(object?["items"] as? [[String: String]], [["name": "onion", "display": "Onion"]])
    }

    // MARK: - Checkout response

    func testARecordedCheckoutDecodesWithItsStoredOrder() throws {
        let response = try decode(CheckoutResponse.self, """
            {"orderId":"ORD1","total":"₹412","recorded":true,
             "order":{"orderId":"ORD1","placedAt":"2026-10-08T10:00:00.000Z","total":"₹412",
                      "status":"live","statusLabel":"","etaAt":null,"checkedAt":"2026-10-08T10:00:00.000Z",
                      "items":[{"name":"onion","display":"Onion"}]}}
            """)
        XCTAssertEqual(response.orderId, "ORD1")
        XCTAssertEqual(response.total, "₹412")
        XCTAssertTrue(response.recorded)
        XCTAssertEqual(response.order?.items, [OrderedItem(name: "onion", display: "Onion")])
        XCTAssertEqual(response.order?.orderStatus, .live)
    }

    func testAnUnrecordedCheckoutIsStillAPlacedOrder() throws {
        let response = try decode(CheckoutResponse.self, #"{"orderId":"ORD2","total":"₹99","recorded":false}"#)
        XCTAssertEqual(response.orderId, "ORD2")
        XCTAssertFalse(response.recorded)
        XCTAssertNil(response.order)
    }

    /// A malformed `order` must not turn a placed order into an apparent failure.
    func testAMalformedOrderRecordStillDecodesThePlacedOrder() throws {
        let response = try decode(CheckoutResponse.self, #"{"orderId":"ORD3","order":{"items":7},"recorded":true}"#)
        XCTAssertEqual(response.orderId, "ORD3")
        XCTAssertNil(response.order)
    }

    /// Without an id there is nothing to show or record: that 2xx is
    /// unreadable, which the repository reports as unconfirmed.
    func testACheckoutWithoutAnOrderIdDoesNotDecode() {
        XCTAssertThrowsError(try decode(CheckoutResponse.self, #"{"total":"₹99"}"#))
        XCTAssertThrowsError(try decode(CheckoutResponse.self, #"{"orderId":""}"#))
    }

    // MARK: - Shopping-list PATCH

    /// The server treats a present field as an update and 400s on neither, so
    /// an absent one must vanish rather than go out as `null`.
    func testAShoppingListPatchSendsOnlyTheFieldsItWasGiven() throws {
        XCTAssertEqual(
            string(Endpoints.updateShoppingList("2026-10-05", UpdateShoppingListRequest(haveAlready: ["salt"])).body),
            #"{"haveAlready":["salt"]}"#
        )
        XCTAssertEqual(
            string(Endpoints.updateShoppingList("2026-10-05", UpdateShoppingListRequest(haveAlready: [])).body),
            #"{"haveAlready":[]}"#
        )

        let ordersOnly = Endpoints.updateShoppingList(
            "2026-10-05", UpdateShoppingListRequest(orders: [StoredOrder(orderId: "ORD1")])
        )
        XCTAssertEqual(ordersOnly.method, .patch)
        XCTAssertEqual(ordersOnly.path, "api/shopping-list/2026-10-05")
        let object = try JSONSerialization.jsonObject(with: try XCTUnwrap(ordersOnly.body)) as? [String: Any]
        XCTAssertNil(object?["haveAlready"])
        let order = try XCTUnwrap((object?["orders"] as? [[String: Any]])?.first)
        XCTAssertEqual(order["orderId"] as? String, "ORD1")
        XCTAssertEqual(order["status"] as? String, "live")
        XCTAssertNil(order["etaAt"], "a missing ETA is left off, never sent as null")

        let both = try JSONSerialization.jsonObject(with: try XCTUnwrap(
            Endpoints.updateShoppingList(
                "2026-10-05", UpdateShoppingListRequest(haveAlready: ["salt"], orders: [])
            ).body
        )) as? [String: Any]
        XCTAssertEqual(both?["haveAlready"] as? [String], ["salt"])
        XCTAssertEqual((both?["orders"] as? [Any])?.count, 0)
    }

    /// The existing haveAlready write must not change by a byte.
    func testTheExistingHaveAlreadyPatchIsUnchanged() {
        let endpoint = Endpoints.updateHaveAlready("2026-10-05", UpdateHaveAlreadyRequest(haveAlready: ["salt"]))
        XCTAssertEqual(endpoint.path, "api/shopping-list/2026-10-05")
        XCTAssertEqual(endpoint.method, .patch)
        XCTAssertEqual(string(endpoint.body), #"{"haveAlready":["salt"]}"#)
    }

    func testThePatchResponseCarriesTheSanitizedOrders() throws {
        let response = try decode(
            UpdateHaveAlreadyResponse.self,
            #"{"success":true,"haveAlready":[],"orders":[{"orderId":"A","status":"delivered"}]}"#
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.orders?.first?.orderStatus, .delivered)
        XCTAssertNil(try decode(UpdateHaveAlreadyResponse.self, #"{"success":true,"orders":null}"#).orders)
    }

    // MARK: - Status, connect, geo

    func testStatusDecodesAMissingTokenAsDisconnectedWithNoExpiry() throws {
        let response = try decode(GroceriesStatusResponse.self, #"{"connected":false,"expiresAt":null}"#)
        XCTAssertFalse(response.connected)
        XCTAssertNil(response.expiresAt)
        XCTAssertEqual(
            try decode(GroceriesStatusResponse.self, #"{"connected":true,"expiresAt":1780000000000}"#).expiresAt,
            1_780_000_000_000
        )
    }

    func testConnectAndGeoDecode() throws {
        XCTAssertEqual(
            try decode(ConnectResponse.self, #"{"authorizeUrl":"https://swiggy/x"}"#).authorizeUrl,
            "https://swiggy/x"
        )
        XCTAssertEqual(try decode(GeoResponse.self, #"{"country":"IN"}"#).country, "IN")
        XCTAssertNil(try decode(GeoResponse.self, #"{"country":null}"#).country)
        XCTAssertNil(try decode(GeoResponse.self, "{}").country)
    }

    func testTheReadOnlyEndpointsUseTheStandardBudget() {
        let status = Endpoints.groceriesStatus
        XCTAssertEqual(status.method, .get)
        XCTAssertEqual(status.path, "api/groceries/status")
        XCTAssertEqual(status.profile, .standard)
        XCTAssertTrue(status.requiresAuth)

        let connect = Endpoints.groceriesConnect()
        XCTAssertEqual(connect.method, .get)
        XCTAssertEqual(connect.path, "api/groceries/connect")
        XCTAssertEqual(connect.query, [URLQueryItem(name: "client", value: "ios")])
        XCTAssertEqual(connect.profile, .standard)

        let disconnect = Endpoints.groceriesDisconnect
        XCTAssertEqual(disconnect.method, .delete)
        XCTAssertEqual(disconnect.path, "api/groceries/connect")

        // Raw, not pre-encoded: APIClient's appendingPathComponent encodes the
        // path itself, and would turn a pre-encoded "%20" into "%2520".
        let order = Endpoints.orderStatus("1234567890")
        XCTAssertEqual(order.method, .get)
        XCTAssertEqual(order.path, "api/groceries/order/1234567890")
        XCTAssertEqual(order.profile, .standard)

        let geo = Endpoints.geo
        XCTAssertEqual(geo.method, .get)
        XCTAssertEqual(geo.path, "api/geo")
        XCTAssertFalse(geo.requiresAuth)
    }

    // MARK: - JSONValue

    func testJSONValueKeepsTypesApart() throws {
        let value = try decode(JSONValue.self, #"{"t":true,"one":1,"s":"true","n":null,"a":[1,"x"],"o":{"k":false}}"#)
        XCTAssertEqual(value["t"], .bool(true))
        XCTAssertEqual(value["one"], .number(1))
        XCTAssertEqual(value["s"], .string("true"))
        XCTAssertEqual(value["n"], .null)
        XCTAssertNil(value["missing"])
        XCTAssertEqual(value["a"], .array([.number(1), .string("x")]))
        XCTAssertEqual(value["o"]?["k"], .bool(false))
    }

    func testJSONValueSerializesObjectsInInsertionOrder() {
        let value = JSONValue.object([
            ("z", .number(1)), ("a", .array([.bool(true), .null])), ("m", .string("é/\u{8}\t")),
        ])
        XCTAssertEqual(string(value.jsonData), #"{"z":1,"a":[true,null],"m":"é/\b\t"}"#)
    }
}
