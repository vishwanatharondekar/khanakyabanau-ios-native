import Foundation
import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// A reply held back until the test opens it, so a test can look at the
/// in-between state (building, placing) and then decide what lands.
@MainActor
final class Gate<Value> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, any Error>?

    func wait() async throws -> Value {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func open(_ result: Result<Value, any Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            self.result = result
        }
    }
}

/// Each call answers from its property; calls are recorded for assertions,
/// before answering, so a call still suspended is already visible.
@MainActor
final class FakeInstamartGateway: InstamartGateway {
    var countryResult: Result<String?, any Error> = .success("IN")
    var statusResult: Result<InstamartAvailability, any Error> = .success(.connected)
    var connectResult: Result<URL, any Error> = .success(URL(string: "https://swiggy.example/consent")!)
    var build: () async throws -> CartBuild = { InstamartFixtures.firstBuild }
    var rebuild: () async throws -> CartBuild = { InstamartFixtures.firstBuild }
    var checkoutReply: () async throws -> CheckoutResponse = { CheckoutResponse(orderId: "o1") }
    var statusReplies: [String: Result<JSONValue, any Error>] = [:]
    var updateOrdersResult: Result<Void, any Error> = .success(())

    private(set) var countryCalls = 0
    private(set) var statusCalls = 0
    private(set) var buildRequests: [[String]] = []
    private(set) var rebuildRequests: [(lines: [CartPlanLine], misses: [String])] = []
    private(set) var checkoutRequests: [(total: Double, week: String, items: [OrderedItem])] = []
    private(set) var orderStatusCalls: [String] = []
    private(set) var updateOrdersCalls: [(week: String, orders: [StoredOrder], haveAlready: [String]?)] = []

    func country() async throws -> String? {
        countryCalls += 1
        return try countryResult.get()
    }

    func status() async throws -> InstamartAvailability {
        statusCalls += 1
        return try statusResult.get()
    }

    func connectURL() async throws -> URL { try connectResult.get() }

    func disconnect() async throws {}

    func buildCart(scoped: ScopedShoppingList, haveAlready: [String], isVegetarian: Bool) async throws -> CartBuild {
        buildRequests.append(haveAlready)
        return try await build()
    }

    func rebuildCart(lines: [CartPlanLine], misses: [String]) async throws -> CartBuild {
        rebuildRequests.append((lines, misses))
        return try await rebuild()
    }

    func checkout(expectedTotal: Double, weekStartDate: String, items: [OrderedItem]) async throws -> CheckoutResponse {
        checkoutRequests.append((expectedTotal, weekStartDate, items))
        return try await checkoutReply()
    }

    func orderStatus(orderId: String) async throws -> JSONValue {
        orderStatusCalls.append(orderId)
        guard let reply = statusReplies[orderId] else { throw URLError(.notConnectedToInternet) }
        return try reply.get()
    }

    func updateOrders(weekStartDate: String, orders: [StoredOrder], haveAlready: [String]?) async throws {
        updateOrdersCalls.append((weekStartDate, orders, haveAlready))
        try updateOrdersResult.get()
    }
}

enum InstamartFixtures {
    /// Fixed "now": 2025-10-09T08:53:20Z.
    static let nowMillis: Int64 = 1_760_000_000_000
    static let now = Date(timeIntervalSince1970: TimeInterval(nowMillis) / 1000)
    static let week = "2026-10-05"

    static func line(_ spin: String, _ ingredient: String) -> CartPlanLine {
        CartPlanLine(ingredient: ingredient, display: ingredient.capitalized, spinId: spin)
    }

    static func priced(_ line: CartPlanLine, inCart: Bool) -> PricedCartLine {
        PricedCartLine(
            ingredient: line.ingredient,
            display: line.display,
            spinId: line.spinId,
            inCart: inCart,
            chargedPrice: inCart ? 40 : nil
        )
    }

    static let onion = line("s1", "onion")
    static let tomato = line("s2", "tomato")

    /// Onion in the cart, tomato planned but left out by Swiggy, saffron unmatched.
    static let firstBuild = CartBuild(
        plan: CartPlan(lines: [onion, tomato], misses: ["Saffron"]),
        cart: InstamartCart(billBreakdown: BillBreakdown(toPay: BillRow(label: "To pay", value: "₹120.00"))),
        priced: [priced(onion, inCart: true), priced(tomato, inCart: false)]
    )

    static let request = OrderRequest(
        scoped: ScopedShoppingList(ingredients: ["onion", "tomato", "saffron"]),
        haveAlready: ["salt", "rice"],
        isVegetarian: true,
        weekStartDate: week
    )

    static let flaggedUser = User(id: "u1", name: "Asha", features: UserFeatures(swiggyInstamart: true))

    /// A stored order whose last check was `checkedAgo` ms before `nowMillis`.
    static func order(
        _ id: String,
        checkedAgo: Int64,
        _ names: [String] = [],
        status: String = "live"
    ) -> StoredOrder {
        StoredOrder(
            orderId: id,
            status: status,
            checkedAt: InstamartOrders.toISOString(epochMillis: nowMillis - checkedAgo),
            items: names.map { OrderedItem(name: $0, display: $0) }
        )
    }
}

/// Lets the main actor run until `condition` holds — for the in-between
/// states of a flow the test has started but not awaited.
@MainActor
func waitUntil(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTAssertTrue(condition(), "waitUntil timed out", file: file, line: line)
}
