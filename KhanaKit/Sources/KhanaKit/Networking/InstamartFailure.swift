import Foundation

/// Whether Instamart ordering is on for this user, and if so whether Swiggy is
/// connected. `.unavailable` is the server's 404 — deployment switch off or the
/// user unflagged — and hides the button; it is a normal answer, not a failure.
public enum InstamartAvailability: Sendable, Hashable {
    case unavailable
    case disconnected
    case connected

    /// The answer `GET api/groceries/status` gave, or nil when the status says
    /// the call failed — type that with `InstamartFailure.from`.
    ///
    /// A 200 whose body does not say `connected: true` is `.disconnected`: not
    /// proof of a token, and the connect flow re-asks before building a cart.
    public static func from(status: Int, body: Data) -> InstamartAvailability? {
        if status == 404 { return .unavailable }
        guard (200...299).contains(status) else { return nil }
        let response = (try? JSONDecoder().decode(GroceriesStatusResponse.self, from: body))
            ?? GroceriesStatusResponse()
        return response.connected ? .connected : .disconnected
    }

    public static func from(_ response: RawResponse) -> InstamartAvailability? {
        from(status: response.status, body: response.body)
    }
}

/// Why a groceries call failed, typed by what the UI must do about it. Every
/// case carries the server's own sentence when it sent one, else the call's
/// fallback. Port of Android's `InstamartFailure` (`InstamartRepository.kt`).
public enum InstamartFailure: Error, Hashable, Sendable {
    /// 409 `reconnect`: the Swiggy grant lapsed or was never made. Mark disconnected.
    case reconnect(message: String)
    /// 409 `repriced`: the total moved after the user confirmed it. Nothing was charged.
    case repriced(message: String)
    /// 409 `expired`: Swiggy dropped the cart. Build it again.
    case expired(message: String)
    /// 429: Swiggy is throttling us. Shown, never retried automatically.
    case rateLimited(message: String, retryAfterSeconds: Int?)
    /// Anything else — 422s (address, minimum order, ceiling) included — in the server's words.
    case rejected(message: String)
    /// Checkout only: the request may or may not have reached Swiggy (timeout,
    /// dropped connection, unreadable 2xx). Unlike every other case this one
    /// does *not* mean "no order was placed", so the UI must not offer "try
    /// again" — the user checks their Swiggy orders, and the week's list is
    /// re-read in case the server recorded one. Never produced by `from`: the
    /// repository raises it for any checkout failure that is not an HTTP status.
    case checkoutUnconfirmed(message: String = Fallback.unconfirmed)

    /// Per-call fallbacks, verbatim from Android so the apps say the same thing.
    public enum Fallback {
        public static let generic = "Something went wrong with Swiggy. Try again."
        public static let connect = "Could not start Swiggy sign-in."
        public static let build = "Could not build a Swiggy cart."
        public static let rebuild = "Could not update the Swiggy cart."
        public static let checkout = "Could not place the order."
        public static let order = "Could not fetch that order."
        public static let unconfirmed =
            "We couldn't confirm whether your order went through. Check your Swiggy orders before ordering again."
    }

    public var message: String {
        switch self {
        case let .reconnect(message), let .repriced(message), let .expired(message),
             let .rejected(message), let .checkoutUnconfirmed(message):
            message
        case let .rateLimited(message, _):
            message
        }
    }

    /// Types a non-2xx from any groceries route.
    ///
    /// Every route fails as `{error, reconnect? | repriced? | expired?}`, with
    /// `Retry-After` on a 429. The flags only count on a 409, the one status the
    /// server sends them with, and only as a JSON `true` — the webapp's
    /// `=== true`, so `"true"` and `1` do not count. A missing, blank or
    /// non-string `error` (an HTML error page, an empty 502) gives `fallback`.
    public static func from(
        status: Int,
        body: Data?,
        retryAfter: String?,
        fallback: String = Fallback.generic
    ) -> InstamartFailure {
        let object = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        func flag(_ name: String) -> Bool { object?[name] == .bool(true) }

        let message = object?["error"]?.stringValue
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? fallback

        if status == 409, flag("reconnect") { return .reconnect(message: message) }
        if status == 409, flag("repriced") { return .repriced(message: message) }
        if status == 409, flag("expired") { return .expired(message: message) }
        if status == 429 {
            // Seconds only: the server never sends the HTTP-date form, and a
            // wrong guess at one is worse than no hint.
            let seconds = retryAfter
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .flatMap { $0 >= 0 ? $0 : nil }
            return .rateLimited(message: message, retryAfterSeconds: seconds)
        }
        return .rejected(message: message)
    }

    /// `from(status:body:retryAfter:fallback:)` for a `APIClient.sendRaw` result.
    public static func from(_ response: RawResponse, fallback: String = Fallback.generic) -> InstamartFailure {
        from(
            status: response.status,
            body: response.body,
            retryAfter: response.header("Retry-After"),
            fallback: fallback
        )
    }
}

extension InstamartFailure: LocalizedError {
    public var errorDescription: String? { message }
}
