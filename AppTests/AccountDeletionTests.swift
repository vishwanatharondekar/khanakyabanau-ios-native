import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// Serves one canned HTTP response, so deletion can be exercised without a
/// backend — and without the throwaway production accounts the routing tests
/// have to create.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class AccountDeletionTests: XCTestCase {

    private func makeAuth() -> (AuthRepository, TokenStore) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(
            session: URLSession(configuration: config),
            tokenProvider: { "stub-token" }
        )
        let tokenStore = TokenStore()
        tokenStore.save("stub-token")
        return (AuthRepository(api: api, tokenStore: tokenStore), tokenStore)
    }

    func testDeletingTheAccountClearsTheStoredToken() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"success":true}"#.utf8)
        let (auth, tokenStore) = makeAuth()

        try await auth.deleteAccount(password: "s3cret")

        XCTAssertFalse(
            tokenStore.isAuthenticated,
            "The account is gone; keeping its token would 401 every later request."
        )
    }

    /// The reason the route answers 403 rather than 401. A mistyped password is
    /// an ordinary, recoverable error — it must not clear the session or leave
    /// the user believing their account was destroyed.
    func testAWrongPasswordLeavesTheUserSignedIn() async {
        StubURLProtocol.status = 403
        StubURLProtocol.body = Data(#"{"error":"That password isn't right."}"#.utf8)
        let (auth, tokenStore) = makeAuth()

        do {
            try await auth.deleteAccount(password: "wrong")
            XCTFail("A 403 must surface as an error, not a successful deletion")
        } catch {
            XCTAssertTrue(tokenStore.isAuthenticated)
        }
    }
}
