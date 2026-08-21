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

    /// Permanently deletes the account and everything it owns, then clears the
    /// local session.
    ///
    /// The token is dropped only after the server confirms. A wrong password or a
    /// dropped connection must leave the user signed in and able to try again —
    /// clearing first would strand them with no account *and* no way back in.
    ///
    /// `password` is nil for a guest, who has none to re-enter.
    func deleteAccount(password: String?) async throws {
        try await api.send(Endpoints.deleteAccount(DeleteAccountRequest(password: password)))
        tokenStore.clear()
    }

    /// There is no server-side logout — the token is unsigned and non-revocable —
    /// so signing out is purely local.
    func logout() {
        tokenStore.clear()
    }
}
