import Foundation

/// The extra fields the server attaches to a 403 when a guest has used up their
/// free allowance (`app/api/ai/generate/route.ts:52-81`). Lifetime limits, not daily.
public struct GuestLimitInfo: Hashable, Sendable {
    public var usageLimit: Int
    public var currentUsage: Int

    public init(usageLimit: Int, currentUsage: Int) {
        self.usageLimit = usageLimit
        self.currentUsage = currentUsage
    }

    public var remaining: Int { max(0, usageLimit - currentUsage) }
}

public enum APIError: Error, Sendable {
    /// No route to host / DNS failure — the user is offline.
    case offline
    case timeout
    /// Any other transport-level failure.
    case network(String)
    /// Non-2xx with the server's `{"error": …}` body, when there was one.
    case http(status: Int, message: String?)
    /// 403 with `isGuestLimitReached` — the caller should offer account creation.
    case guestLimitReached(message: String?, info: GuestLimitInfo?)
    /// 409 on register / upgrade-guest.
    case accountAlreadyExists
    /// 401, or a 500 caused by a token the server couldn't parse.
    case unauthorized
    case decoding(String)

    /// User-facing copy, reproduced verbatim from Android's
    /// `Throwable.toUserMessage` (`core/common/error/UserMessage.kt:35`) so the
    /// two apps say the same thing about the same failure.
    public func userMessage(fallback: String) -> String {
        switch self {
        case .offline:
            "You're offline. Check your internet connection and try again."
        case .timeout:
            "The connection timed out. Please try again."
        case .network:
            "Network problem. Check your connection and try again."
        case .accountAlreadyExists:
            "An account with this email already exists. Please sign in instead."
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case let .http(_, message):
            message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        case let .guestLimitReached(message, _):
            message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        case .decoding:
            fallback
        }
    }

    /// True when retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .network: true
        case let .http(status, _): status >= 500
        default: false
        }
    }

    /// Maps a `URLError` onto the same three buckets Android derives from
    /// `UnknownHostException` / `SocketTimeoutException` / `IOException`.
    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .networkConnectionLost, .internationalRoamingOff,
             .dataNotAllowed:
            .offline
        case .timedOut:
            .timeout
        default:
            .network(urlError.localizedDescription)
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { userMessage(fallback: "Something went wrong.") }
}
