import Foundation
import KhanaKit
import Security

/// Thin wrapper over the keychain for the session token.
///
/// Android keeps the token in a plaintext DataStore. The token is an unsigned,
/// non-expiring bearer credential that the server cannot revoke, so on iOS it goes
/// in the keychain — `kSecAttrAccessibleAfterFirstUnlock` because push handling can
/// wake the app in the background.
enum KeychainStore {
    private static let service = "in.khanakyabanau.app"

    static func string(for key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for key: String) -> Bool {
        guard let value, !value.isEmpty else { return delete(key) }
        let data = Data(value.utf8)

        // Update in place when it already exists, so we never briefly have no token.
        let updateStatus = SecItemUpdate(
            baseQuery(key: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var query = baseQuery(key: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// Owns the session token and the guest device id.
///
/// The in-memory mirror matters: `APIClient` reads the token synchronously while
/// building every request, and a keychain round trip per request would be wasteful.
/// Writes update the mirror first so a request fired immediately after login
/// already carries the new token — the same ordering Android's `TokenDataStore` uses.
@MainActor
@Observable
final class TokenStore {
    private enum Keys {
        static let token = "auth_token"
        static let guestDeviceId = "guest_device_id"
    }

    private(set) var token: String?

    /// Read by the networking layer from any isolation domain.
    nonisolated(unsafe) private static var cachedToken: String?

    /// UI tests pass `-KKBResetState` so each journey starts from a genuinely
    /// signed-out app. The keychain survives an app uninstall on the simulator,
    /// so there is no way to get a clean state from outside the process.
    static var isResetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-KKBResetState")
    }

    init() {
        if TokenStore.isResetRequested {
            KeychainStore.delete(Keys.token)
            KeychainStore.delete(Keys.guestDeviceId)
        }
        let stored = KeychainStore.string(for: Keys.token)
        token = stored
        TokenStore.cachedToken = stored
    }

    var isAuthenticated: Bool { !(token ?? "").isEmpty }

    func save(_ newToken: String) {
        TokenStore.cachedToken = newToken
        token = newToken
        KeychainStore.set(newToken, for: Keys.token)
    }

    /// Drops the token *and* the guest device id, so "Get Started" after a sign-out
    /// mints a fresh guest rather than silently resuming the previous one.
    func clear() {
        TokenStore.cachedToken = nil
        token = nil
        KeychainStore.delete(Keys.token)
        KeychainStore.delete(Keys.guestDeviceId)
    }

    /// A stable id for this install, created on first use.
    func getOrCreateGuestDeviceID() -> String {
        if let existing = KeychainStore.string(for: Keys.guestDeviceId), !existing.isEmpty {
            return existing
        }
        let generated = GuestDeviceID.generate()
        KeychainStore.set(generated, for: Keys.guestDeviceId)
        return generated
    }

    /// The token provider handed to `APIClient`.
    nonisolated static func currentToken() -> String? { cachedToken }
}
