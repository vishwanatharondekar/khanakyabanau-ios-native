import XCTest
@testable import KhanaKit

/// The delete-account contract, which has two properties worth pinning down: it
/// must reach the route that actually deletes, and it must carry the password
/// re-authentication the server demands of registered users.
final class DeleteAccountEndpointTests: XCTestCase {

    func testTargetsTheAuthenticatedDeleteRoute() {
        let endpoint = Endpoints.deleteAccount(DeleteAccountRequest(password: "s3cret"))

        XCTAssertEqual(endpoint.method, .delete)
        XCTAssertEqual(endpoint.path, "api/auth/delete-account")
        XCTAssertTrue(
            endpoint.requiresAuth,
            "The server identifies the account to delete from the bearer token alone."
        )
    }

    func testCarriesThePasswordForARegisteredAccount() throws {
        let endpoint = Endpoints.deleteAccount(DeleteAccountRequest(password: "s3cret"))

        let body = try XCTUnwrap(endpoint.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["password"] as? String, "s3cret")
    }

    /// A guest has no password to re-enter. `encodeIfPresent` must leave the key
    /// out entirely rather than send an explicit null.
    func testOmitsThePasswordForAGuest() throws {
        let endpoint = Endpoints.deleteAccount(DeleteAccountRequest(password: nil))

        let body = try XCTUnwrap(endpoint.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true)
    }
}
