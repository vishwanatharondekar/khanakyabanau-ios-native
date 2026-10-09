import Foundation
import KhanaKit

/// Whether the Instamart button exists at all, and which tap it means.
enum InstamartOffer: Hashable {
    /// Not offered: wrong brand, guest, unflagged, outside India, the server's
    /// 404, or any failure finding out. Every unknown lands here — showing a
    /// button that cannot work is worse than not showing it.
    case hidden
    /// Offered. `connected` false means the tap opens Swiggy's sign-in first.
    case available(connected: Bool)
}

/// Swiggy's cart, on screen for confirmation.
///
/// `removed` are lines the user unticked in an earlier round, kept so they can
/// be put back. `rebuilding` and `placing` are mutually exclusive and each
/// disables the other's button: a cart write racing a checkout is how an order
/// ends up not matching the screen it was confirmed on.
struct InstamartReview: Hashable {
    var build: CartBuild
    var removed: [CartPlanLine] = []
    var rebuilding = false
    var placing = false

    var busy: Bool { rebuilding || placing }
}

/// Where the ordering flow is. One at a time; every phase but `.idle` is a sheet.
enum InstamartPhase: Hashable {
    case idle
    /// Swiggy's sign-in is up (`InstamartViewModel.pendingSignInURL`) and we are
    /// waiting for it to finish — see `InstamartViewModel.signInFinished()`.
    case connecting
    /// `POST api/groceries/cart` in flight. Dismissable: see `cancelBuild()`.
    case building
    case review(InstamartReview)
    /// The receipt. `stillToBuy` is captured at checkout; the cart that knew it is gone.
    case placed(order: StoredOrder, stillToBuy: [String])
}

/// Everything the cart request needs, captured at the tap. Held across the
/// sign-in round trip so the cart built afterwards is the list the user
/// actually tapped on, not whatever it became while Swiggy's page was up.
struct OrderRequest: Hashable {
    var scoped: ScopedShoppingList
    /// `haveAlready ∪ ordered` (`ShoppingListViewModel.cartHaveAlready`), so a
    /// second cart cannot re-buy what is on its way.
    var haveAlready: [String]
    var isVegetarian: Bool
    var weekStartDate: String
}

/// A checkout that came back 2xx, handed to the week's list. When `recorded`
/// is false the server did not save it and the list must
/// (`ShoppingListViewModel.onOrderPlaced`).
struct PlacedOrder: Hashable {
    var order: StoredOrder
    var recorded: Bool
    var weekStartDate: String
}

/// Swiggy Instamart ordering from the shopping list: who sees the button, and
/// the connect → build → review → place flow behind it. Port of Android's
/// `InstamartViewModel`; the list half (`orders`, `haveAlready`, status sync)
/// stays with the list, in `ShoppingListViewModel`.
///
/// Every action is `async` and returns when its work is done, so the view
/// calls it from a `Task` and tests simply await it. Internally each runs in a
/// stored task so `cancelBuild()` and a user change can stop it.
///
/// Nothing here retries. Swiggy allows 30 cart writes a minute and every order
/// is uncancellable cash on delivery; a second attempt is the user's decision,
/// made on a screen that told them the first one failed.
@MainActor
@Observable
final class InstamartViewModel {
    static let reconnectMessage = "Reconnect Swiggy to order."
    static let notConnectedMessage = "Swiggy is not connected yet."

    private(set) var offer: InstamartOffer = .hidden
    private(set) var phase: InstamartPhase = .idle

    /// Swiggy's consent page, while one is wanted. The view presents it in an
    /// `ASWebAuthenticationSession` and, when that session ends *for any
    /// reason* — callback, cancel, error, or failing to start at all — calls
    /// `signInFinished()`. The callback URL proves nothing; the status re-check
    /// in `signInFinished` is what decides.
    private(set) var pendingSignInURL: URL?

    /// One line for the user, already in their words. Bind to `kkbToast`,
    /// which clears it.
    var message: String?

    /// Receives every placed order. Set by whoever owns the week's list.
    ///
    /// Buffered: an order placed while nobody is listening (the pane went away
    /// mid-checkout) is held and delivered the moment this is set, because an
    /// unrecorded order's only route to the server is the list receiving it.
    /// Android uses a buffered Channel for the same reason.
    var onOrderPlaced: ((PlacedOrder) -> Void)? {
        didSet { deliverPending() }
    }

    /// Asked to re-read the week's list after a checkout whose outcome is
    /// unknown: the server may have recorded an order. Buffered like
    /// `onOrderPlaced`.
    var onReloadShopping: (() -> Void)? {
        didSet { deliverPending() }
    }

    private let gateway: any InstamartGateway
    private let track: (AnalyticsEvent) -> Void
    private let now: () -> Date
    private let brand: Brand

    /// Cached once the edge answers; it does not change under a session.
    private var country: String?

    /// What the last `refresh` decided on, so a re-render does not re-ask.
    private var availabilityKey: AvailabilityKey?
    private var availabilityTask: Task<Void, Never>?
    private var userId: String?

    /// Held across `.connecting`; consumed by the build that follows.
    private var pending: OrderRequest?
    /// The request behind the current building/review, for its week.
    private var active: OrderRequest?
    /// The one in-flight call of the ordering flow, whichever it is.
    private var flowTask: Task<Void, Never>?

    private var undelivered: [PlacedOrder] = []
    private var reloadOwed = false

    private struct AvailabilityKey: Equatable {
        var id: String?
        var guest: Bool
        var flag: Bool
    }

    init(
        gateway: any InstamartGateway,
        track: @escaping (AnalyticsEvent) -> Void = { _ in },
        now: @escaping () -> Date = Date.init,
        brand: Brand = .current
    ) {
        self.gateway = gateway
        self.track = track
        self.now = now
        self.brand = brand
    }

    convenience init(env: AppEnvironment) {
        let analytics = env.analytics
        self.init(gateway: env.instamart, track: { analytics.track($0) })
    }

    // MARK: - Availability

    /// Decide whether to offer Instamart to `user`. Cheap gates first: nothing
    /// goes to the network for a user the brand, guest or flag check already
    /// refuses. Re-runs only when the user or their flag changes, or on
    /// `force` (the Shopping pane opening, to pick up a server-side switch or
    /// a connection made on the web).
    func refresh(user: User?, force: Bool = false) async {
        let key = AvailabilityKey(
            id: user?.id, guest: user?.isGuest ?? false, flag: user?.features.swiggyInstamart ?? false
        )
        if !force, key == availabilityKey { return }
        let userChanged = availabilityKey?.id != key.id
        availabilityKey = key
        userId = user?.id

        // A different person: whatever flow the last one left open is not
        // theirs. An order mid-checkout is the exception — its result still
        // has to land.
        if userChanged, !isPlacing { resetFlow() }

        availabilityTask?.cancel()
        // "IN" stands in for the country only to ask the non-network gates first.
        guard canOrderInstamart(brand: brand, user: user, country: "IN") else {
            offer = .hidden
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            // A failed lookup is not cached: the next refresh asks again.
            if self.country == nil, let fresh = try? await self.gateway.country() {
                self.country = fresh
            }
            guard !Task.isCancelled else { return }
            guard canOrderInstamart(brand: self.brand, user: user, country: self.country) else {
                self.offer = .hidden
                return
            }
            let availability = try? await self.gateway.status()
            guard !Task.isCancelled else { return }
            self.offer = switch availability {
            case .connected: .available(connected: true)
            case .disconnected: .available(connected: false)
            // The server's 404 and any failure alike: no button.
            case .unavailable, nil: .hidden
            }
        }
        availabilityTask = task
        await task.value
    }

    // MARK: - Flow

    /// The Instamart button. Connected: build the cart. Not connected: fetch
    /// Swiggy's consent URL into `pendingSignInURL` and remember `request`
    /// for when the sign-in ends.
    func order(_ request: OrderRequest) async {
        guard case let .available(connected) = offer, phase == .idle, flowTask == nil else { return }

        if connected {
            await runFlow { await $0.startBuild(request) }
            return
        }
        await runFlow { model in
            do {
                let url = try await model.gateway.connectURL()
                model.pending = request
                model.phase = .connecting
                model.pendingSignInURL = url
            } catch {
                model.fail(error, fallback: InstamartFailure.Fallback.connect)
            }
        }
    }

    /// The sign-in sheet closed, however it closed. Only meaningful while
    /// `.connecting`: the status is re-checked whatever ended the session,
    /// because the callback carries no secret and a cancel may still follow a
    /// completed consent.
    func signInFinished() async {
        pendingSignInURL = nil
        guard phase == .connecting, flowTask == nil else { return }
        let request = pending
        pending = nil
        await runFlow { model in
            switch try? await model.gateway.status() {
            case .connected:
                model.offer = .available(connected: true)
                if let request {
                    await model.startBuild(request)
                } else {
                    model.phase = .idle
                }
            case .unavailable:
                // Switched off server-side while the user was away.
                model.offer = .hidden
                model.phase = .idle
                model.message = Self.notConnectedMessage
            // Not connected, or we could not tell — the webapp reads a failed
            // status check as "not connected" too.
            case .disconnected, nil:
                if case .available = model.offer { model.offer = .available(connected: false) }
                model.phase = .idle
                model.message = Self.notConnectedMessage
            }
        }
    }

    /// Dismissing the building sheet stops the build. The task is cancelled
    /// and, belt and braces, the result is only applied while the phase is
    /// still `.building` — so a response that lands in the instant before the
    /// dismissal cannot reopen a sheet over whatever the user moved on to.
    func cancelBuild() {
        guard phase == .building else { return }
        flowTask?.cancel()
        flowTask = nil
        active = nil
        phase = .idle
    }

    /// Re-price with only the lines in `keptSpinIds`, drawn from what Swiggy
    /// holds now plus what was removed earlier. The rest become `removed`.
    /// Ignored while a rebuild or checkout is already in flight.
    func rebuild(keptSpinIds: Set<String>) async {
        guard let review = currentReview, !review.busy else { return }

        let split = InstamartCartLogic.splitForRebuild(
            current: review.build.plan.lines, removed: review.removed, keptSpinIds: keptSpinIds
        )
        var rebuilding = review
        rebuilding.rebuilding = true
        phase = .review(rebuilding)
        await runFlow { model in
            do {
                let build = try await model.gateway.rebuildCart(lines: split.kept, misses: review.build.plan.misses)
                // Dismissed meanwhile: the cart write happened, but there is
                // no review left to show it in.
                guard model.currentReview != nil else { return }
                model.phase = .review(InstamartReview(build: build, removed: split.removed))
            } catch {
                model.fail(error, fallback: InstamartFailure.Fallback.rebuild)
            }
        }
    }

    /// Place the cash-on-delivery order. `expectedTotal` is the To-pay figure
    /// the user confirmed, read with `InstamartCartLogic.parseRupees`; the
    /// server refuses if Swiggy's total has moved since.
    func placeOrder(expectedTotal: Double) async {
        guard let review = currentReview, !review.busy, let request = active else { return }

        // Only what Swiggy actually holds: a planned line it left out is not
        // on its way, and recording it would tick it off the list.
        let items = InstamartCartLogic.orderedItems(priced: review.build.priced)
        var placing = review
        placing.placing = true
        phase = .review(placing)
        await runFlow { model in
            do {
                let response = try await model.gateway.checkout(
                    expectedTotal: expectedTotal, weekStartDate: request.weekStartDate, items: items
                )
                // A 2xx is a placed order, always. Nothing below may depend on
                // the sheet still being open: the receipt and the record are
                // owed regardless.
                let recorded = response.recorded && response.order != nil
                let order: StoredOrder
                if recorded, let serverOrder = response.order {
                    order = serverOrder
                } else {
                    let stamp = InstamartOrders.toISOString(epochMillis: InstamartOrders.millis(model.now()))
                    order = StoredOrder(
                        orderId: response.orderId,
                        placedAt: stamp,
                        total: response.total.isEmpty ? review.build.cart.billBreakdown.toPay.value : response.total,
                        status: OrderStatus.live.wire,
                        statusLabel: "",
                        checkedAt: stamp,
                        items: items
                    )
                }
                model.active = nil
                model.phase = .placed(
                    order: order,
                    stillToBuy: InstamartCartLogic.stillToBuy(build: review.build, removed: review.removed)
                )
                model.undelivered.append(
                    PlacedOrder(order: order, recorded: recorded, weekStartDate: request.weekStartDate)
                )
                model.deliverPending()
                model.trackEvent(AnalyticsEvents.Shopping.swiggyOrderPlaced, [
                    AnalyticsProperties.total: expectedTotal,
                    AnalyticsProperties.weekStart: request.weekStartDate,
                ])
            } catch {
                model.fail(error, fallback: InstamartFailure.Fallback.checkout)
            }
        }
    }

    /// Close the review or the receipt. Refused while placing — the order is
    /// already on its way to Swiggy and its outcome must land on a screen. A
    /// rebuild in flight is abandoned (its result is ignored).
    func dismiss() {
        switch phase {
        case let .review(review) where review.placing:
            return
        case .review, .placed:
            break
        case .building:
            return cancelBuild()
        case .connecting:
            pending = nil
            pendingSignInURL = nil
        case .idle:
            return
        }
        flowTask?.cancel()
        flowTask = nil
        active = nil
        phase = .idle
    }

    /// The receipt's "Back to shopping list".
    func dismissPlaced() {
        if case .placed = phase { phase = .idle }
    }

    // MARK: - Internals

    private var currentReview: InstamartReview? {
        if case let .review(review) = phase { return review }
        return nil
    }

    private var isPlacing: Bool { currentReview?.placing ?? false }

    /// Runs `body` as the flow's one task and waits for it. The task is
    /// cleared on the way out only if it is still the current one — a
    /// `cancelBuild()` followed by a new tap must not have its task nulled by
    /// the old one finishing late.
    private func runFlow(_ body: @escaping @MainActor (InstamartViewModel) async -> Void) async {
        let task = Task { [weak self] in
            guard let self else { return }
            await body(self)
        }
        flowTask = task
        await task.value
        if flowTask == task { flowTask = nil }
    }

    /// Runs inside the flow task, so `cancelBuild()` cancels it.
    private func startBuild(_ request: OrderRequest) async {
        active = request
        phase = .building
        do {
            let build = try await gateway.buildCart(
                scoped: request.scoped, haveAlready: request.haveAlready, isVegetarian: request.isVegetarian
            )
            // Cancelled, or dismissed in the instant before the response landed.
            guard phase == .building, !Task.isCancelled else { return }
            phase = .review(InstamartReview(build: build))
            trackEvent(AnalyticsEvents.Shopping.swiggyCartBuilt, [
                AnalyticsProperties.matchedCount: build.plan.lines.count,
                AnalyticsProperties.missedCount: build.plan.misses.count,
                AnalyticsProperties.weekStart: request.weekStartDate,
            ])
        } catch {
            guard phase == .building, !Task.isCancelled else { return }
            fail(error, fallback: InstamartFailure.Fallback.build)
        }
    }

    /// One failure policy for every call. "Stay" means a review stays open
    /// with its buttons live again, so the user can retry by hand; any other
    /// phase has nothing to stay in and closes.
    private func fail(_ error: any Error, fallback: String) {
        switch error as? InstamartFailure {
        case .reconnect:
            closeFlow()
            if case .available = offer { offer = .available(connected: false) }
            message = Self.reconnectMessage
        // "Look again", not "something broke": the cart is gone or no longer
        // what was confirmed, so the review closes and the user starts again
        // from the list.
        case let .repriced(text), let .expired(text):
            closeFlow()
            message = text
        // May or may not have reached Swiggy. No retry is offered, and the
        // list is re-read in case the server recorded an order.
        case let .checkoutUnconfirmed(text):
            closeFlow()
            message = text
            reloadOwed = true
            deliverPending()
        case let .rateLimited(text, _), let .rejected(text):
            stay()
            message = text
        // Offline, timeout, unreadable body: the action's own line.
        case nil:
            stay()
            message = fallback
        }
    }

    private func stay() {
        switch phase {
        case var .review(review):
            review.rebuilding = false
            review.placing = false
            phase = .review(review)
        case .placed:
            break
        default:
            closeFlow()
        }
    }

    private func closeFlow() {
        active = nil
        pending = nil
        pendingSignInURL = nil
        phase = .idle
    }

    private func resetFlow() {
        flowTask?.cancel()
        flowTask = nil
        closeFlow()
    }

    private func deliverPending() {
        if let onOrderPlaced, !undelivered.isEmpty {
            let placed = undelivered
            undelivered.removeAll()
            placed.forEach(onOrderPlaced)
        }
        if let onReloadShopping, reloadOwed {
            reloadOwed = false
            onReloadShopping()
        }
    }

    private func trackEvent(_ action: String, _ parameters: [String: Any]) {
        var parameters = parameters
        if let userId { parameters[AnalyticsProperties.userID] = userId }
        track(AnalyticsEvent(
            action: action,
            category: AnalyticsEvents.Category.shopping,
            label: "instamart",
            parameters: parameters
        ))
    }
}
