import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// The ordering state machine, against a fake gateway. Case for case with
/// Android's `InstamartViewModelTest`, plus the sign-in hand-off that is
/// iOS-only (`pendingSignInURL` / `signInFinished`).
@MainActor
final class InstamartViewModelTests: XCTestCase {
    private typealias F = InstamartFixtures

    private var gateway: FakeInstamartGateway!
    private var events: [AnalyticsEvent] = []
    private var placed: [PlacedOrder] = []
    private var reloads = 0

    override func setUp() async throws {
        gateway = FakeInstamartGateway()
        events = []
        placed = []
        reloads = 0
    }

    private func subject(listening: Bool = true) -> InstamartViewModel {
        let model = InstamartViewModel(
            gateway: gateway,
            track: { [unowned self] in events.append($0) },
            now: { F.now }
        )
        if listening {
            model.onOrderPlaced = { [unowned self] in placed.append($0) }
            model.onReloadShopping = { [unowned self] in reloads += 1 }
        }
        return model
    }

    /// Available + connected, then straight into a review of `firstBuild`.
    private func inReview() async -> InstamartViewModel {
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)
        guard case .review = model.phase else {
            XCTFail("Expected a review, got \(model.phase)")
            return model
        }
        return model
    }

    private func review(_ model: InstamartViewModel) -> InstamartReview? {
        if case let .review(review) = model.phase { return review }
        return nil
    }

    // MARK: - Availability

    func testHiddenWithoutFlagOrSignedOutAndAsksNothingItNeedNot() async {
        let model = subject()

        await model.refresh(user: User(id: "u1", name: "Asha"))
        XCTAssertEqual(model.offer, .hidden)
        await model.refresh(user: nil)
        XCTAssertEqual(model.offer, .hidden)
        // The cheap gates refused, so not even the geo lookup ran.
        XCTAssertEqual(gateway.countryCalls, 0)

        gateway.countryResult = .success(nil)
        await model.refresh(user: F.flaggedUser)
        XCTAssertEqual(model.offer, .hidden)
        XCTAssertEqual(gateway.statusCalls, 0)

        gateway.countryResult = .success("US")
        await model.refresh(user: F.flaggedUser, force: true)
        XCTAssertEqual(model.offer, .hidden)
        XCTAssertEqual(gateway.statusCalls, 0)
    }

    func testServer404OrFailedStatusHidesTheButton() async {
        let model = subject()
        gateway.statusResult = .success(.unavailable)
        await model.refresh(user: F.flaggedUser)
        XCTAssertEqual(model.offer, .hidden)

        gateway.statusResult = .failure(InstamartFailure.rejected(message: "boom"))
        await model.refresh(user: F.flaggedUser, force: true)
        XCTAssertEqual(model.offer, .hidden)
    }

    func testRefreshDoesNotRepeatForTheSameUserAndCachesTheCountry() async {
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.refresh(user: F.flaggedUser)
        XCTAssertEqual(gateway.statusCalls, 1)
        XCTAssertEqual(model.offer, .available(connected: true))

        await model.refresh(user: F.flaggedUser, force: true)
        XCTAssertEqual(gateway.statusCalls, 2)
        XCTAssertEqual(gateway.countryCalls, 1)
    }

    // MARK: - Connecting

    func testNotConnectedHandsOutTheSignInURLThenBuildsOnceConnected() async {
        gateway.statusResult = .success(.disconnected)
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        XCTAssertEqual(model.offer, .available(connected: false))

        await model.order(F.request)
        XCTAssertEqual(model.phase, .connecting)
        XCTAssertEqual(model.pendingSignInURL, URL(string: "https://swiggy.example/consent"))
        XCTAssertTrue(gateway.buildRequests.isEmpty)

        let gate = Gate<CartBuild>()
        gateway.build = { try await gate.wait() }
        gateway.statusResult = .success(.connected)
        let finishing = Task { await model.signInFinished() }
        await waitUntil { model.phase == .building }
        XCTAssertNil(model.pendingSignInURL)
        XCTAssertEqual(model.offer, .available(connected: true))
        // The request captured at the tap, carried across the round trip.
        XCTAssertEqual(gateway.buildRequests, [F.request.haveAlready])

        gate.open(.success(F.firstBuild))
        await finishing.value
        XCTAssertEqual(model.phase, .review(InstamartReview(build: F.firstBuild)))
        XCTAssertEqual(events.map(\.action), [AnalyticsEvents.Shopping.swiggyCartBuilt])
        XCTAssertEqual(events.first?.parameters[AnalyticsProperties.matchedCount] as? Int, 2)
        XCTAssertEqual(events.first?.parameters[AnalyticsProperties.missedCount] as? Int, 1)
    }

    func testSignInEndingWithoutAConnectionGoesIdleAndSaysSo() async {
        gateway.statusResult = .success(.disconnected)
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)

        await model.signInFinished()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.pendingSignInURL)
        XCTAssertEqual(model.offer, .available(connected: false))
        XCTAssertEqual(model.message, "Swiggy is not connected yet.")
        XCTAssertTrue(gateway.buildRequests.isEmpty)
    }

    func testSignInFinishedOutsideConnectingDoesNothing() async {
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.signInFinished()
        XCTAssertEqual(gateway.statusCalls, 1)
        XCTAssertEqual(model.phase, .idle)
    }

    func testAFailedConnectURLStaysIdleWithTheConnectLine() async {
        gateway.statusResult = .success(.disconnected)
        gateway.connectResult = .failure(URLError(.timedOut))
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.pendingSignInURL)
        XCTAssertEqual(model.message, "Could not start Swiggy sign-in.")
    }

    // MARK: - Building

    func testALapsedGrantDuringBuildMarksSwiggyDisconnected() async {
        gateway.build = { throw InstamartFailure.reconnect(message: "Swiggy session expired") }
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.offer, .available(connected: false))
        XCTAssertEqual(model.message, "Reconnect Swiggy to order.")
    }

    func testANetworkFailureDuringBuildClosesWithTheActionsOwnLine() async {
        gateway.build = { throw APIError.offline }
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "Could not build a Swiggy cart.")
    }

    func testCancelBuildDropsAResponseThatLandsAfterwards() async {
        let gate = Gate<CartBuild>()
        gateway.build = { try await gate.wait() }
        let model = subject()
        await model.refresh(user: F.flaggedUser)
        let ordering = Task { await model.order(F.request) }
        await waitUntil { model.phase == .building }

        model.cancelBuild()
        gate.open(.success(F.firstBuild))
        await ordering.value

        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.message)
        XCTAssertTrue(events.isEmpty)

        // And the flow is free for the next tap.
        gateway.build = { F.firstBuild }
        await model.order(F.request)
        XCTAssertEqual(model.phase, .review(InstamartReview(build: F.firstBuild)))
    }

    // MARK: - Review

    func testRebuildSendsTheKeptLinesAndRemembersTheRestAsRemoved() async {
        let model = await inReview()
        let onionOnly = CartBuild(
            plan: CartPlan(lines: [F.onion], misses: ["Saffron"]),
            cart: F.firstBuild.cart,
            priced: F.firstBuild.priced
        )
        gateway.rebuild = { onionOnly }

        await model.rebuild(keptSpinIds: ["s1"])
        XCTAssertEqual(gateway.rebuildRequests.last?.lines, [F.onion])
        XCTAssertEqual(gateway.rebuildRequests.last?.misses, ["Saffron"])
        XCTAssertEqual(model.phase, .review(InstamartReview(build: onionOnly, removed: [F.tomato])))

        // Putting tomato back draws it from `removed`.
        gateway.rebuild = { F.firstBuild }
        await model.rebuild(keptSpinIds: ["s1", "s2"])
        XCTAssertEqual(gateway.rebuildRequests.last?.lines, [F.onion, F.tomato])
        XCTAssertEqual(model.phase, .review(InstamartReview(build: F.firstBuild, removed: [])))
    }

    func testRebuildAndCheckoutCannotOverlap() async {
        let model = await inReview()
        let gate = Gate<CartBuild>()
        gateway.rebuild = { try await gate.wait() }

        let rebuilding = Task { await model.rebuild(keptSpinIds: ["s1"]) }
        await waitUntil { self.gateway.rebuildRequests.count == 1 }
        XCTAssertEqual(review(model)?.rebuilding, true)
        await model.placeOrder(expectedTotal: 120)
        await model.rebuild(keptSpinIds: ["s2"])
        XCTAssertTrue(gateway.checkoutRequests.isEmpty)
        XCTAssertEqual(gateway.rebuildRequests.count, 1)

        gate.open(.success(F.firstBuild))
        await rebuilding.value
        XCTAssertEqual(gateway.rebuildRequests.count, 1)
        XCTAssertEqual(review(model)?.busy, false)
    }

    func testARateLimitedRebuildKeepsTheReviewOpenForAManualRetry() async {
        let model = await inReview()
        gateway.rebuild = { throw InstamartFailure.rateLimited(message: "Slow down", retryAfterSeconds: 30) }

        await model.rebuild(keptSpinIds: ["s1"])
        XCTAssertEqual(model.phase, .review(InstamartReview(build: F.firstBuild)))
        XCTAssertEqual(model.message, "Slow down")
        XCTAssertEqual(gateway.rebuildRequests.count, 1, "never retried")
    }

    // MARK: - Checkout

    func testUnrecordedCheckoutBuildsTheOrderHereAndHandsItToTheList() async {
        let model = await inReview()
        gateway.checkoutReply = { CheckoutResponse(orderId: "o1", total: "", recorded: false) }

        await model.placeOrder(expectedTotal: 120)

        let items = [OrderedItem(name: "onion", display: "Onion")]
        XCTAssertEqual(gateway.checkoutRequests.count, 1)
        XCTAssertEqual(gateway.checkoutRequests.first?.total, 120)
        XCTAssertEqual(gateway.checkoutRequests.first?.week, F.week)
        XCTAssertEqual(gateway.checkoutRequests.first?.items, items)

        let iso = InstamartOrders.toISOString(epochMillis: F.nowMillis)
        let expected = StoredOrder(
            orderId: "o1", placedAt: iso, total: "₹120.00", status: "live", checkedAt: iso, items: items
        )
        XCTAssertEqual(placed, [PlacedOrder(order: expected, recorded: false, weekStartDate: F.week)])
        XCTAssertEqual(model.phase, .placed(order: expected, stillToBuy: ["Saffron", "Tomato"]))
        XCTAssertEqual(events.last?.action, AnalyticsEvents.Shopping.swiggyOrderPlaced)
        XCTAssertEqual(events.last?.parameters[AnalyticsProperties.total] as? Double, 120)

        model.dismissPlaced()
        XCTAssertEqual(model.phase, .idle)
    }

    func testRecordedCheckoutUsesTheServersOrder() async {
        let model = await inReview()
        let serverOrder = StoredOrder(orderId: "o9", placedAt: "2026-10-08T10:00:00.000Z", total: "₹118.00")
        gateway.checkoutReply = {
            CheckoutResponse(orderId: "o9", total: "₹118.00", order: serverOrder, recorded: true)
        }

        await model.placeOrder(expectedTotal: 120)

        XCTAssertEqual(placed, [PlacedOrder(order: serverOrder, recorded: true, weekStartDate: F.week)])
        guard case let .placed(order, _) = model.phase else { return XCTFail("Expected placed") }
        XCTAssertEqual(order, serverOrder)
    }

    func testRecordedWithoutAnOrderIsTreatedAsUnrecorded() async {
        let model = await inReview()
        gateway.checkoutReply = { CheckoutResponse(orderId: "o2", total: "₹119.00", order: nil, recorded: true) }

        await model.placeOrder(expectedTotal: 120)

        XCTAssertEqual(placed.first?.recorded, false)
        XCTAssertEqual(placed.first?.order.orderId, "o2")
        XCTAssertEqual(placed.first?.order.total, "₹119.00")
    }

    func testStillToBuyIncludesLinesTheUserRemoved() async {
        let model = await inReview()
        let onionOnly = CartBuild(
            plan: CartPlan(lines: [F.onion], misses: ["Saffron"]),
            cart: F.firstBuild.cart,
            priced: [F.priced(F.onion, inCart: true)]
        )
        gateway.rebuild = { onionOnly }
        await model.rebuild(keptSpinIds: ["s1"])

        await model.placeOrder(expectedTotal: 80)
        guard case let .placed(_, stillToBuy) = model.phase else { return XCTFail("Expected placed") }
        XCTAssertEqual(stillToBuy, ["Saffron", "Tomato"])
    }

    func testRepricedClosesTheReviewWithTheServersWords() async {
        let model = await inReview()
        gateway.checkoutReply = { throw InstamartFailure.repriced(message: "The total changed to ₹130.") }

        await model.placeOrder(expectedTotal: 120)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "The total changed to ₹130.")
        XCTAssertTrue(placed.isEmpty)
    }

    func testExpiredClosesTheReviewToo() async {
        let model = await inReview()
        gateway.rebuild = { throw InstamartFailure.expired(message: "Your cart expired.") }

        await model.rebuild(keptSpinIds: ["s1"])
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "Your cart expired.")
    }

    func testARejectedCheckoutStaysOnTheReviewWithTheButtonLive() async {
        let model = await inReview()
        gateway.checkoutReply = { throw InstamartFailure.rejected(message: "Below the minimum order.") }

        await model.placeOrder(expectedTotal: 120)
        XCTAssertEqual(review(model)?.placing, false)
        XCTAssertEqual(model.message, "Below the minimum order.")
        XCTAssertEqual(reloads, 0)
    }

    func testAnUnconfirmedCheckoutClosesAndAsksTheListToReload() async {
        let model = await inReview()
        gateway.checkoutReply = { throw InstamartFailure.checkoutUnconfirmed(message: "Check your Swiggy orders.") }

        await model.placeOrder(expectedTotal: 120)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "Check your Swiggy orders.")
        XCTAssertEqual(reloads, 1)
        XCTAssertTrue(placed.isEmpty)
        XCTAssertEqual(gateway.checkoutRequests.count, 1, "never retried")
    }

    func testDismissIsRefusedWhilePlacingAndTheOrderStillLands() async {
        let model = await inReview()
        let gate = Gate<CheckoutResponse>()
        gateway.checkoutReply = { try await gate.wait() }

        let placing = Task { await model.placeOrder(expectedTotal: 120) }
        await waitUntil { self.gateway.checkoutRequests.count == 1 }
        model.dismiss()
        XCTAssertEqual(review(model)?.placing, true)

        gate.open(.success(CheckoutResponse(orderId: "o1")))
        await placing.value
        guard case .placed = model.phase else { return XCTFail("Expected placed") }
        XCTAssertEqual(placed.map(\.order.orderId), ["o1"])
    }

    func testAnOrderPlacedWithNobodyListeningIsDeliveredOnceSomeoneIs() async {
        let model = subject(listening: false)
        await model.refresh(user: F.flaggedUser)
        await model.order(F.request)
        await model.placeOrder(expectedTotal: 120)
        XCTAssertTrue(placed.isEmpty)

        model.onOrderPlaced = { [unowned self] in placed.append($0) }
        XCTAssertEqual(placed.map(\.order.orderId), ["o1"])
        // Delivered once, not on every re-assignment.
        model.onOrderPlaced = { [unowned self] in placed.append($0) }
        XCTAssertEqual(placed.count, 1)
    }

    func testDismissClosesAReviewAndALogoutResetsTheFlow() async {
        let model = await inReview()
        model.dismiss()
        XCTAssertEqual(model.phase, .idle)

        await model.order(F.request)
        guard case .review = model.phase else { return XCTFail("Expected a review") }
        await model.refresh(user: nil)
        XCTAssertEqual(model.offer, .hidden)
        XCTAssertEqual(model.phase, .idle)
    }
}
