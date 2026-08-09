import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Which of the two request budgets an endpoint uses.
///
/// Android runs two OkHttp clients for exactly this reason: AI endpoints do not
/// stream and a meal plan or shopping list can legitimately take most of a minute
/// (`OPENAI_TIMEOUT_MS` defaults to 45 s server-side), while everything else should
/// fail fast.
public enum TimeoutProfile: Sendable {
    case standard
    case ai

    var requestTimeout: TimeInterval {
        switch self {
        case .standard: 10
        case .ai: 180
        }
    }
}

public struct Endpoint: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var requiresAuth: Bool
    public var profile: TimeoutProfile

    public init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool = true,
        profile: TimeoutProfile = .standard
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.profile = profile
    }

    /// JSON-encodes a request body. Optional properties encode via
    /// `encodeIfPresent`, so an all-nil payload correctly becomes `{}` — which is
    /// what `POST /api/meals/{week}/prep` uses to mean "the whole week".
    public static func json(_ value: some Encodable) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

/// The single HTTP entry point. Everything that talks to the backend goes through
/// here so auth, error mapping and timeouts have exactly one implementation.
public actor APIClient {
    /// Hard-coded on Android too (`NetworkModule.kt:45`); there is no staging host.
    public static let productionBaseURL = URL(string: "https://www.khanakyabanau.in/")!

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Reads the current session token. A closure rather than a stored value so the
    /// client always sees the live token after a login or a guest upgrade swaps it.
    private var tokenProvider: @Sendable () -> String?
    /// Invoked once when the server rejects our token. Android has no 401 handling
    /// at all; on iOS this drives a clean sign-out instead of an unexplained error.
    private var unauthorizedHandler: (@Sendable () async -> Void)?

    public init(
        baseURL: URL = APIClient.productionBaseURL,
        session: URLSession? = nil,
        tokenProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.decoder = JSONDecoder()

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // Per-request timeouts are set on each URLRequest; this is the ceiling
            // for the whole resource including retries.
            configuration.timeoutIntervalForRequest = TimeoutProfile.ai.requestTimeout
            configuration.timeoutIntervalForResource = 300
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func setTokenProvider(_ provider: @escaping @Sendable () -> String?) {
        tokenProvider = provider
    }

    public func setUnauthorizedHandler(_ handler: (@Sendable () async -> Void)?) {
        unauthorizedHandler = handler
    }

    // MARK: - Sending

    @discardableResult
    public func send(_ endpoint: Endpoint) async throws -> Data {
        let (data, response) = try await perform(endpoint)
        try await validate(response: response, data: data, endpoint: endpoint)
        return data
    }

    public func send<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(endpoint)
        return try decode(data, as: type)
    }

    /// For the handful of endpoints where a 404 means "nothing saved yet" rather
    /// than an error — `GET /api/auth/video-urls` is the documented case.
    public func sendAllowingNotFound<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws -> Response? {
        let (data, response) = try await perform(endpoint)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try await validate(response: response, data: data, endpoint: endpoint)
        return try decode(data, as: type)
    }

    /// Decodes a response that may legitimately be the JSON literal `null` —
    /// `GET /api/auth/dietary-preferences` returns the bare object or bare null.
    public func sendAllowingNull<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type
    ) async throws -> Response? {
        let data = try await send(endpoint)
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return nil }
        return try decode(data, as: type)
    }

    // MARK: - Internals

    private func perform(_ endpoint: Endpoint) async throws -> (Data, URLResponse) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let url = components?.url else {
            throw APIError.network("Could not build a URL for \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.profile.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth, let token = tokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func validate(
        response: URLResponse,
        data: Data,
        endpoint: Endpoint
    ) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Malformed response")
        }
        guard !(200...299).contains(http.statusCode) else { return }

        let payload = ErrorPayload(data: data)

        switch http.statusCode {
        // A 401 from an endpoint we sent a token to means that token is no longer
        // good. A 401 from login/register means the *credentials* were wrong — the
        // server says "Invalid credentials" and the user must see that, not
        // "your session expired".
        case 401 where endpoint.requiresAuth:
            await signalUnauthorized()
            throw APIError.unauthorized

        case 401:
            throw APIError.http(status: 401, message: payload.error)

        case 403 where payload.isGuestLimitReached:
            throw APIError.guestLimitReached(message: payload.error, info: payload.guestLimitInfo)

        case 409:
            throw APIError.accountAlreadyExists

        default:
            // Deliberately no 500-means-bad-token heuristic. A corrupt token does
            // surface as a 500 on some routes, but the AI routes echo the upstream
            // provider's message into their 500 body, and those messages routinely
            // contain the word "token" ("hit the 2000-token output limit",
            // "rate limit ... on tokens per min"). Signing out on that would clear
            // the keychain — including `guest_device_id`, which *is* the guest's
            // server-side user id — and permanently orphan everything they planned.
            // A stale token instead fails visibly on the next real 401.
            throw APIError.http(status: http.statusCode, message: payload.error)
        }
    }

    private func signalUnauthorized() async {
        guard let unauthorizedHandler else { return }
        await unauthorizedHandler()
    }

    private func decode<Response: Decodable>(
        _ data: Data,
        as type: Response.Type
    ) throws -> Response {
        // An empty 200 body is a valid "done" for several PUT/PATCH routes.
        if data.isEmpty, let empty = EmptyResponse() as? Response { return empty }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

/// Stand-in for endpoints whose response body we don't read.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

/// Parses the server's error envelope. Every route returns `{"error": "…"}`; some
/// add discriminator booleans.
private struct ErrorPayload {
    let error: String?
    let isGuestLimitReached: Bool
    let guestLimitInfo: GuestLimitInfo?
    init(data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        error = json?["error"] as? String
        isGuestLimitReached = json?["isGuestLimitReached"] as? Bool ?? false
        if let limit = json?["usageLimit"] as? Int, let usage = json?["currentUsage"] as? Int {
            guestLimitInfo = GuestLimitInfo(usageLimit: limit, currentUsage: usage)
        } else {
            guestLimitInfo = nil
        }
    }
}
