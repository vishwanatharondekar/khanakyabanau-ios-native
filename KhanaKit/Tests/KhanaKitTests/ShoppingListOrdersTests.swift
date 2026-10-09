import XCTest
@testable import KhanaKit

/// `ShoppingList.orders`: Instamart orders ride on the existing
/// get-shopping-list response. Port of the order cases in Android's
/// `ShoppingListTest.kt`.
final class ShoppingListOrdersTests: XCTestCase {

    private func decode(_ json: String) throws -> ShoppingList {
        try JSONDecoder().decode(ShoppingList.self, from: Data(json.utf8))
    }

    func testOrdersDecodeFromTheServerResponse() throws {
        let list = try decode("""
            {"categorized":{},"dayWise":{},
             "orders":[{"orderId":"ORD-1","placedAt":"2026-08-29T10:00:00.000Z","total":"₹482.00",
                        "status":"delivered","statusLabel":"Delivered","etaAt":null,
                        "checkedAt":"2026-08-29T10:30:00.000Z",
                        "items":[{"name":"tomatoes","display":"Tomatoes"}]}]}
            """)
        let order = try XCTUnwrap(list.orders.first)
        XCTAssertEqual(list.orders.count, 1)
        XCTAssertEqual(order.orderId, "ORD-1")
        XCTAssertEqual(order.total, "₹482.00")
        XCTAssertEqual(order.orderStatus, .delivered)
        XCTAssertEqual(order.statusLabel, "Delivered")
        XCTAssertNil(order.etaAt)
        XCTAssertEqual(order.checkedAt, "2026-08-29T10:30:00.000Z")
        XCTAssertEqual(order.items, [OrderedItem(name: "tomatoes", display: "Tomatoes")])
    }

    func testAListSavedBeforeOrdersExistedDecodesWithNone() throws {
        XCTAssertEqual(try decode(#"{"categorized":{},"dayWise":{},"haveAlready":["onion"]}"#).orders, [])
        XCTAssertEqual(try decode(#"{"orders":null}"#).orders, [])
    }

    /// A status this build has never heard of must not fail the whole list.
    func testAnUnknownOrderStatusDecodesAndReadsAsLive() throws {
        XCTAssertEqual(try decode(#"{"orders":[{"orderId":"A","status":"returned"}]}"#).orders.first?.orderStatus, .live)
    }

    /// One unreadable record costs that record, not every order in the week —
    /// losing them all would put every ordered item back on the list.
    func testAnUnreadableOrderIsDroppedAlone() throws {
        let list = try decode(#"{"orders":[{"status":"live"},7,{"orderId":"B"}]}"#)
        XCTAssertEqual(list.orders.map(\.orderId), ["B"])
    }

    /// Orders round-trip through the shopping-list PATCH in the stored shape.
    func testAStoredOrderRoundTrips() throws {
        let order = StoredOrder(
            orderId: "A", placedAt: "p", total: "₹1", status: "cancelled", statusLabel: "x",
            etaAt: "2026-08-29T10:30:00.000Z", checkedAt: "c",
            items: [OrderedItem(name: "onion", display: "Onion")]
        )
        let back = try JSONDecoder().decode(StoredOrder.self, from: JSONEncoder().encode(order))
        XCTAssertEqual(back, order)
    }
}
