import XCTest
@testable import KhanaKit

/// How a groceries failure is typed — a port of Android's `InstamartFailureTest.kt`
/// — plus the raw-response path through `APIClient` that feeds it.
final class InstamartFailureTests: XCTestCase {

    private func failure(
        _ status: Int,
        _ body: String?,
        retryAfter: String? = nil,
        fallback: String = InstamartFailure.Fallback.generic
    ) -> InstamartFailure {
        InstamartFailure.from(
            status: status, body: body.map { Data($0.utf8) }, retryAfter: retryAfter, fallback: fallback
        )
    }

    // MARK: - InstamartFailure.from

    func testALapsedGrantAsksToReconnect() {
        let result = failure(409, #"{"error":"Swiggy sign-in expired","reconnect":true}"#)
        XCTAssertEqual(result, .reconnect(message: "Swiggy sign-in expired"))
        XCTAssertEqual(result.message, "Swiggy sign-in expired")
    }

    func testRepricedAndExpiredCartsKeepTheServersWords() {
        XCTAssertEqual(
            failure(409, #"{"error":"The price changed while you were reviewing. Check the cart again.","repriced":true}"#),
            .repriced(message: "The price changed while you were reviewing. Check the cart again.")
        )
        XCTAssertEqual(
            failure(409, #"{"error":"Your Swiggy cart expired. Build it again.","expired":true}"#),
            .expired(message: "Your Swiggy cart expired. Build it again.")
        )
    }

    /// The webapp's `=== true`: only a JSON boolean counts, and only on a 409 —
    /// the one status the server sends the flags with.
    func testFlagsOnlyCountAsAJSONTrueOnA409() {
        XCTAssertEqual(failure(409, #"{"error":"x","reconnect":"true"}"#), .rejected(message: "x"))
        XCTAssertEqual(failure(409, #"{"error":"x","reconnect":false}"#), .rejected(message: "x"))
        XCTAssertEqual(failure(409, #"{"error":"x","reconnect":1}"#), .rejected(message: "x"))
        XCTAssertEqual(failure(502, #"{"error":"x","reconnect":true}"#), .rejected(message: "x"))
    }

    /// Server order of precedence: reconnect is checked before repriced/expired.
    func testReconnectWinsOverTheCartFlags() {
        XCTAssertEqual(
            failure(409, #"{"error":"x","expired":true,"reconnect":true}"#), .reconnect(message: "x")
        )
    }

    func testA429CarriesTheRetryHintInSeconds() {
        XCTAssertEqual(
            failure(429, #"{"error":"Swiggy is rate limiting us — try again in a minute."}"#, retryAfter: "60"),
            .rateLimited(message: "Swiggy is rate limiting us — try again in a minute.", retryAfterSeconds: 60)
        )
        // Seconds only: the HTTP-date form is not guessed at.
        XCTAssertEqual(
            failure(429, nil, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT", fallback: "Could not build a Swiggy cart."),
            .rateLimited(message: "Could not build a Swiggy cart.", retryAfterSeconds: nil)
        )
        XCTAssertEqual(
            failure(429, nil, retryAfter: " -5 "),
            .rateLimited(message: InstamartFailure.Fallback.generic, retryAfterSeconds: nil)
        )
        XCTAssertEqual(
            failure(429, nil, retryAfter: " 30 "),
            .rateLimited(message: InstamartFailure.Fallback.generic, retryAfterSeconds: 30)
        )
    }

    func testA422IsRejectedVerbatim() {
        XCTAssertEqual(
            failure(
                422,
                #"{"error":"Tag one of your Swiggy addresses as Home so we know where to deliver.","ambiguousAddress":true,"candidates":[]}"#
            ),
            .rejected(message: "Tag one of your Swiggy addresses as Home so we know where to deliver.")
        )
    }

    func testAnUnparseableOrEmptyBodyFallsBackToTheCallsMessage() {
        XCTAssertEqual(
            failure(502, "<html>", fallback: "Could not place the order.").message, "Could not place the order."
        )
        XCTAssertEqual(
            failure(500, nil, fallback: "Could not update the Swiggy cart.").message,
            "Could not update the Swiggy cart."
        )
        XCTAssertEqual(
            failure(502, #"{"error":"  "}"#, fallback: "Could not place the order.").message,
            "Could not place the order."
        )
        XCTAssertEqual(failure(502, #"{"error":42}"#).message, InstamartFailure.Fallback.generic)
    }

    func testCheckoutUnconfirmedNeverInvitesARetry() {
        let unconfirmed = InstamartFailure.checkoutUnconfirmed()
        XCTAssertEqual(
            unconfirmed.message,
            "We couldn't confirm whether your order went through. Check your Swiggy orders before ordering again."
        )
        XCTAssertEqual(unconfirmed.localizedDescription, unconfirmed.message)
    }

    // MARK: - InstamartAvailability

    func testA404MeansTheFeatureIsOffNotAFailure() {
        XCTAssertEqual(InstamartAvailability.from(status: 404, body: Data()), .unavailable)
    }

    func testA200SaysWhetherSwiggyIsConnected() {
        XCTAssertEqual(
            InstamartAvailability.from(status: 200, body: Data(#"{"connected":true,"expiresAt":1}"#.utf8)),
            .connected
        )
        XCTAssertEqual(
            InstamartAvailability.from(status: 200, body: Data(#"{"connected":false,"expiresAt":null}"#.utf8)),
            .disconnected
        )
        // Not proof of a token, so not connected.
        XCTAssertEqual(InstamartAvailability.from(status: 200, body: Data("{}".utf8)), .disconnected)
    }

    func testAnyOtherStatusIsAFailureForTheCallerToType() {
        XCTAssertNil(InstamartAvailability.from(status: 502, body: Data()))
        XCTAssertNil(InstamartAvailability.from(status: 409, body: Data()))
    }

    // MARK: - APIClient.sendRaw

    private func client(token: String? = "tok") -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://example.test/")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { token }
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// A groceries 409 must reach the mapper with its body intact — `send`
    /// would have turned it into `.accountAlreadyExists` and dropped the flags.
    func testSendRawHandsBackANon2xxWithItsBodyAndHeaders() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return (429, ["Retry-After": "60"], Data(#"{"error":"slow down"}"#.utf8))
        }
        let response = try await client().sendRaw(Endpoints.groceriesStatus)
        XCTAssertEqual(response.status, 429)
        XCTAssertFalse(response.isSuccess)
        XCTAssertEqual(response.header("retry-after"), "60")
        XCTAssertEqual(
            InstamartFailure.from(response, fallback: "f"),
            .rateLimited(message: "slow down", retryAfterSeconds: 60)
        )
    }

    func testSendRawDecodesASuccess() async throws {
        StubURLProtocol.handler = { _ in (200, [:], Data(#"{"country":"IN"}"#.utf8)) }
        let response = try await client().sendRaw(Endpoints.geo)
        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(try response.decode(GeoResponse.self).country, "IN")
    }

    func testSendRawDecodeFailureIsADecodingError() async throws {
        StubURLProtocol.handler = { _ in (200, [:], Data("<html>".utf8)) }
        let response = try await client().sendRaw(Endpoints.geo)
        XCTAssertThrowsError(try response.decode(GeoResponse.self)) { error in
            guard case APIError.decoding = error else { return XCTFail("\(error)") }
        }
    }

    /// A dead session is still a dead session on these routes: the global
    /// sign-out must keep firing.
    func testSendRawStillSignalsUnauthorizedOnAnAuthenticated401() async throws {
        StubURLProtocol.handler = { _ in (401, [:], Data(#"{"error":"Unauthorized"}"#.utf8)) }
        let api = client()
        let fired = Flag()
        await api.setUnauthorizedHandler { await fired.set() }
        do {
            _ = try await api.sendRaw(Endpoints.groceriesStatus)
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            let didFire = await fired.value
            XCTAssertTrue(didFire)
        }
    }
}

private actor Flag {
    var value = false
    func set() { value = true }
}

/// Answers every request from `handler`. Tests in this file set it per case.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
