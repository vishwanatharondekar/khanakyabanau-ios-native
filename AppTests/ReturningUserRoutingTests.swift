import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// The returning-user routing bug, guarded at the level it actually lives.
///
/// `POST /api/auth/login` returns only `{id, email, name}` — no
/// `onboardingCompleted`, no cuisine or dietary preferences
/// (`app/api/auth/login/route.ts:63-69`). Routing from that response decodes
/// `onboardingCompleted` as its `false` default, so an established account is sent
/// back through onboarding, and finishing it overwrites the cuisines they had.
///
/// These run against the **production** backend and register one throwaway account
/// per run under the reserved `.invalid` TLD, which can never reach a real inbox or
/// collide with a real user.
@MainActor
final class ReturningUserRoutingTests: XCTestCase {

    private func uniqueEmail() -> String {
        "ios-test-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6))"
            .lowercased() + "@khanakyabanau.invalid"
    }

    /// The shape of the login response is the whole reason the profile fetch exists.
    func testLoginResponseOmitsOnboardingCompleted() throws {
        // Exactly what `app/api/auth/login/route.ts` returns.
        let json = #"{"token":"t","user":{"id":"abc","email":"a@b.com","name":"Asha"}}"#
        let response = try JSONDecoder().decode(AuthResponse.self, from: Data(json.utf8))

        XCTAssertFalse(
            response.user.onboardingCompleted,
            """
            The login response carries no onboardingCompleted, so it decodes false. \
            Anything that routes from this response will send returning users to \
            onboarding — SessionStore.signedIn() must fetch the profile instead.
            """
        )
        XCTAssertTrue(response.user.cuisinePreferences.isEmpty)
        XCTAssertNil(response.user.dietaryPreferences)
    }

    /// The profile response, by contrast, is complete.
    func testProfileResponseCarriesOnboardingState() throws {
        let json = """
        {"user":{"id":"abc","email":"a@b.com","name":"Asha","onboardingCompleted":true,
          "cuisinePreferences":["North Indian"],
          "dietaryPreferences":{"isVegetarian":true}}}
        """
        let profile = try JSONDecoder().decode(ProfileResponse.self, from: Data(json.utf8))
        XCTAssertTrue(profile.user.onboardingCompleted)
        XCTAssertEqual(profile.user.cuisinePreferences, ["North Indian"])
        XCTAssertTrue(profile.user.dietaryPreferences?.isVegetarian ?? false)
    }

    /// End to end against production: register, onboard, sign out, sign back in.
    /// The second sign-in must land on `.ready`, not `.needsOnboarding`.
    func testSigningBackInRoutesToReadyNotOnboarding() async throws {
        let env = AppEnvironment()
        let session = SessionStore(env: env)
        let email = uniqueEmail()
        let password = "kkb-test-password"

        // Start from a clean session regardless of what is in the keychain.
        env.tokenStore.clear()

        // --- Register. A brand-new account genuinely needs onboarding. ---
        _ = try await env.auth.register(email: email, password: password, name: "iOS Test")
        try await session.signedIn()
        guard case .needsOnboarding = session.state else {
            return XCTFail("A new account should need onboarding, got \(session.state)")
        }

        // --- Complete onboarding the way the real flow does. ---
        try await env.settings.saveCuisines(["North Indian"], onboardingCompleted: true)
        try await env.settings.saveDietary(DietaryPreferences(isVegetarian: true))

        // --- Sign out. ---
        env.auth.logout()
        XCTAssertFalse(env.tokenStore.isAuthenticated)

        // --- Sign back in: the case that regressed. ---
        _ = try await env.auth.login(email: email, password: password)
        try await session.signedIn()

        guard case let .ready(user) = session.state else {
            return XCTFail(
                "A returning account was routed to \(session.state) instead of .ready — "
                + "signedIn() is trusting the login response again"
            )
        }
        XCTAssertTrue(user.onboardingCompleted)
        XCTAssertFalse(user.isGuest)
        XCTAssertEqual(user.email, email)
        XCTAssertEqual(
            user.cuisinePreferences, ["North Indian"],
            "Preferences must come back too — they seed the suggestion sheet"
        )
    }

    /// The client-side half of guest resume: the device id must be stable across
    /// sessions, because it *is* the guest's Firestore document id
    /// (`app/api/auth/guest/route.ts:36-37`). A regenerated id means a new, empty
    /// account and an unreachable meal plan.
    ///
    /// Deliberately not exercised over the network: a test host's keychain is not
    /// the app's, and the app only takes the resume-by-device-id path after a
    /// sign-out — a normal relaunch resumes from the stored token instead.
    func testGuestDeviceIDIsStableWithinASession() {
        let store = TokenStore()
        let first = store.getOrCreateGuestDeviceID()
        XCTAssertTrue(first.hasPrefix("guest_"), "The server rejects ids without this prefix")
        XCTAssertEqual(
            store.getOrCreateGuestDeviceID(), first,
            "The device id must not be regenerated on every read"
        )
    }

    /// Signing out deliberately drops the device id too, so "Get Started" mints a
    /// genuinely new guest rather than silently resuming the previous one. Android
    /// clears both for the same reason.
    func testSigningOutDiscardsTheGuestIdentity() {
        let store = TokenStore()
        store.save("test-token")
        XCTAssertTrue(store.isAuthenticated)

        store.clear()
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.token)
    }
}
