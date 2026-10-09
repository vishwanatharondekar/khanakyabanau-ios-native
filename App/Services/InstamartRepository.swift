import Foundation
import KhanaKit
import os

/// What the Instamart view models need from `InstamartRepository`, as a protocol
/// so they can be tested against a fake instead of the network — Android's
/// `InstamartGateway`, for the same reason. See the implementation for each
/// call's contract.
@MainActor
protocol InstamartGateway: AnyObject {
    func country() async throws -> String?
    func status() async throws -> InstamartAvailability
    func connectURL() async throws -> URL
    func disconnect() async throws
    func buildCart(scoped: ScopedShoppingList, haveAlready: [String], isVegetarian: Bool) async throws -> CartBuild
    func rebuildCart(lines: [CartPlanLine], misses: [String]) async throws -> CartBuild
    func checkout(expectedTotal: Double, weekStartDate: String, items: [OrderedItem]) async throws -> CheckoutResponse
    func orderStatus(orderId: String) async throws -> JSONValue
    func updateOrders(weekStartDate: String, orders: [StoredOrder], haveAlready: [String]?) async throws
}

/// Instamart ordering through the `api/groceries` routes, plus the orders half
/// of the shopping-list PATCH. Thin: Swiggy, prices and SKU choice are all
/// server-side, and so is the order record when checkout can make it.
///
/// Every groceries call goes through `APIClient.sendRaw`, never `send`: `send`
/// folds every 409 into `.accountAlreadyExists` and drops the body and the
/// `Retry-After` that `InstamartFailure.from` needs to tell a lapsed grant from
/// a repriced cart from a throttle.
///
/// Nothing here retries. Swiggy allows 30 cart writes a minute and every order
/// is uncancellable cash on delivery; a repeat is the user's call, not ours.
@MainActor
final class InstamartRepository: InstamartGateway {
    private let api: APIClient
    private static let log = Logger(subsystem: "in.khanakyabanau.app", category: "instamart")

    init(api: APIClient) {
        self.api = api
    }

    /// ISO country from the edge, or nil when unknown — which
    /// `canOrderInstamart` reads as "not India". Blank is unknown too.
    func country() async throws -> String? {
        let response = try await api.send(Endpoints.geo, as: GeoResponse.self)
        guard let country = response.country?.trimmingCharacters(in: .whitespacesAndNewlines),
              !country.isEmpty else { return nil }
        return country
    }

    /// A 404 is `.unavailable` — the server's gate saying no, a normal answer —
    /// while any other non-2xx throws, so the caller cannot mistake an outage
    /// for "switched off" or for "connected".
    func status() async throws -> InstamartAvailability {
        let response = try await api.sendRaw(Endpoints.groceriesStatus)
        if let availability = InstamartAvailability.from(response) { return availability }
        throw InstamartFailure.from(response)
    }

    /// Swiggy's consent page, for an `ASWebAuthenticationSession`.
    func connectURL() async throws -> URL {
        let response = try await api.sendRaw(Endpoints.groceriesConnect())
        guard response.isSuccess else {
            throw InstamartFailure.from(response, fallback: InstamartFailure.Fallback.connect)
        }
        // Only an absolute https URL is something we will open a sign-in sheet on.
        guard let body = try? response.decode(ConnectResponse.self),
              let url = URL(string: body.authorizeUrl),
              url.scheme?.lowercased() == "https" else {
            throw InstamartFailure.rejected(message: InstamartFailure.Fallback.connect)
        }
        return url
    }

    func disconnect() async throws {
        let response = try await api.sendRaw(Endpoints.groceriesDisconnect)
        guard response.isSuccess else { throw InstamartFailure.from(response) }
    }

    /// `haveAlready` should already include names on live orders — the
    /// webapp's `haveAlready ∪ ordered` — so a second cart cannot re-buy what
    /// is on its way.
    func buildCart(scoped: ScopedShoppingList, haveAlready: [String], isVegetarian: Bool) async throws -> CartBuild {
        let response = try await api.sendRaw(Endpoints.buildCart(BuildCartRequest(
            scoped: scoped, haveAlready: haveAlready, isVegetarian: isVegetarian
        )))
        guard response.isSuccess else {
            throw InstamartFailure.from(response, fallback: InstamartFailure.Fallback.build)
        }
        return try response.decode(CartBuild.self)
    }

    func rebuildCart(lines: [CartPlanLine], misses: [String]) async throws -> CartBuild {
        let response = try await api.sendRaw(Endpoints.rebuildCart(RebuildCartRequest(lines: lines, misses: misses)))
        guard response.isSuccess else {
            throw InstamartFailure.from(response, fallback: InstamartFailure.Fallback.rebuild)
        }
        return try response.decode(CartBuild.self)
    }

    /// Places the order. A return is a placed order, always — check
    /// `recorded` and save the order yourself when false.
    ///
    /// A non-2xx is a typed `InstamartFailure` and the server guarantees no
    /// order exists. Anything else — a timeout, a dropped connection, a 2xx we
    /// cannot read — is `.checkoutUnconfirmed`, because the request may have
    /// landed and the user may have an order they cannot see. The one
    /// exception is our own session dying (`APIError.unauthorized`): the server
    /// refused that before reaching Swiggy, so it is passed through as-is.
    func checkout(expectedTotal: Double, weekStartDate: String, items: [OrderedItem]) async throws -> CheckoutResponse {
        let response: RawResponse
        do {
            response = try await api.sendRaw(Endpoints.checkout(CheckoutRequest(
                expectedTotal: expectedTotal, weekStartDate: weekStartDate, items: items
            )))
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            Self.log.warning("checkout outcome unknown: \(String(describing: error), privacy: .public)")
            throw InstamartFailure.checkoutUnconfirmed()
        }
        guard response.isSuccess else {
            throw InstamartFailure.from(response, fallback: InstamartFailure.Fallback.checkout)
        }
        do {
            return try response.decode(CheckoutResponse.self)
        } catch {
            Self.log.warning("checkout 2xx unreadable: \(String(describing: error), privacy: .public)")
            throw InstamartFailure.checkoutUnconfirmed()
        }
    }

    /// Swiggy's delivery status, relayed raw; read it with
    /// `InstamartOrders.readOrderStatus`, never into a struct.
    func orderStatus(orderId: String) async throws -> JSONValue {
        let response = try await api.sendRaw(Endpoints.orderStatus(orderId))
        guard response.isSuccess else {
            throw InstamartFailure.from(response, fallback: InstamartFailure.Fallback.order)
        }
        return try response.decode(JSONValue.self)
    }

    /// The orders-capable shopping-list PATCH. `haveAlready` nil leaves it off
    /// the wire (untouched server-side); a status sync that moved delivered
    /// items sends both, so an order and the items it delivered cannot disagree
    /// after a half-failed update. Not a groceries route, so plain `send`.
    func updateOrders(weekStartDate: String, orders: [StoredOrder], haveAlready: [String]?) async throws {
        _ = try await api.send(Endpoints.updateShoppingList(
            weekStartDate, UpdateShoppingListRequest(haveAlready: haveAlready, orders: orders)
        ))
    }
}
