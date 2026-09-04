import XCTest
@testable import KhanaKyaBanau

/// The token and the guest device id move into a shared keychain access group so
/// the widget extension can read them. An access group is part of a keychain
/// item's identity, not a filter over it, so every pre-existing item becomes
/// invisible the moment the group is added — the app would decide the whole
/// installed base is signed out.
///
/// Worse for guests: `guest_device_id` *is* their account. There is no password
/// to sign back in with, so losing it orphans their data permanently. That is the
/// case this file exists for.
final class KeychainMigrationTests: XCTestCase {

    /// Unique per run so a failed test cannot poison the next one, and so this
    /// never collides with a real token on a developer's machine.
    private var tokenKey = ""
    private var guestKey = ""

    override func setUp() {
        super.setUp()
        let suffix = UUID().uuidString
        tokenKey = "test_auth_token_\(suffix)"
        guestKey = "test_guest_device_id_\(suffix)"
    }

    override func tearDown() {
        KeychainStore.delete(tokenKey, accessGroup: KeychainStore.legacyAccessGroup)
        KeychainStore.delete(guestKey, accessGroup: KeychainStore.legacyAccessGroup)
        KeychainStore.delete(tokenKey, accessGroup: KeychainStore.sharedAccessGroup)
        KeychainStore.delete(guestKey, accessGroup: KeychainStore.sharedAccessGroup)
        super.tearDown()
    }

    /// Skips rather than fails where the entitlement is absent — a free Apple ID
    /// cannot provision a keychain access group, and the repo deliberately keeps
    /// the app installable there.
    ///
    /// Probes rather than checking `sharedAccessGroup != nil`. The group *string*
    /// is built from `AppIdentifierPrefix`, an Info.plist build variable that
    /// expands whether or not the entitlement is present, so its existence proves
    /// nothing. Only a round-trip proves the app may actually use the group.
    private func requireSharedGroup() throws -> String {
        guard let group = KeychainStore.sharedAccessGroup else {
            throw XCTSkip("No shared keychain access group configured.")
        }

        let canary = "entitlement_probe_\(UUID().uuidString)"
        defer { KeychainStore.delete(canary, accessGroup: group) }

        guard KeychainStore.set("1", for: canary, accessGroup: group),
              KeychainStore.string(for: canary, accessGroup: group) == "1"
        else {
            throw XCTSkip(
                "Not entitled to \(group). Build with "
                    + "KKB_ENTITLEMENTS=App/KhanaKyaBanau-Widgets.entitlements to exercise this."
            )
        }
        return group
    }

    func testATokenWrittenTheOldWayIsReadableAfterMigration() throws {
        let group = try requireSharedGroup()
        KeychainStore.set("old-token", for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertEqual(KeychainStore.string(for: tokenKey, accessGroup: group), "old-token")
    }

    /// The whole point. A guest has no credentials to recover with.
    func testAGuestDeviceIdSurvivesMigration() throws {
        let group = try requireSharedGroup()
        KeychainStore.set("guest-abc-123", for: guestKey, accessGroup: KeychainStore.legacyAccessGroup)

        KeychainStore.migrateToSharedAccessGroup(keys: [guestKey])

        XCTAssertEqual(KeychainStore.string(for: guestKey, accessGroup: group), "guest-abc-123")
    }

    /// Leaving the original behind would let a later downgrade resurrect a stale
    /// token, and leaves a credential in a group nothing reads.
    func testTheOldItemIsRemoved() throws {
        _ = try requireSharedGroup()
        KeychainStore.set("old-token", for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertNil(KeychainStore.string(for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup))
    }

    /// It runs on every launch, so the second run must be a no-op rather than
    /// overwriting a good token with the nothing it finds in the old group.
    func testMigratingTwiceKeepsTheValue() throws {
        let group = try requireSharedGroup()
        KeychainStore.set("old-token", for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])
        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertEqual(KeychainStore.string(for: tokenKey, accessGroup: group), "old-token")
    }

    /// A user who signed in after the update already has a shared-group item and
    /// nothing in the old group. The migration must not touch them.
    func testAnAlreadyMigratedUserIsUntouched() throws {
        let group = try requireSharedGroup()
        KeychainStore.set("new-token", for: tokenKey, accessGroup: group)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertEqual(KeychainStore.string(for: tokenKey, accessGroup: group), "new-token")
    }

    /// Both keys migrate independently: a signed-in user who was previously a
    /// guest has both, and neither may be dropped.
    func testBothKeysMigrateTogether() throws {
        let group = try requireSharedGroup()
        KeychainStore.set("old-token", for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup)
        KeychainStore.set("guest-abc-123", for: guestKey, accessGroup: KeychainStore.legacyAccessGroup)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey, guestKey])

        XCTAssertEqual(KeychainStore.string(for: tokenKey, accessGroup: group), "old-token")
        XCTAssertEqual(KeychainStore.string(for: guestKey, accessGroup: group), "guest-abc-123")
    }

    func testMigratingAKeyThatWasNeverSetIsHarmless() throws {
        let group = try requireSharedGroup()

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertNil(KeychainStore.string(for: tokenKey, accessGroup: group))
        XCTAssertNil(KeychainStore.string(for: tokenKey, accessGroup: KeychainStore.legacyAccessGroup))
    }
}
