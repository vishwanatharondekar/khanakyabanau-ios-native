import XCTest
@testable import KhanaKit

/// Port-parity tests for `InstamartOrders`. Every case mirrors the webapp's
/// `lib/swiggy/orders.test.ts` by way of Android's `InstamartOrdersTest.kt`;
/// when in doubt, `lib/swiggy/orders.ts` is the specification.
final class InstamartOrdersTests: XCTestCase {

    private func order(
        orderId: String = "ORD-1",
        status: String = "live",
        statusLabel: String = "Out for delivery",
        checkedAt: String = "2026-08-29T10:00:00.000Z",
        items: [OrderedItem] = [
            OrderedItem(name: "tomatoes", display: "Tomatoes"),
            OrderedItem(name: "onions", display: "Onions"),
        ]
    ) -> StoredOrder {
        StoredOrder(
            orderId: orderId,
            placedAt: "2026-08-29T10:00:00.000Z",
            total: "₹482.00",
            status: status,
            statusLabel: statusLabel,
            checkedAt: checkedAt,
            items: items
        )
    }

    private func millis(_ iso: String) -> Int64 { InstamartOrders.parseISOMillis(iso)! }

    /// A status payload as the order route relays it, decoded the way the App
    /// layer will decode it — through `JSONValue`.
    private func status(_ json: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: - deriveItemStates

    func testMovesLiveOrderItemsOutOfToBuy() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["Tomatoes", "Onions", "Paneer"], haveAlready: [], orders: [order()]
        )
        XCTAssertEqual(result.ordered, ["onions", "tomatoes"])
        XCTAssertEqual(result.toBuy, ["Paneer"])
    }

    /// The user ticking "have" is a stronger statement than our tracking guess.
    func testLetsHaveAlreadyWinOverALiveOrder() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["Tomatoes", "Onions"], haveAlready: ["tomatoes"], orders: [order()]
        )
        XCTAssertEqual(result.ordered, ["onions"])
        XCTAssertEqual(result.toBuy, [])
    }

    func testIgnoresDeliveredOrders() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["Tomatoes"], haveAlready: [], orders: [order(status: "delivered")]
        )
        XCTAssertTrue(result.ordered.isEmpty)
        XCTAssertEqual(result.toBuy, ["Tomatoes"])
    }

    /// Two orders in one week is the designed-for case, not the edge case.
    func testUnionsItemsAcrossSeveralLiveOrders() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["Tomatoes", "Paneer"],
            haveAlready: [],
            orders: [
                order(orderId: "A", items: [OrderedItem(name: "tomatoes", display: "Tomatoes")]),
                order(orderId: "B", items: [OrderedItem(name: "paneer", display: "Paneer")]),
            ]
        )
        XCTAssertEqual(result.ordered, ["paneer", "tomatoes"])
        XCTAssertEqual(result.toBuy, [])
    }

    func testToBuyMatchesOnTheNormalizedName() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["  TOMATOES ", "Paneer"], haveAlready: [], orders: [order()]
        )
        XCTAssertEqual(result.toBuy, ["Paneer"])
    }

    // MARK: - mergeDeliveredIntoHave

    func testAddsDeliveredItemsToHaveAlready() {
        let result = InstamartOrders.mergeDeliveredIntoHave(
            orders: [order(status: "delivered")], haveAlready: []
        )
        XCTAssertEqual(result.haveAlready, ["onions", "tomatoes"])
        XCTAssertTrue(result.changed)
    }

    func testLeavesLiveOrdersAlone() {
        let result = InstamartOrders.mergeDeliveredIntoHave(orders: [order()], haveAlready: [])
        XCTAssertTrue(result.haveAlready.isEmpty)
        XCTAssertFalse(result.changed)
    }

    /// Without this the pane writes to the server on every open, forever.
    func testReportsNoChangeWhenTheMergeIsAlreadyDone() {
        let result = InstamartOrders.mergeDeliveredIntoHave(
            orders: [order(status: "delivered")], haveAlready: ["tomatoes", "onions"]
        )
        XCTAssertFalse(result.changed)
    }

    // Value semantics make "does not mutate the set it was given" hold by
    // construction; the webapp and Android need a test for it, Swift does not.

    // MARK: - shouldRefresh

    private var refreshNow: Int64 { millis("2026-08-29T10:05:00.000Z") }

    func testRefreshesALiveOrderCheckedLongerAgoThanTheThrottle() {
        XCTAssertTrue(InstamartOrders.shouldRefresh(
            order(checkedAt: "2026-08-29T10:00:00.000Z"), nowMillis: refreshNow
        ))
    }

    func testSkipsALiveOrderCheckedWithinTheThrottle() {
        XCTAssertFalse(InstamartOrders.shouldRefresh(
            order(checkedAt: "2026-08-29T10:04:30.000Z"), nowMillis: refreshNow
        ))
    }

    func testNeverRefreshesADeliveredOrder() {
        XCTAssertFalse(InstamartOrders.shouldRefresh(
            order(status: "delivered", checkedAt: "2026-01-01T00:00:00.000Z"), nowMillis: refreshNow
        ))
    }

    func testRefreshesWhenCheckedAtIsUnreadable() {
        XCTAssertTrue(InstamartOrders.shouldRefresh(order(checkedAt: "not-a-date"), nowMillis: refreshNow))
        XCTAssertTrue(InstamartOrders.shouldRefresh(order(checkedAt: ""), nowMillis: refreshNow))
    }

    /// The re-run a status sync triggers must find nothing due, or it loops:
    /// every order the sync touched carries a checkedAt of "now".
    func testIsFalseForAnOrderJustSyncedSoADependentRefreshCannotLoop() {
        let justSynced = order(checkedAt: InstamartOrders.toISOString(epochMillis: refreshNow))
        XCTAssertFalse(InstamartOrders.shouldRefresh(justSynced, nowMillis: refreshNow))
    }

    func testExportsASixtySecondThrottle() {
        XCTAssertEqual(InstamartOrders.refreshThrottleMillis, 60_000)
    }

    // MARK: - readOrderStatus

    /// get_delivery_status reports terminal states as booleans, not as an enum.
    func testReadsTheDeliveredFlag() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(
                status(#"{"orderId":"O","delivered":true,"statusText":"Delivered"}"#),
                nowMillis: refreshNow
            ),
            StatusRead(status: .delivered, statusLabel: "Delivered", etaAt: nil)
        )
    }

    func testReadsTheCancelledFlag() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(
                status(#"{"orderId":"O","cancelled":true,"statusText":"Cancelled"}"#),
                nowMillis: refreshNow
            ),
            StatusRead(status: .cancelled, statusLabel: "Cancelled", etaAt: nil)
        )
    }

    /// Both flags are optional and absent while the order is on its way.
    func testTreatsAnInProgressResponseAsLive() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(
                status(#"{"orderId":"O","etaText":"12 mins","serverNow":1}"#),
                nowMillis: refreshNow
            ),
            StatusRead(status: .live, statusLabel: "12 mins", etaAt: nil)
        )
    }

    func testPrefersStatusTextOverEtaTextForTheLabel() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"orderId":"O","statusText":"Out for delivery","etaText":"5 mins"}"#),
            nowMillis: refreshNow
        )
        XCTAssertEqual(read?.statusLabel, "Out for delivery")
    }

    func testFallsBackToEtaTextWhenStatusTextIsBlank() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"statusText":"  ","etaText":"5 mins"}"#), nowMillis: refreshNow
        )
        XCTAssertEqual(read?.statusLabel, "5 mins")
    }

    func testIsLiveWithAnEmptyLabelWhenNeitherTextFieldIsPresent() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(
                status(#"{"orderId":"O","deliveryBy":123}"#), nowMillis: refreshNow
            ),
            StatusRead(status: .live, statusLabel: "", etaAt: nil)
        )
    }

    /// An unrecognised payload must leave the stored status untouched rather than
    /// silently reporting "live" for an order that may have arrived.
    func testReturnsNilWhenNothingIsRecognisable() {
        XCTAssertNil(InstamartOrders.readOrderStatus(status(#"{"somethingElse":1}"#), nowMillis: refreshNow))
        XCTAssertNil(InstamartOrders.readOrderStatus(nil, nowMillis: refreshNow))
        XCTAssertNil(InstamartOrders.readOrderStatus(status("null"), nowMillis: refreshNow))
        XCTAssertNil(InstamartOrders.readOrderStatus(status(#""nope""#), nowMillis: refreshNow))
        XCTAssertNil(InstamartOrders.readOrderStatus(status(#"[{"delivered":true}]"#), nowMillis: refreshNow))
    }

    /// The webapp's `!== undefined` counts an explicit null as present.
    func testAnExplicitNullStillMarksAKnownField() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(status(#"{"delivered":null}"#), nowMillis: refreshNow),
            StatusRead(status: .live, statusLabel: "", etaAt: nil)
        )
    }

    /// Delivered wins: an order cannot be both, and arriving is the safer read of
    /// a contradiction than being written off.
    func testPrefersDeliveredWhenBothFlagsAreSet() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"delivered":true,"cancelled":true}"#), nowMillis: refreshNow
        )
        XCTAssertEqual(read?.status, .delivered)
    }

    /// Only a real JSON `true` counts — the string "true" and the number 1 are
    /// not Swiggy's flag, as with the webapp's `=== true`.
    func testOnlyAJSONTrueIsADeliveredFlag() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(status(#"{"delivered":"true"}"#), nowMillis: refreshNow)?.status,
            .live
        )
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(status(#"{"delivered":1}"#), nowMillis: refreshNow)?.status,
            .live
        )
    }

    // MARK: - Cancelled orders

    /// The groceries never came, so the ingredients go back on the list.
    func testPutsACancelledOrdersItemsBackIntoToBuy() {
        let result = InstamartOrders.deriveItemStates(
            ingredients: ["Tomatoes", "Onions"], haveAlready: [], orders: [order(status: "cancelled")]
        )
        XCTAssertTrue(result.ordered.isEmpty)
        XCTAssertEqual(result.toBuy, ["Tomatoes", "Onions"])
    }

    func testNeverMergesACancelledOrderIntoHaveAlready() {
        let result = InstamartOrders.mergeDeliveredIntoHave(
            orders: [order(status: "cancelled")], haveAlready: []
        )
        XCTAssertTrue(result.haveAlready.isEmpty)
        XCTAssertFalse(result.changed)
    }

    func testNeverRefreshesACancelledOrderAgain() {
        XCTAssertFalse(InstamartOrders.shouldRefresh(
            order(status: "cancelled", checkedAt: "2026-01-01T00:00:00.000Z"),
            nowMillis: millis("2026-08-29T10:05:00.000Z")
        ))
    }

    // MARK: - readOrderStatus ETA

    private var etaNow: Int64 { millis("2026-09-05T10:00:00.000Z") }
    private let serverNow: Int64 = 1_780_000_000_000

    func testAnchorsTheETAToOurOwnClockNotTheServers() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":\#(serverNow),"deliveryBy":\#(serverNow + 15 * 60_000),"statusText":"On the way"}"#),
            nowMillis: etaNow
        )
        XCTAssertEqual(read?.etaAt, "2026-09-05T10:15:00.000Z")
    }

    /// The whole reason serverNow exists. Only the *duration* is trusted, so a
    /// server clock hours out of step still yields the right countdown.
    func testIsUnaffectedByASkewedServerClock() {
        let skewed = serverNow + 9 * 3_600_000
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":\#(skewed),"deliveryBy":\#(skewed + 12 * 60_000)}"#),
            nowMillis: etaNow
        )
        XCTAssertEqual(read?.etaAt, InstamartOrders.toISOString(epochMillis: etaNow + 12 * 60_000))
    }

    func testETAIsNilWhenEitherHalfIsMissing() {
        XCTAssertNil(InstamartOrders.readOrderStatus(
            status(#"{"deliveryBy":\#(serverNow + 60_000)}"#), nowMillis: etaNow
        )?.etaAt)
        XCTAssertNil(InstamartOrders.readOrderStatus(
            status(#"{"serverNow":\#(serverNow),"statusText":"On the way"}"#), nowMillis: etaNow
        )?.etaAt)
    }

    func testETAIsNilWhenItHasAlreadyPassedAtFetchTime() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":\#(serverNow),"deliveryBy":\#(serverNow - 60_000)}"#), nowMillis: etaNow
        )
        XCTAssertNil(read?.etaAt)
    }

    /// Instamart is a ten-to-thirty-minute service. A seven-hour ETA is a bad
    /// value, and showing nothing beats showing a number we do not believe.
    func testETAIsNilWhenImplausiblyFarOut() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":\#(serverNow),"deliveryBy":\#(serverNow + 7 * 3_600_000)}"#),
            nowMillis: etaNow
        )
        XCTAssertNil(read?.etaAt)
    }

    /// `Number()` in the webapp reads a numeric string; so does the port.
    func testReadsEpochMillisSentAsStrings() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":"\#(serverNow)","deliveryBy":" \#(serverNow + 60_000) "}"#),
            nowMillis: etaNow
        )
        XCTAssertEqual(read?.etaAt, InstamartOrders.toISOString(epochMillis: etaNow + 60_000))
    }

    func testABooleanIsNotANumber() {
        let read = InstamartOrders.readOrderStatus(
            status(#"{"serverNow":true,"deliveryBy":\#(serverNow)}"#), nowMillis: etaNow
        )
        XCTAssertNil(read?.etaAt)
    }

    func testStillReadsStatusAndLabelWhenThereIsNoETA() {
        XCTAssertEqual(
            InstamartOrders.readOrderStatus(status(#"{"statusText":"Packing your order"}"#), nowMillis: etaNow),
            StatusRead(status: .live, statusLabel: "Packing your order", etaAt: nil)
        )
    }

    // MARK: - formatCountdown

    private func inMinutes(_ m: Int64) -> String {
        InstamartOrders.toISOString(epochMillis: etaNow + m * 60_000)
    }

    func testCountsWholeMinutes() {
        XCTAssertEqual(InstamartOrders.formatCountdown(etaAt: inMinutes(12), nowMillis: etaNow), "Arriving in 12 min")
    }

    func testNeverSaysZeroMinutes() {
        XCTAssertEqual(
            InstamartOrders.formatCountdown(
                etaAt: InstamartOrders.toISOString(epochMillis: etaNow + 30_000), nowMillis: etaNow
            ),
            "Arriving in under a minute"
        )
    }

    /// A countdown that reaches "-4 min" reads as broken, which is why it stops.
    func testSwitchesToAPhraseOnceTheETAPasses() {
        XCTAssertEqual(InstamartOrders.formatCountdown(etaAt: inMinutes(-4), nowMillis: etaNow), "Arriving any moment")
        XCTAssertEqual(InstamartOrders.formatCountdown(etaAt: inMinutes(0), nowMillis: etaNow), "Arriving any moment")
    }

    func testCountdownIsNilWithoutAnETA() {
        XCTAssertNil(InstamartOrders.formatCountdown(etaAt: nil, nowMillis: etaNow))
        XCTAssertNil(InstamartOrders.formatCountdown(etaAt: "", nowMillis: etaNow))
    }

    func testCountdownIsNilWhenTheStoredValueIsUnreadable() {
        XCTAssertNil(InstamartOrders.formatCountdown(etaAt: "not-a-date", nowMillis: etaNow))
    }

    func testRoundsRatherThanTruncating() {
        XCTAssertEqual(
            InstamartOrders.formatCountdown(
                etaAt: InstamartOrders.toISOString(epochMillis: etaNow + 110_000), nowMillis: etaNow
            ),
            "Arriving in 2 min"
        )
    }

    /// An ISO string without milliseconds — what another writer might store — is
    /// still an instant.
    func testReadsAnETAWithoutMilliseconds() {
        XCTAssertEqual(
            InstamartOrders.formatCountdown(etaAt: "2026-09-05T10:05:00Z", nowMillis: etaNow),
            "Arriving in 5 min"
        )
    }

    // MARK: - prependOrder

    func testPutsTheNewOrderFirst() {
        let next = InstamartOrders.prependOrder([order(orderId: "OLD")], order(orderId: "NEW"))
        XCTAssertEqual(next.map(\.orderId), ["NEW", "OLD"])
    }

    func testStartsAListWhenThereWasNone() {
        XCTAssertEqual(InstamartOrders.prependOrder([], order()).map(\.orderId), ["ORD-1"])
    }

    /// A retried write must not record one purchase twice — the shopping list
    /// would still be right, but the receipt history would not.
    func testReplacesAnOrderAlreadyRecordedUnderTheSameId() {
        let existing = [order(orderId: "A", statusLabel: "old"), order(orderId: "B")]
        let next = InstamartOrders.prependOrder(existing, order(orderId: "A", statusLabel: "new"))
        XCTAssertEqual(next.map(\.orderId), ["A", "B"])
        XCTAssertEqual(next[0].statusLabel, "new")
    }

    /// The server rejects a longer list outright, which would make the week's
    /// orders unwritable. The oldest go.
    func testKeepsAtMostMaxStoredOrdersDroppingTheOldest() {
        let max = InstamartOrders.maxStoredOrders
        let existing = (0..<max).map { order(orderId: "O\($0)") }
        let next = InstamartOrders.prependOrder(existing, order(orderId: "NEW"))
        XCTAssertEqual(max, 20)
        XCTAssertEqual(next.count, max)
        XCTAssertEqual(next.first?.orderId, "NEW")
        XCTAssertEqual(next.last?.orderId, "O\(max - 2)")
    }

    // MARK: - withStatus / OrderStatus

    func testWithStatusAppliesAReadAndStampsCheckedAt() {
        let read = StatusRead(status: .delivered, statusLabel: "Delivered", etaAt: nil)
        let next = InstamartOrders.withStatus(order(), read: read, nowISO: "2026-08-29T10:30:00.000Z")
        XCTAssertEqual(next.status, "delivered")
        XCTAssertEqual(next.orderStatus, .delivered)
        XCTAssertEqual(next.statusLabel, "Delivered")
        XCTAssertNil(next.etaAt)
        XCTAssertEqual(next.checkedAt, "2026-08-29T10:30:00.000Z")
        XCTAssertEqual(next.items, order().items)
    }

    /// The ETA is replaced, not merged: a stale estimate is worse than none.
    func testWithStatusReplacesAStaleETA() {
        var stale = order()
        stale.etaAt = "2026-08-29T10:20:00.000Z"
        let next = InstamartOrders.withStatus(
            stale, read: StatusRead(status: .live, statusLabel: "x", etaAt: nil), nowISO: "2026-08-29T10:30:00.000Z"
        )
        XCTAssertNil(next.etaAt)
    }

    /// Same rule as the webapp's sanitizeOrders: anything unrecognised is live.
    func testAnUnknownWireStatusReadsAsLive() {
        XCTAssertEqual(order(status: "returned").orderStatus, .live)
        XCTAssertEqual(order(status: "cancelled").orderStatus, .cancelled)
        XCTAssertEqual(OrderStatus(wire: nil), .live)
    }

    // MARK: - ISO helpers

    func testToISOStringMatchesJavaScriptToISOString() {
        XCTAssertEqual(InstamartOrders.toISOString(epochMillis: etaNow), "2026-09-05T10:00:00.000Z")
        XCTAssertEqual(InstamartOrders.toISOString(epochMillis: etaNow + 250), "2026-09-05T10:00:00.250Z")
        XCTAssertEqual(InstamartOrders.toISOString(epochMillis: 0), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(InstamartOrders.toISOString(epochMillis: -1), "1969-12-31T23:59:59.999Z")
    }

    func testParseISOMillisReadsTheForms() {
        XCTAssertEqual(InstamartOrders.parseISOMillis("1970-01-01T00:00:01.500Z"), 1_500)
        XCTAssertEqual(InstamartOrders.parseISOMillis("1970-01-01T00:00:01Z"), 1_000)
        XCTAssertEqual(InstamartOrders.parseISOMillis(" 1970-01-01T05:30:01+05:30 "), 1_000)
        XCTAssertNil(InstamartOrders.parseISOMillis(nil))
        XCTAssertNil(InstamartOrders.parseISOMillis("   "))
        XCTAssertNil(InstamartOrders.parseISOMillis("2026-09-05"))
    }

    func testMillisFromADateRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_780_000_000.25)
        XCTAssertEqual(InstamartOrders.millis(date), 1_780_000_000_250)
    }
}
