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

    /// The group both the app and the widget extension can reach.
    ///
    /// `nil` when `AppIdentifierPrefix` is missing from the Info.plist, which is
    /// the normal state on a build without the entitlement — a free Apple ID
    /// cannot provision one, and the app stays installable there. Everything
    /// below then behaves exactly as it did before the widget existed.
    static let sharedAccessGroup: String? = {
        guard let group = teamPrefixed("in.khanakyabanau.shared") else { return nil }

        // Probe, do not assume. `AppIdentifierPrefix` is an Info.plist build
        // variable that expands whether or not the entitlement is present, so
        // the group *string* proves nothing about whether we may use it.
        //
        // Getting this wrong is not a degraded widget, it is a broken app: on an
        // unentitled build every write to the group fails silently, every read
        // returns nil, and `guestDeviceId` regenerates on each access — which
        // orphans a guest's plans on the very build a contributor without a paid
        // membership would be running. Falling back to nil keeps that path
        // behaving exactly as it did before the widget existed.
        let canary = "access_group_probe"
        defer { _ = delete(canary, accessGroup: group) }
        guard set("1", for: canary, accessGroup: group),
              string(for: canary, accessGroup: group) == "1"
        else { return nil }

        return group
    }()

    /// Where items written before the shared group existed still live.
    ///
    /// With no `kSecAttrAccessGroup`, iOS files an item under the app's default
    /// group, `<prefix><bundle id>`. Naming it explicitly matters more than it
    /// looks: **a query that omits the access group is not scoped to the default
    /// one, it searches every group the app can reach.** A group-less delete
    /// during migration therefore matches the copy just written into the shared
    /// group and removes it again — the migration silently undoing itself, and
    /// every user signed out exactly as if it had never run.
    static let legacyAccessGroup: String? = teamPrefixed("in.khanakyabanau.app")

    private static func teamPrefixed(_ group: String) -> String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty,
              !prefix.contains("$(")
        else { return nil }
        return "\(prefix)\(group)"
    }

    static func string(for key: String, accessGroup: String? = sharedAccessGroup) -> String? {
        var query = baseQuery(key: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(
        _ value: String?,
        for key: String,
        accessGroup: String? = sharedAccessGroup
    ) -> Bool {
        guard let value, !value.isEmpty else { return delete(key, accessGroup: accessGroup) }
        let data = Data(value.utf8)

        // Update in place when it already exists, so we never briefly have no token.
        let updateStatus = SecItemUpdate(
            baseQuery(key: key, accessGroup: accessGroup) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var query = baseQuery(key: key, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ key: String, accessGroup: String? = sharedAccessGroup) -> Bool {
        let status = SecItemDelete(baseQuery(key: key, accessGroup: accessGroup) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Move items written before the shared access group existed.
    ///
    /// **Why this is not optional.** A keychain item's access group is part of
    /// its identity, not a filter over it, so adding one makes every existing
    /// item invisible to every query: without this, shipping the widget signs out
    /// the entire installed base. For guests it is worse than a sign-out —
    /// `guest_device_id` *is* their account, there is no password to recover
    /// with, and their plans would be orphaned permanently.
    ///
    /// Idempotent by construction: it reads the *old* group-less item, and a
    /// second run finds nothing there and does nothing. That matters because it
    /// runs on every launch.
    ///
    /// **Deletable** once no install predating the widget release remains — in
    /// practice a few months after it ships, or immediately after a forced
    /// reinstall. It is written to be removed, not carried.
    static func migrateToSharedAccessGroup(keys: [String]) {
        guard let group = sharedAccessGroup else { return }

        guard let legacyGroup = legacyAccessGroup else { return }

        for key in keys {
            // Both sides named explicitly. See `legacyAccessGroup`: a group-less
            // query spans every reachable group, so `nil` here would read back
            // the item we just migrated and then delete it.
            guard let legacy = string(for: key, accessGroup: legacyGroup) else { continue }

            // Write first, delete second. The reverse order loses the credential
            // outright if the process dies between the two.
            guard set(legacy, for: key, accessGroup: group) else { continue }
            delete(key, accessGroup: legacyGroup)
        }
    }

    private static func baseQuery(key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
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
            // Also clear the pre-widget group, or a reset would leave items the
            // migration below would faithfully restore.
            KeychainStore.delete(Keys.token, accessGroup: KeychainStore.legacyAccessGroup)
            KeychainStore.delete(Keys.guestDeviceId, accessGroup: KeychainStore.legacyAccessGroup)
        }

        // Before the first read, always. A returning user's token lives in the
        // old group until this runs, and reading first would see nothing and
        // sign them out.
        KeychainStore.migrateToSharedAccessGroup(keys: [Keys.token, Keys.guestDeviceId])

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
