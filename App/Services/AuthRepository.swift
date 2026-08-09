import Foundation
import KhanaKit

/// Auth flows. Every method that succeeds persists the returned token before
/// returning, so callers never have to remember to.
@MainActor
final class AuthRepository {
    private let api: APIClient
    private let tokenStore: TokenStore

    init(api: APIClient, tokenStore: TokenStore) {
        self.api = api
        self.tokenStore = tokenStore
    }

    func login(email: String, password: String) async throws -> User {
        let response = try await api.send(
            Endpoints.login(LoginRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )),
            as: AuthResponse.self
        )
        tokenStore.save(response.token)
        return response.user
    }

    func register(email: String, password: String, name: String) async throws -> User {
        let response = try await api.send(
            Endpoints.register(RegisterRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )),
            as: AuthResponse.self
        )
        tokenStore.save(response.token)
        return response.user
    }

    /// Anonymous account keyed to this install. The device id is stable across
    /// launches, so reinstalling is what loses a guest's plans — same as Android.
    func createGuest() async throws -> User {
        let deviceId = tokenStore.getOrCreateGuestDeviceID()
        let response = try await api.send(
            Endpoints.createGuest(GuestRequest(deviceId: deviceId)),
            as: AuthResponse.self
        )
        tokenStore.save(response.token)
        return response.user
    }

    /// Converts a guest into a registered account. The server creates a **new**
    /// user id and copies the meal plans across, then returns a new token — so the
    /// old one must be replaced, not kept alongside.
    func upgradeGuest(email: String, password: String, name: String) async throws -> User {
        let response = try await api.send(
            Endpoints.upgradeGuest(UpgradeGuestRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )),
            as: AuthResponse.self
        )
        tokenStore.save(response.token)
        return response.user
    }

    func fetchProfile() async throws -> User {
        try await api.send(Endpoints.profile, as: ProfileResponse.self).user
    }

    /// There is no server-side logout — the token is unsigned and non-revocable —
    /// so signing out is purely local.
    func logout() {
        tokenStore.clear()
    }
}
