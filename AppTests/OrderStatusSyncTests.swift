import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// The pure halves of the status sync (Android's `OrderStatusSyncTest`), then
/// the list model that drives it: one sequential read per due order, delivered
/// items folded into haveAlready, one PATCH for both.
@MainActor
final class OrderStatusSyncTests: XCTestCase {
    private typealias F = InstamartFixtures

    private let delivered = JSONValue.object([("delivered", .bool(true)), ("statusText", .string("Delivered"))])

    // MARK: - OrderStatusSync

    func testOnlyLiveOrdersCheckedAMinuteAgoOrMoreAreDue() {
        let fresh = F.order("a", checkedAgo: 10_000)
        let stale = F.order("b", checkedAgo: 61_000)
        let done = F.order("c", checkedAgo: 600_000, status: "delivered")
        XCTAssertEqual(OrderStatusSync.due([fresh, stale, done], nowMillis: F.nowMillis), [stale])
    }

    func testFetchIsSequentialAndSkipsFailuresAndUnreadablePayloads() async {
        var asked: [String] = []
        let replies: [String: JSONValue?] = [
            "a": .object([("delivered", .bool(true))]),
            "b": nil,
            "c": .string("??"),
        ]
        let updates = await OrderStatusSync.fetch(
            [F.order("a", checkedAgo: 70_000), F.order("b", checkedAgo: 70_000), F.order("c", checkedAgo: 70_000)],
            nowMillis: { F.nowMillis }
        ) { id in
            asked.append(id)
            guard let reply = replies[id] ?? nil else { throw URLError(.timedOut) }
            return reply
        }

        XCTAssertEqual(asked, ["a", "b", "c"])
        XCTAssertEqual(Set(updates.keys), ["a"])
        XCTAssertEqual(updates["a"]?.checkedAt, InstamartOrders.toISOString(epochMillis: F.nowMillis))
    }

    func testApplyFoldsDeliveredItemsIntoHaveAlreadyAgainstTheCurrentList() async {
        let deliveredOrder = F.order("a", checkedAgo: 70_000, ["onion", "tomato"])
        let updates = await OrderStatusSync.fetch([deliveredOrder], nowMillis: { F.nowMillis }) { _ in
            self.delivered
        }
        // A second order placed while the read was in flight survives.
        let placedMeanwhile = F.order("b", checkedAgo: 0, ["rice"])

        let result = OrderStatusSync.apply(
            orders: [placedMeanwhile, deliveredOrder], haveAlready: ["salt"], updates: updates
        )

        XCTAssertEqual(result?.orders.map(\.orderId), ["b", "a"])
        XCTAssertEqual(result?.orders[1].status, "delivered")
        XCTAssertEqual(result?.orders[1].statusLabel, "Delivered")
        XCTAssertEqual(result?.haveAlready, ["salt", "onion", "tomato"])
        XCTAssertEqual(result?.haveChanged, true)
    }

    func testApplyOnAStillLiveOrderChangesOrdersButNotHaveAlready() async {
        let live = F.order("a", checkedAgo: 70_000, ["onion"])
        let updates = await OrderStatusSync.fetch([live], nowMillis: { F.nowMillis }) { _ in
            .object([("statusText", .string("Packing"))])
        }
        let result = OrderStatusSync.apply(orders: [live], haveAlready: [], updates: updates)
        XCTAssertEqual(result?.orders.first?.statusLabel, "Packing")
        XCTAssertEqual(result?.haveChanged, false)
    }

    func testApplyIsNilWhenNoUpdateMatchesAnOrderOnTheList() {
        XCTAssertNil(OrderStatusSync.apply(orders: [F.order("a", checkedAgo: 0)], haveAlready: [], updates: [:]))
    }

    // MARK: - ShoppingListViewModel

    private func makeList(orders: [StoredOrder]) -> ShoppingList {
        ShoppingList(
            categorized: [
                "Vegetables": [
                    Ingredient(name: "Onion", amount: 300, unit: "g"),
                    Ingredient(name: "Tomato", amount: 200, unit: "g"),
                    Ingredient(name: "Garlic", amount: 50, unit: "g"),
                ],
            ],
            haveAlready: ["garlic"],
            orders: orders
        )
    }

    private func makeModel(
        orders: [StoredOrder],
        gateway: any InstamartGateway,
        reload: (() async -> ShoppingList?)? = nil
    ) -> ShoppingListViewModel {
        ShoppingListViewModel(
            env: AppEnvironment(),
            list: makeList(orders: orders),
            weekStartDate: F.week,
            instamart: gateway,
            reloadList: reload,
            now: { F.now }
        )
    }

    func testOrdersSeedFromTheListAndCountAsOrderedNotToBuy() {
        let model = makeModel(orders: [F.order("a", checkedAgo: 0, ["onion", "garlic"])], gateway: FakeInstamartGateway())
        // Garlic is ticked by hand, and a hand tick beats an order.
        XCTAssertEqual(model.orderedNames, ["onion"])
        XCTAssertTrue(model.isOrdered("Onion"))
        XCTAssertFalse(model.isOrdered("Garlic"))
        XCTAssertEqual(model.toBuyCount, 1)
        XCTAssertEqual(model.orderedCount, 1)
        XCTAssertEqual(model.haveCount, 1)
        XCTAssertEqual(model.cartHaveAlready, ["garlic", "onion"])
        XCTAssertEqual(model.itemStates(["Onion", "Tomato"]).toBuy, ["Tomato"])
    }

    func testSyncMovesDeliveredItemsIntoHaveAndWritesBothInOnePatch() async {
        let gateway = FakeInstamartGateway()
        gateway.statusReplies = ["a": .success(delivered)]
        let model = makeModel(orders: [F.order("a", checkedAgo: 120_000, ["onion"])], gateway: gateway)
        var written: (Set<String>, [StoredOrder])?
        model.onStateChange = { written = ($0, $1) }

        await model.syncOrderStatuses()

        XCTAssertEqual(gateway.orderStatusCalls, ["a"])
        XCTAssertTrue(model.isHad("Onion"))
        XCTAssertEqual(model.orders.first?.orderStatus, .delivered)
        XCTAssertEqual(gateway.updateOrdersCalls.count, 1)
        XCTAssertEqual(gateway.updateOrdersCalls.first?.orders, model.orders)
        XCTAssertEqual(Set(gateway.updateOrdersCalls.first?.haveAlready ?? []), ["garlic", "onion"])
        XCTAssertEqual(written?.0, ["garlic", "onion"])

        // Delivered is terminal: nothing is due, nothing is asked or written.
        await model.syncOrderStatuses()
        XCTAssertEqual(gateway.orderStatusCalls.count, 1)
        XCTAssertEqual(gateway.updateOrdersCalls.count, 1)
    }

    func testSyncOnAStillLiveOrderWritesOrdersOnly() async {
        let gateway = FakeInstamartGateway()
        gateway.statusReplies = ["a": .success(.object([("statusText", .string("Packing"))]))]
        let model = makeModel(orders: [F.order("a", checkedAgo: 120_000, ["onion"])], gateway: gateway)

        await model.syncOrderStatuses()

        XCTAssertEqual(model.orders.first?.statusLabel, "Packing")
        XCTAssertEqual(gateway.updateOrdersCalls.count, 1)
        XCTAssertNil(gateway.updateOrdersCalls.first?.haveAlready)
    }

    func testSyncSkipsFreshOrdersAndIsSilentOnFailure() async {
        let gateway = FakeInstamartGateway()
        let model = makeModel(
            orders: [F.order("fresh", checkedAgo: 5_000, ["onion"]), F.order("stale", checkedAgo: 90_000, ["tomato"])],
            gateway: gateway
        )

        await model.syncOrderStatuses()

        // Only the stale one is asked; its read fails, so nothing changes or is written.
        XCTAssertEqual(gateway.orderStatusCalls, ["stale"])
        XCTAssertTrue(gateway.updateOrdersCalls.isEmpty)
        XCTAssertEqual(model.orders.map(\.status), ["live", "live"])
    }

    func testSyncDoesNotOverlap() async {
        let gateway = FakeInstamartGateway()
        let gate = Gate<JSONValue>()
        // The read waits on the gate, holding the first sync open.
        let slow = SlowStatusGateway(base: gateway, gate: gate)
        let gated = makeModel(orders: [F.order("a", checkedAgo: 120_000, ["onion"])], gateway: slow)

        let first = Task { await gated.syncOrderStatuses() }
        await waitUntil { slow.calls == 1 }
        await gated.syncOrderStatuses()
        XCTAssertEqual(slow.calls, 1)

        gate.open(.success(delivered))
        await first.value
        XCTAssertEqual(gateway.updateOrdersCalls.count, 1)
    }

    func testUnrecordedOrderIsPrependedSavedAndReadOnceRightAway() async {
        let gateway = FakeInstamartGateway()
        let older = F.order("old", checkedAgo: 0, ["rice"])
        let model = makeModel(orders: [older], gateway: gateway)
        let fresh = F.order("new", checkedAgo: 0, ["tomato"])
        gateway.statusReplies = ["new": .success(.object([("statusText", .string("Packing"))]))]

        await model.onOrderPlaced(PlacedOrder(order: fresh, recorded: false, weekStartDate: F.week))

        XCTAssertEqual(model.orders.map(\.orderId), ["new", "old"])
        XCTAssertTrue(model.isOrdered("Tomato"))
        // Forced past the throttle: checked "just now", read anyway — only it.
        XCTAssertEqual(gateway.orderStatusCalls, ["new"])
        // The fire-and-forget save of the order, plus the sync's own write.
        await waitUntil { gateway.updateOrdersCalls.count == 2 }
        let save = gateway.updateOrdersCalls.first { $0.orders.map(\.orderId) == ["new", "old"] && $0.orders[0].statusLabel.isEmpty }
        XCTAssertNotNil(save)
        XCTAssertNil(save?.haveAlready)
    }

    func testRecordedOrderIsNotSavedAgain() async {
        let gateway = FakeInstamartGateway()
        let model = makeModel(orders: [], gateway: gateway)
        await model.onOrderPlaced(PlacedOrder(
            order: F.order("new", checkedAgo: 0, ["tomato"]), recorded: true, weekStartDate: F.week
        ))
        XCTAssertEqual(model.orders.map(\.orderId), ["new"])
        // The forced read fails (no reply configured), so there is nothing to write either.
        XCTAssertTrue(gateway.updateOrdersCalls.isEmpty)
    }

    func testAnOrderForAnotherWeekIsIgnored() async {
        let gateway = FakeInstamartGateway()
        let model = makeModel(orders: [], gateway: gateway)
        await model.onOrderPlaced(PlacedOrder(
            order: F.order("x", checkedAgo: 0), recorded: false, weekStartDate: "2026-10-12"
        ))
        XCTAssertTrue(model.orders.isEmpty)
        XCTAssertTrue(gateway.updateOrdersCalls.isEmpty)
    }

    func testReloadTakesOnlyTheOrdersAndKeepsLocalTicksAndScope() async {
        let gateway = FakeInstamartGateway()
        let serverOrder = F.order("srv", checkedAgo: 0, ["tomato"])
        var reloaded = makeList(orders: [serverOrder])
        reloaded.haveAlready = []
        let model = makeModel(orders: [], gateway: gateway, reload: { reloaded })
        model.selectedDays = [.monday]

        await model.reloadShopping()

        XCTAssertEqual(model.orders, [serverOrder])
        XCTAssertTrue(model.isHad("Garlic"), "local ticks survive the reload")
        XCTAssertEqual(model.selectedDays, [.monday])
    }
}

/// Wraps the fake so the status read waits on a gate, to hold a sync open.
@MainActor
private final class SlowStatusGateway: InstamartGateway {
    let base: FakeInstamartGateway
    let gate: Gate<JSONValue>
    private(set) var calls = 0

    init(base: FakeInstamartGateway, gate: Gate<JSONValue>) {
        self.base = base
        self.gate = gate
    }

    func country() async throws -> String? { try await base.country() }
    func status() async throws -> InstamartAvailability { try await base.status() }
    func connectURL() async throws -> URL { try await base.connectURL() }
    func disconnect() async throws {}
    func buildCart(scoped: ScopedShoppingList, haveAlready: [String], isVegetarian: Bool) async throws -> CartBuild {
        try await base.buildCart(scoped: scoped, haveAlready: haveAlready, isVegetarian: isVegetarian)
    }
    func rebuildCart(lines: [CartPlanLine], misses: [String]) async throws -> CartBuild {
        try await base.rebuildCart(lines: lines, misses: misses)
    }
    func checkout(expectedTotal: Double, weekStartDate: String, items: [OrderedItem]) async throws -> CheckoutResponse {
        try await base.checkout(expectedTotal: expectedTotal, weekStartDate: weekStartDate, items: items)
    }
    func orderStatus(orderId: String) async throws -> JSONValue {
        calls += 1
        return try await gate.wait()
    }
    func updateOrders(weekStartDate: String, orders: [StoredOrder], haveAlready: [String]?) async throws {
        try await base.updateOrders(weekStartDate: weekStartDate, orders: orders, haveAlready: haveAlready)
    }
}
