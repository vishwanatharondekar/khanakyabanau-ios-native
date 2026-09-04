# iOS Home Screen Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one time-aware home screen widget on iOS — today's menu before 17:00, tonight-plus-tomorrow after it — drawing on the same data as the two Glance widgets Android ships.

**Architecture:** One `StaticConfiguration` whose timeline entries are each stamped with the moment they become valid, so the evening pivot costs one reload rather than a clock read at render time. The app writes a snapshot (JSON plus 256px thumbnails) into an App Group container whenever a week covering today or tomorrow is loaded or saved; the widget extension always renders that snapshot, and tops it up from the network only when the snapshot is stale and a session token is readable. The snapshot model, its store and the timeline arithmetic live in `KhanaKit` so the app and the extension link one implementation and `swift test` covers them with no simulator.

**Tech Stack:** Swift 5.9, iOS 17 floor, SwiftUI, WidgetKit, XCTest, XcodeGen (`project.yml` is the source of truth; the `.xcodeproj` is generated and gitignored).

**Spec:** `docs/superpowers/specs/2026-09-04-ios-home-screen-widgets-design.md`

## Global Constraints

- **iOS 17.0 floor.** `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, and `KhanaKit` declares `.iOS(.v17)`, `.macOS(.v14)`.
- **`KhanaKit` is Foundation-only.** No SwiftUI, no UIKit, no WidgetKit in that target — that is what keeps `swift test` runnable without an iOS SDK. CryptoKit is permitted (it ships on both declared platforms).
- **A paid Apple Developer membership is required.** App Groups and keychain access groups are provisioned capabilities a free Apple ID cannot get. Entitlements go in files selected by build settings — `KKB_ENTITLEMENTS` (existing) and `KKB_WIDGET_ENTITLEMENTS` (new) — so the free-account install route in the README keeps working without the widget.
- **App Group id:** `group.in.khanakyabanau.app`
- **Keychain access group:** `in.khanakyabanau.shared`, prefixed at runtime with `AppIdentifierPrefix` read from `Info.plist`. Never hardcode the team id (`HL88YQFR35`) in Swift.
- **Extension bundle id:** `in.khanakyabanau.app.widgets`
- **One widget kind:** `"menu"`. Never change that string — it is the identity of every widget a user has already placed, and changing it orphans them. `StaticConfiguration` only: the widget picks its own day, so there is nothing left to configure.
- **The evening pivot is 17:00**, `WidgetPhase.eveningPivotMinutes`, the same value as `nominalMealTimes[.eveningSnack]`. A wall-clock constant, never derived from enabled meal types.
- **Timeline entries are capped at 12**, dropping the furthest-out prep boundaries first. `now`, the pivot and the next midnight are never dropped.
- **Copy, verbatim** — these match Android's strings so screenshots and support answers agree:
  - No snapshot or not authenticated: `Tap to set up`
  - Authenticated, no meals: `Open the app to pick meals`
  - Snapshot unreadable: `Couldn't load today's plan`
- **Thumbnails are 256px** (matching Android's Coil `.size(256)`).
- **Network timeouts in the extension:** 2s auth, 2s settings, 5s week — Android's values.
- **Snapshot staleness threshold:** 6 hours (Android's `WorkManager` cadence).
- **Every widget view sets `.containerBackground(for: .widget)`.** Without it the widget renders blank in StandBy and on iPad.
- **Calories follow the app's `showCalories` setting.** Android's widget ignores it; the app must not disagree with itself on one device.
- **The snapshot stores `meal.validPrep` only**, never raw `meal.prep`.
- **After adding or removing any file, run `xcodegen generate`.** The README warns that `-only-testing` against a target with unregenerated files reports `Executed 0 tests` and still exits successfully.
- **Commands:**
  - `cd KhanaKit && swift test` — the pure suite
  - `xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KhanaKyaBanauTests test`
  - Do not run the `KhanaKyaBanauUITests` target: those journeys create real guest accounts against production and consume a guest's three lifetime AI allowances.

---

## Phase A — Keychain (do this first)

This phase ships no widget. It is first because it is the only irreversible part of the change: getting it wrong signs out every existing user, and guests — whose account is reachable only through `guest_device_id` — are orphaned permanently.

### Task 1: Keychain access group and the one-time migration

**Files:**
- Modify: `App/Core/KeychainStore.swift`
- Modify: `App/Info.plist`
- Create: `App/KhanaKyaBanau-Widgets.entitlements`
- Modify: `project.yml`
- Test: `AppTests/KeychainMigrationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `KeychainStore.string(for: String, accessGroup: String?) -> String?`
  - `KeychainStore.set(_ value: String?, for: String, accessGroup: String?) -> Bool`
  - `KeychainStore.delete(_ key: String, accessGroup: String?) -> Bool`
  - `KeychainStore.sharedAccessGroup: String?` — the full prefixed group, `nil` when `AppIdentifierPrefix` is missing
  - `KeychainStore.migrateToSharedAccessGroup(keys: [String])`
  - Existing three-argument-free call sites keep working: the `accessGroup:` parameter defaults to `sharedAccessGroup`.

- [ ] **Step 1: Write the failing test**

Create `AppTests/KeychainMigrationTests.swift`:

```swift
import XCTest
@testable import KhanaKyaBanau

/// Adding `kSecAttrAccessGroup` changes a keychain item's identity: the query that
/// used to find the token stops finding it, and the app concludes the user is
/// signed out. Guests are worse off — their account is only reachable through
/// `guest_device_id`, so losing it orphans them permanently. This is the test that
/// says the migration moves both.
@MainActor
final class KeychainMigrationTests: XCTestCase {

    private let tokenKey = "auth_token"
    private let guestKey = "guest_device_id"

    override func setUp() {
        super.setUp()
        wipe()
    }

    override func tearDown() {
        wipe()
        super.tearDown()
    }

    private func wipe() {
        KeychainStore.delete(tokenKey, accessGroup: nil)
        KeychainStore.delete(guestKey, accessGroup: nil)
        if let shared = KeychainStore.sharedAccessGroup {
            KeychainStore.delete(tokenKey, accessGroup: shared)
            KeychainStore.delete(guestKey, accessGroup: shared)
        }
    }

    /// The entitlement has to actually be provisioned for this build, or every
    /// shared-group `SecItem` call fails with errSecMissingEntitlement (-34018).
    /// That is a build-configuration failure, not a logic one, so say which.
    private func requireSharedGroup() throws -> String {
        guard let shared = KeychainStore.sharedAccessGroup else {
            throw XCTSkip(
                "AppIdentifierPrefix is missing from Info.plist — see Task 1 Step 3"
            )
        }
        guard KeychainStore.set("probe", for: "migration_probe", accessGroup: shared) else {
            XCTFail(
                """
                Could not write to keychain access group \(shared). If SecItem is \
                returning -34018, the keychain-access-groups entitlement is not in \
                this build's entitlements file — see Task 1 Steps 4 and 5.
                """
            )
            throw XCTSkip("entitlement not provisioned")
        }
        KeychainStore.delete("migration_probe", accessGroup: shared)
        return shared
    }

    func testMigrationMovesTheTokenIntoTheSharedGroup() throws {
        let shared = try requireSharedGroup()
        KeychainStore.set("legacy-token", for: tokenKey, accessGroup: nil)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertEqual(
            KeychainStore.string(for: tokenKey, accessGroup: shared), "legacy-token",
            "the token did not arrive in the shared group — every user is now signed out"
        )
        XCTAssertNil(
            KeychainStore.string(for: tokenKey, accessGroup: nil),
            "the legacy item was left behind; the next migration would overwrite newer state"
        )
    }

    func testMigrationMovesTheGuestDeviceId() throws {
        let shared = try requireSharedGroup()
        KeychainStore.set("guest_abc_123456789", for: guestKey, accessGroup: nil)

        KeychainStore.migrateToSharedAccessGroup(keys: [guestKey])

        XCTAssertEqual(
            KeychainStore.string(for: guestKey, accessGroup: shared), "guest_abc_123456789",
            "the guest device id was lost — that guest's account is now unreachable"
        )
    }

    /// Runs on every launch, so it must be harmless when there is nothing to do and
    /// must never clobber a value already in the shared group.
    func testMigrationIsIdempotentAndNeverOverwritesNewerState() throws {
        let shared = try requireSharedGroup()
        KeychainStore.set("current-token", for: tokenKey, accessGroup: shared)
        KeychainStore.set("stale-token", for: tokenKey, accessGroup: nil)

        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])
        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey])

        XCTAssertEqual(
            KeychainStore.string(for: tokenKey, accessGroup: shared), "current-token",
            "migration overwrote a live token with a stale legacy one"
        )
    }

    func testMigrationWithNothingStoredDoesNothing() throws {
        let shared = try requireSharedGroup()
        KeychainStore.migrateToSharedAccessGroup(keys: [tokenKey, guestKey])
        XCTAssertNil(KeychainStore.string(for: tokenKey, accessGroup: shared))
        XCTAssertNil(KeychainStore.string(for: guestKey, accessGroup: shared))
    }
}
```

- [ ] **Step 2: Run the test and watch it fail to build**

```bash
cd /Users/vishwanatharondekar/projects/khanakyabanau-ios-native
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests/KeychainMigrationTests test 2>&1 | grep -E "error:|Executed"
```

Expected: compile errors — `extra argument 'accessGroup' in call`, and `type 'KeychainStore' has no member 'sharedAccessGroup'` / `'migrateToSharedAccessGroup'`.

- [ ] **Step 3: Add `AppIdentifierPrefix` to `App/Info.plist`**

`kSecAttrAccessGroup` needs the full `<TeamID>.<group>` string. Reading the prefix from the bundle keeps the team id out of Swift, so a different signing team still works.

Add inside the top-level `<dict>`:

```xml
	<key>AppIdentifierPrefix</key>
	<string>$(AppIdentifierPrefix)</string>
```

- [ ] **Step 4: Create `App/KhanaKyaBanau-Widgets.entitlements`**

This is the paid-membership variant, following the existing `KhanaKyaBanau-Push.entitlements` pattern. It carries both capabilities the widget needs.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!--
	  Requires a paid Apple Developer Program membership. App Groups and keychain
	  access groups are both provisioned capabilities; a free Apple ID gets
	  neither, and without a shared container there is no way to hand the widget
	  extension any data at all.

	  Selected by KKB_ENTITLEMENTS in project.yml. The free-account install route
	  in the README keeps working with the empty KhanaKyaBanau.entitlements, minus
	  the widget.
	-->
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.in.khanakyabanau.app</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)in.khanakyabanau.shared</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 5: Point the app target at it in `project.yml`**

In `targets.KhanaKyaBanau.settings.base`, replace the `KKB_ENTITLEMENTS` line with:

```yaml
        # Widgets need App Groups + keychain sharing, both of which require a paid
        # membership. Swap back to App/KhanaKyaBanau.entitlements for a
        # free-account device install (the widget will not work, the app will).
        KKB_ENTITLEMENTS: App/KhanaKyaBanau-Widgets.entitlements
```

- [ ] **Step 6: Implement the access group support and the migration**

In `App/Core/KeychainStore.swift`, replace `baseQuery` and thread the parameter through:

```swift
enum KeychainStore {
    private static let service = "in.khanakyabanau.app"

    /// The group the app and the widget extension share.
    ///
    /// The suffix is fixed; the `AppIdentifierPrefix` half comes from the bundle so
    /// the team id is never hardcoded. `nil` when the key is missing, which means
    /// every call falls back to the app's default group — the pre-widget behaviour.
    static let sharedAccessGroup: String? = {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix")
                as? String, !prefix.isEmpty, !prefix.hasPrefix("$(")
        else { return nil }
        return prefix + "in.khanakyabanau.shared"
    }()

    static func string(
        for key: String,
        accessGroup: String? = sharedAccessGroup
    ) -> String? {
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
    static func delete(
        _ key: String,
        accessGroup: String? = sharedAccessGroup
    ) -> Bool {
        let status = SecItemDelete(
            baseQuery(key: key, accessGroup: accessGroup) as CFDictionary
        )
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Moves pre-widget items into the shared group, once, on launch.
    ///
    /// Adding `kSecAttrAccessGroup` changes an item's identity, so without this
    /// every installed user's token becomes invisible and the app decides they are
    /// signed out. Runs on every launch and must therefore be idempotent: an item
    /// already in the shared group wins, because it is the live one and the legacy
    /// copy is whatever was there before the update.
    static func migrateToSharedAccessGroup(keys: [String]) {
        guard let shared = sharedAccessGroup else { return }
        for key in keys {
            guard string(for: key, accessGroup: shared) == nil,
                  let legacy = string(for: key, accessGroup: nil)
            else { continue }
            guard set(legacy, for: key, accessGroup: shared) else { continue }
            delete(key, accessGroup: nil)
        }
    }

    private static func baseQuery(key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
```

- [ ] **Step 7: Call the migration from `TokenStore.init`, before the first read**

In the same file, in `TokenStore.init()`:

```swift
    init() {
        if TokenStore.isResetRequested {
            // Both groups: a reset has to clear whatever the previous build left.
            KeychainStore.delete(Keys.token, accessGroup: nil)
            KeychainStore.delete(Keys.guestDeviceId, accessGroup: nil)
            KeychainStore.delete(Keys.token)
            KeychainStore.delete(Keys.guestDeviceId)
        }
        // Before the first read, or a returning user reads an empty keychain and
        // gets treated as signed out.
        KeychainStore.migrateToSharedAccessGroup(
            keys: [Keys.token, Keys.guestDeviceId]
        )
        let stored = KeychainStore.string(for: Keys.token)
        token = stored
        TokenStore.cachedToken = stored
    }
```

- [ ] **Step 8: Run the tests and watch them pass**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests/KeychainMigrationTests test 2>&1 | grep -E "Test Case|error:|Executed"
```

Expected: 4 tests pass. If they skip with "entitlement not provisioned", Steps 4–5 are not in effect — check that `xcodegen generate` ran and that the build log shows `App/KhanaKyaBanau-Widgets.entitlements`.

- [ ] **Step 9: Run the whole unit suite**

```bash
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
```

Expected: 70 tests, 0 failures (66 before, 4 added).

- [ ] **Step 10: Verify a real returning user is not signed out**

The tests exercise the migration directly; this exercises the launch path.

1. `git stash` this task's changes, build and run, sign in, confirm you are signed in.
2. `git stash pop`, rebuild and run **without** deleting the app.
3. You must still be signed in. If you land on Welcome, the migration is not running before the first read — recheck Step 7.

- [ ] **Step 11: Commit**

```bash
git add App/Core/KeychainStore.swift App/Info.plist \
  App/KhanaKyaBanau-Widgets.entitlements project.yml \
  AppTests/KeychainMigrationTests.swift
git commit -m "feat: share the keychain with the widget extension, and migrate into it"
```

---

## Phase B — Shared foundations in KhanaKit

Everything here runs under `swift test` with no simulator.

### Task 2: The snapshot model and its builder

**Files:**
- Create: `KhanaKit/Sources/KhanaKit/Models/WidgetSnapshot.swift`
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `MealPlan`, `DayMeals`, `Meal`, `MealType`, `DayOfWeek`, `MealPrep`, `PlanDate`, `WeekDates` — all existing.
- Produces:
  - `WidgetSnapshot(version:isAuthenticated:writtenAt:days:)`, `.currentVersion = 1`
  - `WidgetSnapshot.unauthenticated(writtenAt: Date) -> WidgetSnapshot`
  - `WidgetSnapshot.build(today:todayPlan:tomorrowPlan:enabledTypes:showCalories:thumbnailKey:writtenAt:) -> WidgetSnapshot`
  - `WidgetSnapshot.day(_ day: DayOfWeek) -> WidgetDay?`
  - `WidgetSnapshot.isStale(now: Date, maxAge: TimeInterval = 6 * 3600) -> Bool`
  - `WidgetDay(day:date:meals:)`, `WidgetMeal(type:name:calories:thumbnailKey:prep:)`

- [ ] **Step 1: Write the failing test**

Create `KhanaKit/Tests/KhanaKitTests/WidgetSnapshotTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// The snapshot is the whole contract between the app and the widget extension —
/// two processes, and after an app update, possibly two different binaries. These
/// pin the shape, the day resolution and the two filters the writer applies.
final class WidgetSnapshotTests: XCTestCase {

    private let writtenAt = Date(timeIntervalSince1970: 1_788_000_000)

    /// 2026-08-03 is a Monday, so 2026-08-09 is the Sunday of that week.
    private func planWithMeals(week: String) -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["monday"] = DayMeals(
            breakfast: Meal(name: "Poha", imageUrl: "https://cdn.example/poha.jpg", calories: 300),
            lunch: Meal(
                name: "Rajma",
                calories: 500,
                prep: MealPrep(
                    steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
                    maxLeadTimeMinutes: 480
                ),
                prepFor: "Rajma"
            )
        )
        return plan
    }

    private func build(
        today: PlanDate,
        todayPlan: MealPlan,
        tomorrowPlan: MealPlan? = nil,
        enabledTypes: [MealType] = [.breakfast, .lunch, .dinner],
        showCalories: Bool = true
    ) -> WidgetSnapshot {
        WidgetSnapshot.build(
            today: today,
            todayPlan: todayPlan,
            tomorrowPlan: tomorrowPlan ?? todayPlan,
            enabledTypes: enabledTypes,
            showCalories: showCalories,
            thumbnailKey: { url in "key-for-\(url)" },
            writtenAt: writtenAt
        )
    }

    func testCodecRoundTripsEverySupportedShape() throws {
        let snapshot = WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: writtenAt,
            days: [
                WidgetDay(day: .monday, date: "2026-08-03", meals: [
                    WidgetMeal(type: .breakfast, name: "Poha",
                               calories: 300, thumbnailKey: "abc", prep: nil),
                    // No calories, no thumbnail, no prep — the common case for a
                    // dish the user just typed.
                    WidgetMeal(type: .lunch, name: "Dal",
                               calories: nil, thumbnailKey: nil, prep: nil),
                ]),
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testBuildKeepsOnlyEnabledTypesInCanonicalOrder() {
        let snapshot = build(
            today: PlanDate(iso: "2026-08-03")!,
            todayPlan: planWithMeals(week: "2026-08-03"),
            enabledTypes: [.dinner, .breakfast]
        )

        XCTAssertEqual(
            snapshot.day(.monday)?.meals.map(\.type), [.breakfast, .dinner],
            "order must be canonical, not the order enabledTypes happened to arrive in"
        )
    }

    func testBuildResolvesTodayAndTomorrow() {
        let snapshot = build(
            today: PlanDate(iso: "2026-08-03")!,
            todayPlan: planWithMeals(week: "2026-08-03")
        )

        XCTAssertEqual(snapshot.days.map(\.day), [.monday, .tuesday])
        XCTAssertEqual(snapshot.days.map(\.date), ["2026-08-03", "2026-08-04"])
    }

    /// The Sunday→Monday case Android calls out in `loadTomorrowSnapshot`: tomorrow
    /// belongs to *next* week's plan, so the builder must read it from the second
    /// plan rather than looking up "monday" in this week's.
    func testBuildTakesTomorrowFromNextWeekAcrossASundayRollover() {
        var nextWeek = MealPlan.empty(weekStartDate: "2026-08-10")
        nextWeek.meals["monday"] = DayMeals(breakfast: Meal(name: "Next week's poha"))

        let snapshot = build(
            today: PlanDate(iso: "2026-08-09")!,          // Sunday
            todayPlan: planWithMeals(week: "2026-08-03"),
            tomorrowPlan: nextWeek
        )

        XCTAssertEqual(snapshot.days.map(\.day), [.sunday, .monday])
        XCTAssertEqual(snapshot.days.map(\.date), ["2026-08-09", "2026-08-10"])
        XCTAssertEqual(
            snapshot.day(.monday)?.meals.first?.name, "Next week's poha",
            "tomorrow was read out of this week's plan instead of next week's"
        )
    }

    func testBuildStoresThumbnailKeysNotURLs() {
        let snapshot = build(
            today: PlanDate(iso: "2026-08-03")!,
            todayPlan: planWithMeals(week: "2026-08-03")
        )
        let breakfast = snapshot.day(.monday)?.meals.first { $0.type == .breakfast }

        XCTAssertEqual(breakfast?.thumbnailKey, "key-for-https://cdn.example/poha.jpg")
    }

    func testBuildDropsCaloriesWhenTheUserHasThemSwitchedOff() {
        let snapshot = build(
            today: PlanDate(iso: "2026-08-03")!,
            todayPlan: planWithMeals(week: "2026-08-03"),
            showCalories: false
        )

        XCTAssertNil(
            snapshot.day(.monday)?.meals.first?.calories,
            "the widget must not show what the app is hiding on the same device"
        )
    }

    /// A dish edited since prep was generated has prep that no longer applies. The
    /// validity check belongs on the writing side, so the extension never has to
    /// make this judgement.
    func testBuildStoresValidPrepOnly() {
        var plan = MealPlan.empty(weekStartDate: "2026-08-03")
        plan.meals["monday"] = DayMeals(
            lunch: Meal(
                name: "Chole",                        // renamed since generation
                prep: MealPrep(
                    steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
                    maxLeadTimeMinutes: 480
                ),
                prepFor: "Rajma"
            )
        )

        let snapshot = build(today: PlanDate(iso: "2026-08-03")!, todayPlan: plan)

        XCTAssertNil(
            snapshot.day(.monday)?.meals.first { $0.type == .lunch }?.prep,
            "prep for a dish that has since been swapped reached the snapshot"
        )
    }

    func testStalenessIsMeasuredAgainstWrittenAt() {
        let snapshot = WidgetSnapshot.unauthenticated(writtenAt: writtenAt)

        XCTAssertFalse(snapshot.isStale(now: writtenAt.addingTimeInterval(5 * 3600)))
        XCTAssertTrue(snapshot.isStale(now: writtenAt.addingTimeInterval(7 * 3600)))
    }

    func testUnauthenticatedSnapshotCarriesNoDays() {
        let snapshot = WidgetSnapshot.unauthenticated(writtenAt: writtenAt)

        XCTAssertFalse(snapshot.isAuthenticated)
        XCTAssertTrue(snapshot.days.isEmpty)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetSnapshotTests 2>&1 | tail -20
```

Expected: `error: cannot find 'WidgetSnapshot' in scope`.

- [ ] **Step 3: Implement the model**

Create `KhanaKit/Sources/KhanaKit/Models/WidgetSnapshot.swift`:

```swift
import Foundation

/// Everything the home screen widgets need for today and tomorrow, in one file
/// the app writes and the extension reads.
///
/// This is a cross-process, cross-binary contract: after an app update the
/// extension can be asked for a timeline before it has been relaunched, so it can
/// read a snapshot written by a newer app. Hence [version] — an unrecognised
/// version reads as "no snapshot", which renders the setup shell rather than
/// something wrong.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    /// Matches Android's `WorkManager` refresh cadence.
    public static let defaultMaxAge: TimeInterval = 6 * 3600

    public var version: Int
    public var isAuthenticated: Bool
    public var writtenAt: Date
    public var days: [WidgetDay]

    public init(
        version: Int = WidgetSnapshot.currentVersion,
        isAuthenticated: Bool,
        writtenAt: Date,
        days: [WidgetDay]
    ) {
        self.version = version
        self.isAuthenticated = isAuthenticated
        self.writtenAt = writtenAt
        self.days = days
    }

    public static func unauthenticated(writtenAt: Date) -> WidgetSnapshot {
        WidgetSnapshot(isAuthenticated: false, writtenAt: writtenAt, days: [])
    }

    public func day(_ day: DayOfWeek) -> WidgetDay? {
        days.first { $0.day == day }
    }

    public func isStale(
        now: Date,
        maxAge: TimeInterval = WidgetSnapshot.defaultMaxAge
    ) -> Bool {
        now.timeIntervalSince(writtenAt) > maxAge
    }

    /// Builds the snapshot from resolved plans.
    ///
    /// Takes both plans rather than fetching: on a Sunday, tomorrow is the Monday
    /// of the *next* week and lives in a different `MealPlan`. Callers that are not
    /// straddling a week boundary pass the same plan twice.
    ///
    /// Pure, so the day arithmetic and the two filters below are testable without a
    /// network or a container.
    public static func build(
        today: PlanDate,
        todayPlan: MealPlan,
        tomorrowPlan: MealPlan,
        enabledTypes: [MealType],
        showCalories: Bool,
        thumbnailKey: (String) -> String?,
        writtenAt: Date
    ) -> WidgetSnapshot {
        let tomorrow = today.adding(days: 1)
        return WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: writtenAt,
            days: [
                day(tomorrow: false, date: today, plan: todayPlan,
                    enabledTypes: enabledTypes, showCalories: showCalories,
                    thumbnailKey: thumbnailKey),
                day(tomorrow: true, date: tomorrow, plan: tomorrowPlan,
                    enabledTypes: enabledTypes, showCalories: showCalories,
                    thumbnailKey: thumbnailKey),
            ]
        )
    }

    private static func day(
        tomorrow: Bool,
        date: PlanDate,
        plan: MealPlan,
        enabledTypes: [MealType],
        showCalories: Bool,
        thumbnailKey: (String) -> String?
    ) -> WidgetDay {
        let dayOfWeek = date.dayOfWeek
        let meals = plan.meals(for: dayOfWeek)
        return WidgetDay(
            day: dayOfWeek,
            date: date.isoString,
            // Canonical order rather than the caller's list, so output order is
            // stable however `enabledTypes` was assembled — the same rule the prep
            // selectors follow.
            meals: MealType.allCases
                .filter { enabledTypes.contains($0) }
                .map { type in
                    let meal = meals[type]
                    return WidgetMeal(
                        type: type,
                        name: meal.name,
                        calories: showCalories ? meal.calories : nil,
                        thumbnailKey: meal.imageUrl.flatMap(thumbnailKey),
                        // `validPrep`, never `prep`: a dish edited since generation
                        // carries prep that no longer applies, and the extension
                        // must not have to know that.
                        prep: meal.validPrep
                    )
                }
        )
    }
}

public struct WidgetDay: Codable, Hashable, Sendable {
    public var day: DayOfWeek
    /// ISO, so a day rollover is detectable by the reader.
    public var date: String
    public var meals: [WidgetMeal]

    public init(day: DayOfWeek, date: String, meals: [WidgetMeal]) {
        self.day = day
        self.date = date
        self.meals = meals
    }

    /// Whether anything is actually written for this day — an all-empty day gets
    /// the "Open the app to pick meals" shell, not a list of dashes.
    public var hasAnyMeal: Bool {
        meals.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct WidgetMeal: Codable, Hashable, Sendable {
    public var type: MealType
    public var name: String
    public var calories: Int?
    /// A file name inside the container, never a URL. The extension must never be
    /// the thing that discovers it has to download an image.
    public var thumbnailKey: String?
    public var prep: MealPrep?

    public init(
        type: MealType,
        name: String,
        calories: Int?,
        thumbnailKey: String?,
        prep: MealPrep?
    ) {
        self.type = type
        self.name = name
        self.calories = calories
        self.thumbnailKey = thumbnailKey
        self.prep = prep
    }

    public var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
cd KhanaKit && swift test --filter WidgetSnapshotTests 2>&1 | grep -E "Executed|error:"
```

Expected: 9 tests, 0 failures.

- [ ] **Step 5: Run the whole pure suite**

```bash
cd KhanaKit && swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:"
```

Expected: 236 tests, 0 failures (227 before, 9 added).

- [ ] **Step 6: Commit**

```bash
git add KhanaKit/Sources/KhanaKit/Models/WidgetSnapshot.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetSnapshotTests.swift
git commit -m "feat: add the widget snapshot model shared by the app and the extension"
```

### Task 3: The container and the snapshot store

**Files:**
- Create: `KhanaKit/Sources/KhanaKit/Networking/WidgetContainer.swift`
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot` from Task 2.
- Produces:
  - `WidgetContainer.appGroupID = "group.in.khanakyabanau.app"`
  - `WidgetContainer(root: URL)`, `.shared() -> WidgetContainer?`
  - `.snapshotURL`, `.thumbnailsDirectory`, `.thumbnailURL(key:)`
  - `WidgetSnapshotStore.write(_:to:) throws`
  - `WidgetSnapshotStore.read(from:) -> WidgetSnapshot?`
  - `WidgetSnapshotStore.writeThumbnail(_:key:to:) throws`
  - `WidgetSnapshotStore.thumbnailData(key:in:) -> Data?`
  - `WidgetSnapshotStore.pruneThumbnails(keeping:in:)`
  - `WidgetSnapshotStore.thumbnailKey(forImageURL:) -> String`

- [ ] **Step 1: Write the failing test**

Create `KhanaKit/Tests/KhanaKitTests/WidgetSnapshotStoreTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// The store is read by a different process than writes it, and a read can land
/// mid-write. These pin the atomicity, the nil-not-throw reads, and the pruning
/// that stops the container growing for ever.
final class WidgetSnapshotStoreTests: XCTestCase {

    private var container: WidgetContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("widget-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = WidgetContainer(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container.root)
        container = nil
        try super.tearDownWithError()
    }

    private func snapshot(writtenAt: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: writtenAt,
            days: [WidgetDay(day: .monday, date: "2026-08-03", meals: [
                WidgetMeal(type: .lunch, name: "Rajma",
                           calories: 500, thumbnailKey: "abc", prep: nil),
            ])]
        )
    }

    func testWriteThenReadRoundTrips() throws {
        let written = snapshot()
        try WidgetSnapshotStore.write(written, to: container)

        XCTAssertEqual(WidgetSnapshotStore.read(from: container), written)
    }

    func testWritingTwiceReplacesRatherThanAppends() throws {
        try WidgetSnapshotStore.write(snapshot(writtenAt: Date(timeIntervalSince1970: 1)), to: container)
        let second = snapshot(writtenAt: Date(timeIntervalSince1970: 2))
        try WidgetSnapshotStore.write(second, to: container)

        XCTAssertEqual(WidgetSnapshotStore.read(from: container), second)
    }

    /// A widget that renders an error where it could render an invitation is a worse
    /// widget, so absence is not an error.
    func testReadingAnAbsentSnapshotReturnsNil() {
        XCTAssertNil(WidgetSnapshotStore.read(from: container))
    }

    func testReadingGarbageReturnsNilRatherThanThrowing() throws {
        try Data("not json".utf8).write(to: container.snapshotURL)

        XCTAssertNil(WidgetSnapshotStore.read(from: container))
    }

    /// An extension from an older app build can be handed a newer snapshot.
    func testReadingAFutureVersionReturnsNil() throws {
        var future = snapshot()
        future.version = WidgetSnapshot.currentVersion + 1
        try WidgetSnapshotStore.write(future, to: container)

        XCTAssertNil(
            WidgetSnapshotStore.read(from: container),
            "a snapshot from a newer app was decoded by an older extension"
        )
    }

    func testThumbnailsRoundTrip() throws {
        let key = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/poha.jpg")
        try WidgetSnapshotStore.writeThumbnail(Data([0x01, 0x02]), key: key, to: container)

        XCTAssertEqual(
            WidgetSnapshotStore.thumbnailData(key: key, in: container), Data([0x01, 0x02])
        )
    }

    func testThumbnailKeysAreStableAndFilesystemSafe() {
        let a = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/a b/c?d=1&e=2")
        let b = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/a b/c?d=1&e=2")

        XCTAssertEqual(a, b, "the same URL must map to the same file every time")
        XCTAssertNotEqual(
            a, WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/other.jpg")
        )
        XCTAssertNil(
            a.rangeOfCharacter(from: CharacterSet.alphanumerics.union(.init(charactersIn: ".")).inverted),
            "key \(a) contains a character that cannot go in a file name"
        )
    }

    func testPruningKeepsReferencedThumbnailsAndDeletesTheRest() throws {
        let keep = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/keep.jpg")
        let drop = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/drop.jpg")
        try WidgetSnapshotStore.writeThumbnail(Data([0x01]), key: keep, to: container)
        try WidgetSnapshotStore.writeThumbnail(Data([0x02]), key: drop, to: container)

        WidgetSnapshotStore.pruneThumbnails(keeping: [keep], in: container)

        XCTAssertNotNil(WidgetSnapshotStore.thumbnailData(key: keep, in: container))
        XCTAssertNil(
            WidgetSnapshotStore.thumbnailData(key: drop, in: container),
            "an unreferenced thumbnail was left behind; the container grows for ever"
        )
    }

    func testPruningAnEmptyContainerDoesNotThrow() {
        WidgetSnapshotStore.pruneThumbnails(keeping: [], in: container)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetSnapshotStoreTests 2>&1 | tail -20
```

Expected: `error: cannot find 'WidgetContainer' in scope`.

- [ ] **Step 3: Implement the container and store**

Create `KhanaKit/Sources/KhanaKit/Networking/WidgetContainer.swift`:

```swift
import CryptoKit
import Foundation

/// Where the app and the widget extension meet: a directory in the shared App
/// Group container holding one snapshot file and a thumbnail per dish photo.
public struct WidgetContainer: Hashable, Sendable {
    public static let appGroupID = "group.in.khanakyabanau.app"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `nil` when the App Group is not provisioned — a free-account build, which
    /// has no widget. Callers treat that exactly as they treat an absent snapshot.
    public static func shared(
        appGroupID: String = WidgetContainer.appGroupID
    ) -> WidgetContainer? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            .map { WidgetContainer(root: $0) }
    }

    public var snapshotURL: URL {
        root.appendingPathComponent("snapshot.json", isDirectory: false)
    }

    public var thumbnailsDirectory: URL {
        root.appendingPathComponent("thumbnails", isDirectory: true)
    }

    public func thumbnailURL(key: String) -> URL {
        thumbnailsDirectory.appendingPathComponent(key, isDirectory: false)
    }
}

/// Reads and writes the snapshot. Every read is failure-tolerant by design: the
/// extension has no way to recover from a bad file, and "no snapshot" renders a
/// useful shell whereas a thrown error renders nothing.
public enum WidgetSnapshotStore {

    public static func write(_ snapshot: WidgetSnapshot, to container: WidgetContainer) throws {
        try FileManager.default.createDirectory(
            at: container.root, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)

        // Atomic: a render can happen mid-write, and a half-written file would read
        // as garbage. `.atomic` writes to a temporary neighbour and renames.
        try data.write(to: container.snapshotURL, options: .atomic)
    }

    public static func read(from container: WidgetContainer) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: container.snapshotURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              // An extension from an older build can be handed a snapshot written by
              // a newer app. Refusing it shows the setup shell, which is wrong but
              // harmless; guessing at unknown fields would show something false.
              snapshot.version <= WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    public static func writeThumbnail(
        _ data: Data,
        key: String,
        to container: WidgetContainer
    ) throws {
        try FileManager.default.createDirectory(
            at: container.thumbnailsDirectory, withIntermediateDirectories: true
        )
        try data.write(to: container.thumbnailURL(key: key), options: .atomic)
    }

    public static func thumbnailData(key: String, in container: WidgetContainer) -> Data? {
        try? Data(contentsOf: container.thumbnailURL(key: key))
    }

    /// Deletes thumbnails the current snapshot no longer references, so a year of
    /// changing menus cannot fill the container.
    public static func pruneThumbnails(keeping keys: Set<String>, in container: WidgetContainer) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(
            atPath: container.thumbnailsDirectory.path
        ) else { return }
        for name in names where !keys.contains(name) {
            try? manager.removeItem(at: container.thumbnailURL(key: name))
        }
    }

    /// A stable, filesystem-safe file name for a dish photo URL.
    ///
    /// Hashed rather than escaped: these URLs carry query strings and spaces, and a
    /// percent-escaped URL is both unreadable and long enough to risk the path
    /// limit. 32 hex characters of SHA-256 is ample for a handful of files.
    public static func thumbnailKey(forImageURL url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32)) + ".jpg"
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
cd KhanaKit && swift test --filter WidgetSnapshotStoreTests 2>&1 | grep -E "Executed|error:"
```

Expected: 10 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add KhanaKit/Sources/KhanaKit/Networking/WidgetContainer.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetSnapshotStoreTests.swift
git commit -m "feat: add the shared-container snapshot store"
```

### Task 4: The evening pivot, remaining meals, and timeline entry dates

**Files:**
- Create: `KhanaKit/Sources/KhanaKit/Logic/WidgetPhase.swift`
- Create: `KhanaKit/Sources/KhanaKit/Logic/WidgetTimeline.swift`
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetPhaseTests.swift`
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetTimelineTests.swift`

**Interfaces:**
- Consumes: `PrepTonight.nominalMealTimes`, `WidgetMeal` (Task 2).
- Produces:
  - `WidgetPhase.eveningPivotMinutes = 17 * 60`
  - `WidgetPhase.Phase` — `.today`, `.eveningAndTomorrow`
  - `WidgetPhase.pivotDate(onDayOf: Date, calendar: Calendar) -> Date`
  - `WidgetPhase.phase(at: Date, calendar: Calendar) -> Phase`
  - `WidgetPhase.remainingMeals(_ meals: [WidgetMeal], at: Date, calendar: Calendar) -> [WidgetMeal]`
  - `WidgetTimeline.entryDates(startingAt:extraBoundaries:calendar:limit:) -> [Date]`
  - `WidgetTimeline.nextMidnight(after:calendar:) -> Date`

- [ ] **Step 1: Write the failing test for the pivot**

Create `KhanaKit/Tests/KhanaKitTests/WidgetPhaseTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// The widget decides its own day: today's plan until 17:00, then tonight plus
/// tomorrow. These pin the boundary and — the reason this is not one line of
/// arithmetic — the two days a year when a naive `startOfDay + 17h` is wrong.
final class WidgetPhaseTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ iso: String, _ calendar: Calendar) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testTheMorningShowsToday() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.phase(at: date("2026-09-04T08:00:00+05:30", calendar), calendar: calendar),
            .today
        )
    }

    func testTheBoundaryItselfIsAlreadyEvening() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.phase(at: date("2026-09-04T17:00:00+05:30", calendar), calendar: calendar),
            .eveningAndTomorrow,
            "17:00 exactly must resolve one way, and evening is the useful one"
        )
    }

    func testOneMinuteBeforeTheBoundaryIsStillToday() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.phase(at: date("2026-09-04T16:59:00+05:30", calendar), calendar: calendar),
            .today
        )
    }

    func testLateEveningIsStillEveningNotTomorrow() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.phase(at: date("2026-09-04T23:59:00+05:30", calendar), calendar: calendar),
            .eveningAndTomorrow,
            "the rollover is midnight's job, not the pivot's"
        )
    }

    func testJustAfterMidnightIsTodayAgain() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.phase(at: date("2026-09-04T00:01:00+05:30", calendar), calendar: calendar),
            .today
        )
    }

    /// 2026-03-08 is the US spring-forward: 02:00 never happens, so the day is 23
    /// hours long and `startOfDay + 17 * 3600` lands at **18:00**. That is the bug
    /// this test exists for.
    func testThePivotIsSeventeenHundredLocalOnAShortDSTDay() {
        let calendar = calendar("America/New_York")
        let pivot = WidgetPhase.pivotDate(
            onDayOf: date("2026-03-08T09:00:00-05:00", calendar), calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: pivot), 17)
        XCTAssertEqual(calendar.component(.minute, from: pivot), 0)
    }

    /// 2026-11-01 is the fall-back: the day is 25 hours long, and the same naive
    /// arithmetic lands at 16:00 instead.
    func testThePivotIsSeventeenHundredLocalOnALongDSTDay() {
        let calendar = calendar("America/New_York")
        let pivot = WidgetPhase.pivotDate(
            onDayOf: date("2026-11-01T09:00:00-04:00", calendar), calendar: calendar
        )

        XCTAssertEqual(calendar.component(.hour, from: pivot), 17)
        XCTAssertEqual(calendar.component(.minute, from: pivot), 0)
    }

    func testThePivotFallsExactlyOnceOnADSTDay() {
        let calendar = calendar("America/New_York")
        let morning = date("2026-03-08T09:00:00-05:00", calendar)
        let evening = date("2026-03-08T19:00:00-04:00", calendar)

        XCTAssertEqual(WidgetPhase.phase(at: morning, calendar: calendar), .today)
        XCTAssertEqual(WidgetPhase.phase(at: evening, calendar: calendar), .eveningAndTomorrow)
    }

    // MARK: - Remaining meals

    private func meals() -> [WidgetMeal] {
        [MealType.breakfast, .lunch, .eveningSnack, .dinner].map {
            WidgetMeal(type: $0, name: $0.displayName, calories: nil, thumbnailKey: nil, prep: nil)
        }
    }

    func testEverythingRemainsFirstThingInTheMorning() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.remainingMeals(
                meals(), at: date("2026-09-04T06:00:00+05:30", calendar), calendar: calendar
            ).map(\.type),
            [.breakfast, .lunch, .eveningSnack, .dinner]
        )
    }

    /// Nominal times: breakfast 08:00, lunch 13:00, evening snack 17:00, dinner
    /// 20:00. At 19:00 only dinner is still ahead.
    func testOnlyDinnerRemainsAtSeven() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertEqual(
            WidgetPhase.remainingMeals(
                meals(), at: date("2026-09-04T19:00:00+05:30", calendar), calendar: calendar
            ).map(\.type),
            [.dinner]
        )
    }

    func testNothingRemainsLateAtNight() {
        let calendar = calendar("Asia/Kolkata")
        XCTAssertTrue(
            WidgetPhase.remainingMeals(
                meals(), at: date("2026-09-04T23:00:00+05:30", calendar), calendar: calendar
            ).isEmpty
        )
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetPhaseTests 2>&1 | tail -10
```

Expected: `error: cannot find 'WidgetPhase' in scope`.

- [ ] **Step 3: Implement the pivot**

Create `KhanaKit/Sources/KhanaKit/Logic/WidgetPhase.swift`:

```swift
import Foundation

/// Which day the home screen widget should be showing, and what of it is left.
///
/// The widget picks its own day rather than making the user place two: a Tomorrow
/// widget is dead space for most of the day. WidgetKit makes this the cheap
/// option — a timeline entry is stamped with the moment it becomes valid, so the
/// pivot is decided when the timeline is built rather than by reading a clock at
/// render time, and several phase changes a day cost one reload.
public enum WidgetPhase {

    /// 17:00, the same value as `PrepTonight.nominalMealTimes[.eveningSnack]`.
    ///
    /// A wall-clock constant rather than something derived from the user's enabled
    /// meal types: someone with `eveningSnack` switched off still wants their
    /// evening to begin at the same time, and deriving it would make the pivot jump
    /// whenever settings changed.
    public static let eveningPivotMinutes = 17 * 60

    public enum Phase: Hashable, Sendable {
        /// Today's plan.
        case today
        /// Tonight's remaining meals, then tomorrow's plan.
        case eveningAndTomorrow
    }

    /// The pivot instant on the calendar day containing `date`.
    ///
    /// Resolved by matching calendar components, not by adding seconds to midnight:
    /// a DST day is 23 or 25 hours long, so `startOfDay + 17h` lands at 18:00 on a
    /// spring-forward day and 16:00 on a fall-back one. Twice a year, on the two
    /// days nobody tests by hand.
    public static func pivotDate(onDayOf date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        var components = DateComponents()
        components.hour = eveningPivotMinutes / 60
        components.minute = eveningPivotMinutes % 60
        components.second = 0
        // `.nextTime` is what covers a day that genuinely has no 17:00: it resolves
        // to the next instant that exists rather than silently skipping the pivot.
        return calendar.nextDate(
            after: startOfDay, matching: components, matchingPolicy: .nextTime
        ) ?? startOfDay.addingTimeInterval(TimeInterval(eveningPivotMinutes * 60))
    }

    public static func phase(at date: Date, calendar: Calendar = .current) -> Phase {
        date >= pivotDate(onDayOf: date, calendar: calendar) ? .eveningAndTomorrow : .today
    }

    /// The meals whose nominal cook time has not passed yet.
    ///
    /// Nominal, not per-user, because `PrepTonight` already made that call for the
    /// reminders and the widget must not disagree with them. Order is preserved.
    public static func remainingMeals(
        _ meals: [WidgetMeal],
        at date: Date,
        calendar: Calendar = .current
    ) -> [WidgetMeal] {
        let minutesOfDay = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return meals.filter { meal in
            guard let mealTime = PrepTonight.nominalMealTimes[meal.type] else { return true }
            return mealTime > minutesOfDay
        }
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd KhanaKit && swift test --filter WidgetPhaseTests 2>&1 | grep -E "Executed|error:"
```

Expected: 11 tests, 0 failures.

- [ ] **Step 5: Write the failing test for the timeline**

Create `KhanaKit/Tests/KhanaKitTests/WidgetTimelineTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// WidgetKit allows roughly 40–70 timeline reloads a day, so anything that changes
/// on a clock has to be an *entry date* rather than a reload. The pivot is one more
/// date in this list, which is the entire cost of making the widget time-aware.
final class WidgetTimelineTests: XCTestCase {

    /// Fixed zone: the day boundary is the whole point, and `.current` would make
    /// this pass or fail depending on where it runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testTheFirstEntryIsAlwaysNowAndTheLastIsTheNextMidnight() {
        let now = date("2026-09-04T20:30:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
    }

    func testThePivotIsAnEntryWhenItIsStillAhead() {
        let now = date("2026-09-04T09:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates, [
            now,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ], "without the pivot entry the widget shows today's plan all evening")
    }

    func testThePivotIsNotAnEntryOnceItHasPassed() {
        let now = date("2026-09-04T19:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates, [now, date("2026-09-05T00:00:00+05:30")])
    }

    func testPrepBoundariesLaterTodayBecomeEntriesInOrder() {
        let now = date("2026-09-04T09:00:00+05:30")
        let noon = date("2026-09-04T12:00:00+05:30")
        let three = date("2026-09-04T15:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [three, noon], calendar: calendar
        )

        XCTAssertEqual(dates, [
            now, noon, three,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ])
    }

    func testBoundariesInThePastOrBeyondMidnightAreDropped() {
        let now = date("2026-09-04T14:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [
                date("2026-09-04T09:00:00+05:30"),   // already gone
                date("2026-09-05T09:00:00+05:30"),   // tomorrow's timeline's job
            ],
            calendar: calendar
        )

        XCTAssertEqual(dates, [
            now,
            date("2026-09-04T17:00:00+05:30"),
            date("2026-09-05T00:00:00+05:30"),
        ])
    }

    func testABoundaryThatCoincidesWithThePivotIsNotDuplicated() {
        let now = date("2026-09-04T09:00:00+05:30")
        let pivot = date("2026-09-04T17:00:00+05:30")

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: [pivot], calendar: calendar
        )

        XCTAssertEqual(dates, [now, pivot, date("2026-09-05T00:00:00+05:30")])
    }

    /// The cap drops the furthest-out prep entries first: those are already visible
    /// on their own meal's row, whereas now, the pivot and the rollover are not
    /// recoverable from anywhere else.
    func testTheCapKeepsNowThePivotAndTheRolloverAndDropsTheFurthestPrep() {
        let now = date("2026-09-04T06:00:00+05:30")
        let boundaries = (1...20).map { date("2026-09-04T06:00:00+05:30").addingTimeInterval(Double($0) * 1800) }

        let dates = WidgetTimeline.entryDates(
            startingAt: now, extraBoundaries: boundaries, calendar: calendar, limit: 12
        )

        XCTAssertEqual(dates.count, 12)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"))
        XCTAssertTrue(
            dates.contains(date("2026-09-04T17:00:00+05:30")),
            "the pivot was dropped by the cap — the widget would never turn over to tomorrow"
        )
        XCTAssertEqual(
            dates[1], date("2026-09-04T06:30:00+05:30"),
            "the earliest boundaries are the ones to keep"
        )
    }

    func testEntriesAreStrictlyIncreasing() {
        let now = date("2026-09-04T06:00:00+05:30")
        let dates = WidgetTimeline.entryDates(
            startingAt: now,
            extraBoundaries: [
                date("2026-09-04T12:00:00+05:30"),
                date("2026-09-04T12:00:00+05:30"),
                date("2026-09-04T08:00:00+05:30"),
            ],
            calendar: calendar
        )

        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count, "WidgetKit rejects duplicate entry dates")
    }

    func testMidnightExactlyNowStillProducesTheNextOne() {
        let now = date("2026-09-04T00:00:00+05:30")

        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        XCTAssertEqual(dates.last, date("2026-09-05T00:00:00+05:30"),
                       "a widget refreshed exactly at midnight must not schedule its own instant")
    }
}
```

- [ ] **Step 6: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetTimelineTests 2>&1 | tail -10
```

Expected: `error: cannot find 'WidgetTimeline' in scope`.

- [ ] **Step 7: Implement the timeline**

Create `KhanaKit/Sources/KhanaKit/Logic/WidgetTimeline.swift`:

```swift
import Foundation

/// When the widget's timeline should have entries.
///
/// WidgetKit allows roughly 40–70 timeline *reloads* a day, but a timeline may
/// carry many entries, each with its own date. Anything that changes on a clock
/// therefore belongs here rather than in a reload — which is how the evening pivot
/// costs one reload instead of one per phase, and how this ends up strictly better
/// than Android's fixed 6-hour `WorkManager` tick.
public enum WidgetTimeline {

    /// Entries for the rest of today: now, the evening pivot if it is still ahead,
    /// anything the caller knows changes later today, and the next local midnight
    /// so the day rolls over on its own.
    ///
    /// - Parameters:
    ///   - extraBoundaries: moments later today that change what is rendered. The
    ///     prep design uses this for each prep start time still ahead, so the
    ///     "Start now" banner flips on time. Values outside `(now, midnight)` are
    ///     dropped: tomorrow's boundaries belong to the timeline built after the
    ///     rollover.
    ///   - limit: hard cap on entries. `now`, the pivot and the rollover are never
    ///     dropped; the furthest-out boundaries go first, because those are already
    ///     visible on their own meal's row whereas the other three are not
    ///     recoverable from anywhere else.
    public static func entryDates(
        startingAt now: Date,
        extraBoundaries: [Date] = [],
        calendar: Calendar = .current,
        limit: Int = 12
    ) -> [Date] {
        let midnight = nextMidnight(after: now, calendar: calendar)
        let pivot = WidgetPhase.pivotDate(onDayOf: now, calendar: calendar)
        let pivotIsAhead = pivot > now && pivot < midnight

        // Reserve room for the entries that cannot be reconstructed.
        let reserved = 2 + (pivotIsAhead ? 1 : 0)
        let boundaries = Set(extraBoundaries.filter { $0 > now && $0 < midnight })
            .subtracting(pivotIsAhead ? [pivot] : [])
            .sorted()
            .prefix(max(0, limit - reserved))

        var dates = [now] + boundaries
        if pivotIsAhead { dates.append(pivot) }
        // Duplicate entry dates are rejected by WidgetKit, and a boundary can land
        // exactly on the pivot.
        return Array(Set(dates)).sorted() + [midnight]
    }

    /// The next local midnight strictly after `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        // `startOfDay` of a date that *is* midnight returns that same instant, which
        // would schedule an entry for now and leave the widget with nothing after.
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? date.addingTimeInterval(24 * 3600)
    }
}
```

- [ ] **Step 8: Run both suites and watch them pass**

```bash
cd KhanaKit && swift test --filter "WidgetPhaseTests|WidgetTimelineTests" 2>&1 | grep -E "Executed|error:"
cd KhanaKit && swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:"
```

Expected: 9 timeline tests and 11 phase tests pass; whole suite 266 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add KhanaKit/Sources/KhanaKit/Logic/WidgetPhase.swift \
  KhanaKit/Sources/KhanaKit/Logic/WidgetTimeline.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetPhaseTests.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetTimelineTests.swift
git commit -m "feat: add the widget's evening pivot and timeline entry dates"
```

---

## Phase C — The app writes the snapshot

### Task 5: The snapshot writer, and the hook that drives it

**Files:**
- Create: `App/Services/WidgetSnapshotWriter.swift`
- Create: `KhanaKit/Sources/KhanaKit/Logic/WidgetWindow.swift`
- Modify: `App/Services/MealRepository.swift:6-15` (add the hook)
- Modify: `App/AppEnvironment.swift:10-53` (construct and wire)
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetWindowTests.swift`
- Test: `AppTests/WidgetSnapshotWriterTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.build`, `WidgetSnapshotStore`, `WidgetContainer` (Tasks 2–3).
- Produces:
  - `WidgetWindow.covers(weekStartDate: String, today: PlanDate) -> Bool`
  - `WidgetSnapshotWriter(container:settings:loadWeek:reloadTimelines:)`
  - `WidgetSnapshotWriter.rebuild() async`
  - `MealRepository.onWeekChanged: ((String) -> Void)?`

- [ ] **Step 1: Write the failing test for the window check**

Create `KhanaKit/Tests/KhanaKitTests/WidgetWindowTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// Android only refreshes its widgets when a saved week `coversWidgetWeek`. Same
/// rule here: rewriting the snapshot because the user edited a week three months
/// out would be pure waste.
final class WidgetWindowTests: XCTestCase {

    /// 2026-08-03 Monday … 2026-08-09 Sunday.
    func testThisWeekIsInTheWindow() {
        XCTAssertTrue(
            WidgetWindow.covers(weekStartDate: "2026-08-03", today: PlanDate(iso: "2026-08-05")!)
        )
    }

    /// On a Sunday, tomorrow is next week's Monday, so next week matters too.
    func testNextWeekIsInTheWindowOnASunday() {
        XCTAssertTrue(
            WidgetWindow.covers(weekStartDate: "2026-08-10", today: PlanDate(iso: "2026-08-09")!)
        )
    }

    func testNextWeekIsNotInTheWindowMidWeek() {
        XCTAssertFalse(
            WidgetWindow.covers(weekStartDate: "2026-08-10", today: PlanDate(iso: "2026-08-05")!)
        )
    }

    func testLastWeekIsNotInTheWindow() {
        XCTAssertFalse(
            WidgetWindow.covers(weekStartDate: "2026-07-27", today: PlanDate(iso: "2026-08-05")!)
        )
    }

    func testAMalformedWeekStartIsNotInTheWindow() {
        XCTAssertFalse(WidgetWindow.covers(weekStartDate: "", today: PlanDate(iso: "2026-08-05")!))
        XCTAssertFalse(
            WidgetWindow.covers(weekStartDate: "not-a-date", today: PlanDate(iso: "2026-08-05")!)
        )
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetWindowTests 2>&1 | tail -10
```

Expected: `error: cannot find 'WidgetWindow' in scope`.

- [ ] **Step 3: Implement the window check**

Create `KhanaKit/Sources/KhanaKit/Logic/WidgetWindow.swift`:

```swift
import Foundation

/// Which weeks the home screen widgets can possibly be showing.
///
/// Mirrors Android's `coversWidgetWeek`: the snapshot only ever holds today and
/// tomorrow, so a change to any other week cannot change what is on the home
/// screen and must not cost a rewrite. Two weeks qualify, because on a Sunday
/// tomorrow is next week's Monday.
public enum WidgetWindow {
    public static func covers(weekStartDate: String, today: PlanDate) -> Bool {
        guard !weekStartDate.isEmpty, PlanDate(iso: weekStartDate) != nil else { return false }
        let thisWeek = WeekDates.format(WeekDates.mondayOf(today))
        let tomorrowWeek = WeekDates.format(WeekDates.mondayOf(today.adding(days: 1)))
        return weekStartDate == thisWeek || weekStartDate == tomorrowWeek
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd KhanaKit && swift test --filter WidgetWindowTests 2>&1 | grep -E "Executed|error:"
```

Expected: 5 tests, 0 failures.

- [ ] **Step 5: Write the failing test for the writer**

Create `AppTests/WidgetSnapshotWriterTests.swift`:

```swift
import KhanaKit
import XCTest
@testable import KhanaKyaBanau

/// The writer is the app's whole contribution to the widget. These drive it
/// against a temporary container and a stubbed week loader — no network, no App
/// Group provisioning needed.
@MainActor
final class WidgetSnapshotWriterTests: XCTestCase {

    private var container: WidgetContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = WidgetContainer(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container.root)
        container = nil
        try super.tearDownWithError()
    }

    private func planWithLunch(week: String, name: String) -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: week)
        plan.meals["wednesday"] = DayMeals(lunch: Meal(name: name, calories: 400))
        return plan
    }

    func testRebuildWritesASnapshotForTodayAndTomorrow() async {
        var requested: [String] = []
        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { true },
            today: { PlanDate(iso: "2026-08-05")! },      // Wednesday
            loadWeek: { week in
                requested.append(week)
                return self.planWithLunch(week: week, name: "Rajma")
            },
            loadThumbnail: { _ in nil },
            reloadTimelines: {}
        )

        await writer.rebuild()

        let snapshot = WidgetSnapshotStore.read(from: container)
        XCTAssertEqual(snapshot?.isAuthenticated, true)
        XCTAssertEqual(snapshot?.days.map(\.date), ["2026-08-05", "2026-08-06"])
        XCTAssertEqual(snapshot?.day(.wednesday)?.meals.first?.name, "Rajma")
        XCTAssertEqual(requested, ["2026-08-03"], "mid-week needs one week, not two")
    }

    /// The Sunday case: tomorrow is next week's Monday, so two weeks are needed.
    func testRebuildLoadsBothWeeksAcrossASundayRollover() async {
        var requested: [String] = []
        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { true },
            today: { PlanDate(iso: "2026-08-09")! },      // Sunday
            loadWeek: { week in
                requested.append(week)
                return self.planWithLunch(week: week, name: "Week \(week)")
            },
            loadThumbnail: { _ in nil },
            reloadTimelines: {}
        )

        await writer.rebuild()

        XCTAssertEqual(requested.sorted(), ["2026-08-03", "2026-08-10"])
    }

    func testRebuildWritesAnUnauthenticatedSnapshotWithoutLoadingAnything() async {
        var loaded = false
        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { false },
            today: { PlanDate(iso: "2026-08-05")! },
            loadWeek: { _ in loaded = true; return MealPlan.empty(weekStartDate: "2026-08-03") },
            loadThumbnail: { _ in nil },
            reloadTimelines: {}
        )

        await writer.rebuild()

        XCTAssertFalse(loaded, "a signed-out user's plan must not be fetched")
        XCTAssertEqual(WidgetSnapshotStore.read(from: container)?.isAuthenticated, false)
    }

    func testRebuildAlwaysReloadsTimelines() async {
        var reloads = 0
        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { true },
            today: { PlanDate(iso: "2026-08-05")! },
            loadWeek: { _ in throw URLError(.notConnectedToInternet) },
            loadThumbnail: { _ in nil },
            reloadTimelines: { reloads += 1 }
        )

        await writer.rebuild()

        XCTAssertEqual(reloads, 1, "a failed rebuild must still let the widget re-render")
    }

    /// A failed fetch must never replace a good snapshot with an empty one.
    func testAFailedRebuildLeavesThePreviousSnapshotAlone() async {
        let good = WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: Date(timeIntervalSince1970: 1),
            days: [WidgetDay(day: .monday, date: "2026-08-03", meals: [])]
        )
        try? WidgetSnapshotStore.write(good, to: container)

        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { true },
            today: { PlanDate(iso: "2026-08-05")! },
            loadWeek: { _ in throw URLError(.timedOut) },
            loadThumbnail: { _ in nil },
            reloadTimelines: {}
        )

        await writer.rebuild()

        XCTAssertEqual(
            WidgetSnapshotStore.read(from: container), good,
            "an offline rebuild blanked the widget"
        )
    }

    func testThumbnailsAreStoredAndPrunedToWhatTheSnapshotReferences() async {
        var plan = MealPlan.empty(weekStartDate: "2026-08-03")
        plan.meals["wednesday"] = DayMeals(
            lunch: Meal(name: "Rajma", imageUrl: "https://cdn.example/rajma.jpg")
        )
        let stale = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/old.jpg")
        try? WidgetSnapshotStore.writeThumbnail(Data([0xFF]), key: stale, to: container)

        let writer = WidgetSnapshotWriter(
            container: container,
            enabledTypes: { [.lunch] },
            showCalories: { true },
            isAuthenticated: { true },
            today: { PlanDate(iso: "2026-08-05")! },
            loadWeek: { _ in plan },
            loadThumbnail: { _ in Data([0x01, 0x02]) },
            reloadTimelines: {}
        )

        await writer.rebuild()

        let key = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://cdn.example/rajma.jpg")
        XCTAssertEqual(WidgetSnapshotStore.thumbnailData(key: key, in: container), Data([0x01, 0x02]))
        XCTAssertNil(
            WidgetSnapshotStore.thumbnailData(key: stale, in: container),
            "a thumbnail the new snapshot does not reference was left behind"
        )
    }
}
```

- [ ] **Step 6: Run it and watch it fail**

```bash
cd /Users/vishwanatharondekar/projects/khanakyabanau-ios-native
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests/WidgetSnapshotWriterTests test 2>&1 | grep -E "error:|Executed"
```

Expected: `error: cannot find 'WidgetSnapshotWriter' in scope`.

- [ ] **Step 7: Implement the writer**

Create `App/Services/WidgetSnapshotWriter.swift`:

```swift
import Foundation
import KhanaKit
import WidgetKit

/// Builds the widget snapshot and puts it in the shared container.
///
/// Everything it needs arrives as a closure rather than as a repository. That is
/// not ceremony: `MealRepository` calls *into* this type, so holding a
/// `MealRepository` here would be a reference cycle, and the closures make the
/// whole thing drivable from a test with no network and no App Group.
@MainActor
final class WidgetSnapshotWriter {
    private let container: WidgetContainer?
    private let enabledTypes: () -> [MealType]
    private let showCalories: () -> Bool
    private let isAuthenticated: () -> Bool
    private let today: () -> PlanDate
    private let loadWeek: (String) async throws -> MealPlan
    private let loadThumbnail: (String) async -> Data?
    private let reloadTimelines: () -> Void

    /// Coalesces the bursts that happen when several screens settle at once.
    private var inFlight: Task<Void, Never>?

    init(
        container: WidgetContainer?,
        enabledTypes: @escaping () -> [MealType],
        showCalories: @escaping () -> Bool,
        isAuthenticated: @escaping () -> Bool,
        today: @escaping () -> PlanDate = { WeekDates.today() },
        loadWeek: @escaping (String) async throws -> MealPlan,
        loadThumbnail: @escaping (String) async -> Data?,
        reloadTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadAllTimelines()
        }
    ) {
        self.container = container
        self.enabledTypes = enabledTypes
        self.showCalories = showCalories
        self.isAuthenticated = isAuthenticated
        self.today = today
        self.loadWeek = loadWeek
        self.loadThumbnail = loadThumbnail
        self.reloadTimelines = reloadTimelines
    }

    /// Fire-and-forget, for call sites that must not wait on a widget.
    func requestRebuild() {
        inFlight?.cancel()
        inFlight = Task { [weak self] in await self?.rebuild() }
    }

    func rebuild() async {
        // No container means no App Group — a free-account build, which has no
        // widget to feed. Nothing to do, and nothing wrong.
        guard let container else { return }
        defer { reloadTimelines() }

        let today = today()

        guard isAuthenticated() else {
            try? WidgetSnapshotStore.write(.unauthenticated(writtenAt: Date()), to: container)
            return
        }

        let thisWeek = WeekDates.format(WeekDates.mondayOf(today))
        let tomorrowWeek = WeekDates.format(WeekDates.mondayOf(today.adding(days: 1)))

        do {
            let todayPlan = try await loadWeek(thisWeek)
            // Same week on six days out of seven; only a Sunday needs the second.
            let tomorrowPlan = tomorrowWeek == thisWeek
                ? todayPlan
                : try await loadWeek(tomorrowWeek)

            let thumbnails = await thumbnails(
                todayPlan: todayPlan, tomorrowPlan: tomorrowPlan, today: today
            )

            let snapshot = WidgetSnapshot.build(
                today: today,
                todayPlan: todayPlan,
                tomorrowPlan: tomorrowPlan,
                enabledTypes: enabledTypes(),
                showCalories: showCalories(),
                thumbnailKey: { url in
                    let key = WidgetSnapshotStore.thumbnailKey(forImageURL: url)
                    // Only claim a key the file actually exists for, or the
                    // extension renders a gap where a photo should be.
                    return thumbnails[key] == nil ? nil : key
                },
                writtenAt: Date()
            )

            try WidgetSnapshotStore.write(snapshot, to: container)
            WidgetSnapshotStore.pruneThumbnails(keeping: Set(thumbnails.keys), in: container)
        } catch {
            // Deliberately leaves the previous snapshot in place: a stale menu is
            // far better than a blank widget, which is what writing an empty
            // snapshot on every flaky connection would produce.
        }
    }

    /// Downloads and stores the photos for the two days the snapshot covers,
    /// skipping any already on disk. Keyed by file name so the caller can both
    /// reference and prune by the same key.
    private func thumbnails(
        todayPlan: MealPlan,
        tomorrowPlan: MealPlan,
        today: PlanDate
    ) async -> [String: Bool] {
        guard let container else { return [:] }
        let types = enabledTypes()
        let urls: [String] =
            [(today, todayPlan), (today.adding(days: 1), tomorrowPlan)]
            .flatMap { date, plan -> [String] in
                let meals = plan.meals(for: date.dayOfWeek)
                return types.compactMap { meals[$0].imageUrl }
            }

        var stored: [String: Bool] = [:]
        for url in Set(urls) {
            let key = WidgetSnapshotStore.thumbnailKey(forImageURL: url)
            if WidgetSnapshotStore.thumbnailData(key: key, in: container) != nil {
                stored[key] = true
                continue
            }
            guard let data = await loadThumbnail(url) else { continue }
            try? WidgetSnapshotStore.writeThumbnail(data, key: key, to: container)
            stored[key] = true
        }
        return stored
    }
}
```

- [ ] **Step 8: Run the writer tests and watch them pass**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests/WidgetSnapshotWriterTests test 2>&1 | grep -E "Test Case|error:|Executed"
```

Expected: 6 tests, 0 failures.

- [ ] **Step 8b: Add the 256px downscaler**

The spec pins thumbnails at 256px, matching Android's Coil `.size(256)`. Storing
full-resolution photos would put megabytes in the container and hand the extension
images it must downsample inside a ~30MB render budget.

Create `App/Services/WidgetThumbnails.swift`:

```swift
import Foundation
import UIKit

/// Fetches a dish photo and stores it at the size the widget actually draws.
///
/// 256px on the long edge, matching Android's Coil `.size(256)`. The extension
/// renders at 72pt, so anything larger is bytes in the shared container and work
/// inside a ~30MB widget render budget for no visible gain.
enum WidgetThumbnails {
    static let maxPixelSize: CGFloat = 256

    static func fetch(_ url: String) async -> Data? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        return downscale(data)
    }

    /// Returns JPEG data no larger than `maxPixelSize` on its long edge. Falls back
    /// to the original bytes if decoding fails — a working photo beats no photo.
    static func downscale(_ data: Data, maxPixelSize: CGFloat = WidgetThumbnails.maxPixelSize) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxPixelSize else { return image.jpegData(compressionQuality: 0.8) ?? data }

        let scale = maxPixelSize / longEdge
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}
```

Add to `AppTests/WidgetSnapshotWriterTests.swift`:

```swift
    func testThumbnailsAreDownscaledToTheSizeTheWidgetDraws() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 966), format: format)
            .image { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1600, height: 966))
            }

        let shrunk = try XCTUnwrap(WidgetThumbnails.downscale(try XCTUnwrap(big.pngData())))
        let result = try XCTUnwrap(UIImage(data: shrunk))

        XCTAssertEqual(max(result.size.width, result.size.height), 256, accuracy: 1)
        XCTAssertEqual(result.size.width / result.size.height, 1600 / 966, accuracy: 0.01,
                       "the aspect ratio changed — the widget would show a squashed photo")
    }

    func testAnAlreadySmallThumbnailIsNotUpscaled() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 60), format: format)
            .image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
            }

        let result = try XCTUnwrap(
            UIImage(data: try XCTUnwrap(WidgetThumbnails.downscale(try XCTUnwrap(small.pngData()))))
        )

        XCTAssertEqual(result.size.width, 100, accuracy: 1)
    }
```

This test file needs `import UIKit` added at the top.

Run:

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests/WidgetSnapshotWriterTests test 2>&1 | grep -E "Test Case|error:|Executed"
```

Expected: 8 tests, 0 failures.

- [ ] **Step 9: Add the hook to `MealRepository`**

In `App/Services/MealRepository.swift`, add the property and fire it. This mirrors Android injecting `WidgetRefresher` into `MealsRepository`, but as a closure so there is no cycle:

```swift
    /// Called with the week that just changed, so the widget snapshot can be
    /// rebuilt. Android injects a `WidgetRefresher` here; a closure keeps this type
    /// unaware of the widget and avoids a reference cycle with the writer.
    var onWeekChanged: ((String) -> Void)?
```

At the end of `week(_:)`, before `return plan`:

```swift
        onWeekChanged?(weekStartDate)
```

and in `save(_:)`, after the `api.send` succeeds:

```swift
        onWeekChanged?(plan.weekStartDate)
```

- [ ] **Step 10: Wire it up in `AppEnvironment`**

In `App/AppEnvironment.swift`, after `meals` and `settings` exist, add the stored property and the wiring:

```swift
    let widgetSnapshots: WidgetSnapshotWriter
```

and in `init()`:

```swift
        let widgetSnapshots = WidgetSnapshotWriter(
            container: WidgetContainer.shared(),
            enabledTypes: { [settings] in settings.enabledTypes },
            showCalories: { [settings] in settings.showCalories },
            isAuthenticated: { TokenStore.currentToken()?.isEmpty == false },
            loadWeek: { [meals] week in try await meals.week(week) },
            loadThumbnail: { url in await WidgetThumbnails.fetch(url) }
        )
        self.widgetSnapshots = widgetSnapshots

        // Only weeks the widget could be showing. A week three months out cannot
        // change the home screen, and rewriting for it would be pure waste.
        meals.onWeekChanged = { week in
            guard WidgetWindow.covers(weekStartDate: week, today: WeekDates.today()) else {
                return
            }
            widgetSnapshots.requestRebuild()
        }
```

- [ ] **Step 11: Rebuild the snapshot on the other three triggers**

The spec lists sign-in, sign-out and an `enabledTypes` change alongside week loads.

- In `App/SessionStore.swift`, at the end of the method that completes a sign-in and at the end of `signOut()`, add `env.widgetSnapshots.requestRebuild()`.
- In `App/Services/SettingsRepository.swift`, in the method that persists meal settings, add a callback the environment wires the same way — or, if the repository already exposes an `onChange` hook, reuse it. Grep first:

```bash
grep -n "mealSettings" App/Services/SettingsRepository.swift
```

- [ ] **Step 12: Run the whole unit suite**

```bash
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
cd KhanaKit && swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:"
```

Expected: 78 app unit tests and 259 KhanaKit tests, 0 failures.

- [ ] **Step 13: Commit**

```bash
git add App/Services/WidgetSnapshotWriter.swift App/Services/MealRepository.swift \
  App/AppEnvironment.swift App/SessionStore.swift App/Services/SettingsRepository.swift \
  KhanaKit/Sources/KhanaKit/Logic/WidgetWindow.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetWindowTests.swift \
  AppTests/WidgetSnapshotWriterTests.swift
git commit -m "feat: write the widget snapshot whenever a visible week changes"
```

---

## Phase D — The extension

### Task 6: The extension target, placeable and rendering the setup shell

**Files:**
- Create: `Widgets/KhanaKyaBanauWidgets.swift`
- Create: `Widgets/WidgetColors.swift`
- Create: `Widgets/Info.plist`
- Create: `Widgets/KhanaKyaBanauWidgets.entitlements`
- Modify: `project.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `WidgetSnapshotStore`, `WidgetContainer` (Tasks 2–3), `WidgetPhase`, `WidgetTimeline` (Task 4).
- Produces: `MenuWidget` (kind `"menu"`), `MenuEntry`, `SnapshotProvider`, `MenuWidgetView`, `KkbWidget` palette, `WidgetShell(message:emphasis:)`.

- [ ] **Step 1: Create `Widgets/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AppIdentifierPrefix</key>
	<string>$(AppIdentifierPrefix)</string>
	<key>CFBundleDisplayName</key>
	<string>Khana Kya Banau</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 2: Create `Widgets/KhanaKyaBanauWidgets.entitlements`**

The extension needs the same two capabilities as the app — the App Group to read the snapshot, the keychain group to read the token for the network top-up in Task 7.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.in.khanakyabanau.app</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)in.khanakyabanau.shared</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Add the target to `project.yml`**

Under `targets:`, after `KhanaKyaBanau`:

```yaml
  KhanaKyaBanauWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: Widgets
        excludes:
          - "Info.plist"
          - "KhanaKyaBanauWidgets.entitlements"
    dependencies:
      - package: KhanaKit
        product: KhanaKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: in.khanakyabanau.app.widgets
        PRODUCT_NAME: KhanaKyaBanauWidgets
        INFOPLIST_FILE: Widgets/Info.plist
        # App Groups and keychain sharing both need a paid membership, same as
        # push. There is no free-account variant: without the App Group there is
        # no way to hand the extension any data at all.
        CODE_SIGN_ENTITLEMENTS: Widgets/KhanaKyaBanauWidgets.entitlements
        SKIP_INSTALL: "YES"
```

and add it to the app target's `dependencies`, which is what embeds it:

```yaml
      - target: KhanaKyaBanauWidgets
        embed: true
```

- [ ] **Step 4: Create `Widgets/WidgetColors.swift`**

The `Kkb` palette lives in the app target, which the extension does not link. Android duplicates the same values in its own `WidgetColors.kt` for exactly this reason; these hex values are pinned by `DesignSystemTests.testPaletteMatchesAndroidHexValues`.

```swift
import SwiftUI

/// The widget's palette.
///
/// Duplicated from the app's `Kkb` rather than shared: the design system lives in
/// the app target, `KhanaKit` is deliberately SwiftUI-free, and Android duplicates
/// the same values into its own `WidgetColors.kt` for the same reason. The hex
/// values are pinned on the app side by
/// `DesignSystemTests.testPaletteMatchesAndroidHexValues`.
enum KkbWidget {
    static let cream50 = Color(hex: 0xFEFAF3)
    static let cream100 = Color(hex: 0xFDF5E6)
    static let cream300 = Color(hex: 0xF5E6C8)
    static let terracotta500 = Color(hex: 0xD55F24)
    static let terracotta600 = Color(hex: 0xB8481D)
    static let marigold100 = Color(hex: 0xFDEBC8)
    static let marigold700 = Color(hex: 0xB86A06)
    static let ink600 = Color(hex: 0x6B5A4C)
    static let ink900 = Color(hex: 0x2A1F17)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 5: Create `Widgets/KhanaKyaBanauWidgets.swift`**

One widget, whose entries each carry the phase computed from their *own* date — that is what makes the pivot happen without a reload. Rows come in Task 8; this step's deliverable is "it appears in the gallery and can be placed".

```swift
import KhanaKit
import SwiftUI
import WidgetKit

@main
struct KhanaKyaBanauWidgetBundle: WidgetBundle {
    var body: some Widget {
        MenuWidget()
    }
}

/// One widget that decides its own day, rather than Android's pair.
///
/// A Tomorrow widget is dead space for most of the day, and asking someone to
/// place two widgets to get one coherent answer is asking them to do the app's
/// thinking. `StaticConfiguration` because there is nothing left to configure:
/// if you want the other day, the app is one tap away.
struct MenuWidget: Widget {
    /// Never change this string. It is the identity of every widget a user has
    /// already placed on their home screen; changing it orphans them all.
    static let kind = "menu"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MenuWidget.kind, provider: SnapshotProvider()) { entry in
            MenuWidgetView(entry: entry)
        }
        .configurationDisplayName("Khana Kya Banau")
        .description("Today's menu, and tomorrow's once the evening comes round.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MenuEntry: TimelineEntry {
    let date: Date
    /// Computed from `date`, not from "now" — that is the whole trick. Every entry
    /// knows which phase it represents, so the 17:00 turnover costs no reload.
    let phase: WidgetPhase.Phase
    /// `nil` means "no readable snapshot" — rendered as the setup shell, never as
    /// an error, because an invitation is more useful than a complaint.
    let today: WidgetDay?
    let tomorrow: WidgetDay?
    let isAuthenticated: Bool
    let container: WidgetContainer?
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> MenuEntry {
        MenuEntry(
            date: Date(), phase: .today, today: nil, tomorrow: nil,
            isAuthenticated: false, container: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MenuEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MenuEntry>) -> Void) {
        let now = Date()
        let dates = WidgetTimeline.entryDates(startingAt: now)
        completion(
            Timeline(
                entries: dates.map { entry(at: $0) },
                policy: .after(WidgetTimeline.nextMidnight(after: now))
            )
        )
    }

    private func entry(at date: Date) -> MenuEntry {
        let container = WidgetContainer.shared()
        let snapshot = container.flatMap { WidgetSnapshotStore.read(from: $0) }
        // The snapshot holds today then tomorrow in order, so this picks by index
        // rather than by weekday — which stays correct across a rollover without
        // recomputing the calendar here.
        return MenuEntry(
            date: date,
            phase: WidgetPhase.phase(at: date),
            today: snapshot?.days.first,
            tomorrow: snapshot?.days.dropFirst().first,
            isAuthenticated: snapshot?.isAuthenticated ?? false,
            container: container
        )
    }
}

struct MenuWidgetView: View {
    let entry: MenuEntry

    var body: some View {
        content
            // Required: without it the widget renders blank in StandBy and on iPad.
            .containerBackground(KkbWidget.cream50, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isAuthenticated || entry.today == nil {
            WidgetShell(message: "Tap to set up", emphasis: true)
        } else if let today = entry.today, !today.hasAnyMeal,
                  entry.tomorrow?.hasAnyMeal != true {
            WidgetShell(message: "Open the app to pick meals", emphasis: false)
        } else {
            // Rows arrive in Task 8.
            WidgetShell(message: entry.today?.day.displayName ?? "", emphasis: false)
        }
    }
}

/// The empty and unauthenticated states. Copy matches Android's strings so
/// screenshots and support answers agree.
struct WidgetShell: View {
    let message: String
    let emphasis: Bool

    var body: some View {
        Text(message)
            .font(.system(size: emphasis ? 16 : 13, weight: emphasis ? .medium : .regular))
            .foregroundStyle(emphasis ? KkbWidget.ink900 : KkbWidget.ink600)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 6: Generate and build**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`, and the log includes a `KhanaKyaBanauWidgets.appex` being embedded.

- [ ] **Step 7: Run the unit suites to confirm nothing regressed**

```bash
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
```

Expected: 78 tests, 0 failures.

- [ ] **Step 8: Place the widget by hand**

The only way to verify a widget is placeable.

```bash
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' build \
  && xcrun simctl launch booted in.khanakyabanau.app
```

Then, in the simulator: long-press the home screen → **+** → search "Khana" → **one** entry named *Khana Kya Banau* appears (not two) → place it in all three sizes. Signed out, every one reads `Tap to set up`.

- [ ] **Step 9: Document the membership requirement in the README**

Add to the "Installing on your own iPhone" section:

```markdown
The home screen widget needs App Groups and keychain sharing, which are
provisioned capabilities a free Apple ID cannot get. For a free-account install,
set `KKB_ENTITLEMENTS: App/KhanaKyaBanau.entitlements` in `project.yml` and skip
the widget target — the app itself works unchanged.
```

- [ ] **Step 10: Commit**

```bash
git add Widgets project.yml README.md
git commit -m "feat: add the widget extension target with its empty states"
```

### Task 7: The network top-up

**Files:**
- Create: `Widgets/WidgetRefresh.swift`
- Modify: `Widgets/KhanaKyaBanauWidgets.swift` (call it from `getTimeline`)
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetRefreshDecisionTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.isStale`, `WidgetSnapshotStore`.
- Produces: `WidgetRefreshDecision.shouldRefresh(snapshot:hasToken:now:) -> Bool` (in KhanaKit), `WidgetRefresh.topUp(container:) async`

- [ ] **Step 1: Write the failing test for the decision**

Create `KhanaKit/Tests/KhanaKitTests/WidgetRefreshDecisionTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// Whether the extension should spend a network call. Kept pure and in KhanaKit
/// because the answer is arithmetic, and because an extension is the worst place
/// to debug arithmetic.
final class WidgetRefreshDecisionTests: XCTestCase {

    private let writtenAt = Date(timeIntervalSince1970: 1_788_000_000)

    private func snapshot(authenticated: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot(isAuthenticated: authenticated, writtenAt: writtenAt, days: [])
    }

    func testAFreshSnapshotIsLeftAlone() {
        XCTAssertFalse(
            WidgetRefreshDecision.shouldRefresh(
                snapshot: snapshot(), hasToken: true,
                now: writtenAt.addingTimeInterval(3600)
            )
        )
    }

    func testAStaleSnapshotWithATokenIsRefreshed() {
        XCTAssertTrue(
            WidgetRefreshDecision.shouldRefresh(
                snapshot: snapshot(), hasToken: true,
                now: writtenAt.addingTimeInterval(7 * 3600)
            )
        )
    }

    func testNoTokenMeansNoRefreshHoweverStale() {
        XCTAssertFalse(
            WidgetRefreshDecision.shouldRefresh(
                snapshot: snapshot(), hasToken: false,
                now: writtenAt.addingTimeInterval(48 * 3600)
            ),
            "without a token a fetch can only 401 — spend nothing"
        )
    }

    /// No snapshot at all: the app has never run, or the container was cleared. A
    /// token is still the gate.
    func testAMissingSnapshotIsRefreshedOnlyWithAToken() {
        XCTAssertTrue(
            WidgetRefreshDecision.shouldRefresh(snapshot: nil, hasToken: true, now: writtenAt)
        )
        XCTAssertFalse(
            WidgetRefreshDecision.shouldRefresh(snapshot: nil, hasToken: false, now: writtenAt)
        )
    }

    /// A snapshot that says "signed out" is a fact the app wrote, not staleness.
    func testAnUnauthenticatedSnapshotIsNotRefreshed() {
        XCTAssertFalse(
            WidgetRefreshDecision.shouldRefresh(
                snapshot: snapshot(authenticated: false), hasToken: true,
                now: writtenAt.addingTimeInterval(48 * 3600)
            )
        )
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetRefreshDecisionTests 2>&1 | tail -10
```

Expected: `error: cannot find 'WidgetRefreshDecision' in scope`.

- [ ] **Step 3: Implement the decision**

Append to `KhanaKit/Sources/KhanaKit/Logic/WidgetTimeline.swift`:

```swift
/// Whether the widget extension should spend a network call on this render.
///
/// The snapshot is the floor: it is what makes the widget render at all offline,
/// on a slow connection, or before the extension has ever run. The network is a
/// top-up on that floor, and this decides when it is worth taking.
public enum WidgetRefreshDecision {
    public static func shouldRefresh(
        snapshot: WidgetSnapshot?,
        hasToken: Bool,
        now: Date,
        maxAge: TimeInterval = WidgetSnapshot.defaultMaxAge
    ) -> Bool {
        // Without a token a fetch can only 401.
        guard hasToken else { return false }
        guard let snapshot else { return true }
        // "Signed out" is something the app asserted, not something that goes off.
        guard snapshot.isAuthenticated else { return false }
        return snapshot.isStale(now: now, maxAge: maxAge)
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd KhanaKit && swift test --filter WidgetRefreshDecisionTests 2>&1 | grep -E "Executed|error:"
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Implement the top-up in the extension**

Create `Widgets/WidgetRefresh.swift`.

`APIClient` is a `public actor` in `KhanaKit` — not `@MainActor` — and it takes its
token as a `@Sendable () -> String?` closure. So the extension uses the real client
rather than a hand-rolled `URLSession` path, and the endpoint, timeouts, error
mapping and decoding stay in one place.

```swift
import Foundation
import KhanaKit
import Security

/// The extension's network top-up.
///
/// Uses the app's own `APIClient` — it is a `public actor` with an injectable token
/// provider, so nothing about it is app-only — which keeps the endpoint, the two
/// timeout budgets, the error mapping and the decoding in one implementation.
enum WidgetRefresh {

    /// Fetches the weeks the snapshot covers and rewrites it.
    ///
    /// Silent on every failure: the caller has already rendered whatever the app
    /// last wrote, and a stale menu beats a blank widget.
    static func topUp(container: WidgetContainer, now: Date = Date()) async {
        let previous = WidgetSnapshotStore.read(from: container)
        guard WidgetRefreshDecision.shouldRefresh(
            snapshot: previous, hasToken: token() != nil, now: now
        ) else { return }

        let api = APIClient(tokenProvider: { WidgetRefresh.token() })
        let today = WeekDates.today()
        let thisWeek = WeekDates.format(WeekDates.mondayOf(today))
        let tomorrowWeek = WeekDates.format(WeekDates.mondayOf(today.adding(days: 1)))

        do {
            let todayPlan = try await week(thisWeek, via: api)
            // Same week six days out of seven; only a Sunday needs the second.
            let tomorrowPlan = tomorrowWeek == thisWeek
                ? todayPlan
                : try await week(tomorrowWeek, via: api)

            let snapshot = WidgetSnapshot.build(
                today: today,
                todayPlan: todayPlan,
                tomorrowPlan: tomorrowPlan,
                // The extension cannot see the user's settings — they live behind
                // `SettingsRepository` in the app. Carry forward what the app
                // already chose, so a refresh can never widen what it decided to
                // show. No previous snapshot means no basis to choose, so show
                // nothing new and let the app write the first one.
                enabledTypes: previous?.days.first?.meals.map(\.type) ?? [],
                showCalories: previous?.days.first?.meals.contains { $0.calories != nil } ?? false,
                // Only claim photos already on disk. An extension must never be the
                // thing that discovers it has to download an image.
                thumbnailKey: { url in
                    let key = WidgetSnapshotStore.thumbnailKey(forImageURL: url)
                    return WidgetSnapshotStore.thumbnailData(key: key, in: container) == nil
                        ? nil : key
                },
                writtenAt: Date()
            )
            try WidgetSnapshotStore.write(snapshot, to: container)
        } catch {
            // Deliberately nothing: `previous` is still on disk and still renders.
        }
    }

    /// Mirrors `MealRepository.week`, including the image-URL normalisation — the
    /// server returns bare file names as well as absolute URLs.
    private static func week(_ weekStartDate: String, via api: APIClient) async throws -> MealPlan {
        let plan = try await api.send(Endpoints.week(weekStartDate), as: MealPlan.self)
        return plan.normalizingImageURLs(MealImageURLs.absolutize)
    }

    /// The session token, out of the keychain group both targets now share.
    ///
    /// Reads `SecItem` directly rather than through `TokenStore`, which is
    /// `@MainActor`, `@Observable`, and owns a guest-device-id lifecycle the widget
    /// has no business touching.
    static func token() -> String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix")
                as? String, !prefix.isEmpty, !prefix.hasPrefix("$(")
        else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "in.khanakyabanau.app",
            kSecAttrAccount as String: "auth_token",
            kSecAttrAccessGroup as String: prefix + "in.khanakyabanau.shared",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 6: Call it from `getTimeline`**

In `Widgets/KhanaKyaBanauWidgets.swift`, make `getTimeline` async-aware:

```swift
    func getTimeline(in context: Context, completion: @escaping (Timeline<MenuEntry>) -> Void) {
        Task {
            // Best-effort, and bounded: the snapshot has already been written by
            // the app, so the worst case is rendering it one refresh out of date.
            if let container = WidgetContainer.shared() {
                await WidgetRefresh.topUp(container: container)
            }
            let now = Date()
            let dates = WidgetTimeline.entryDates(startingAt: now)
            completion(
                Timeline(
                    entries: dates.map { entry(at: $0) },
                    policy: .after(WidgetTimeline.nextMidnight(after: now))
                )
            )
        }
    }
```

- [ ] **Step 7: Build, and verify by hand**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
cd KhanaKit && swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:"
```

Expected: `BUILD SUCCEEDED`; 265 KhanaKit tests, 0 failures.

Then: sign in, confirm the widget shows meals, force-quit the app, turn on airplane mode, and confirm the widget still shows the same meals rather than an error tile.

- [ ] **Step 8: Commit**

```bash
git add Widgets/WidgetRefresh.swift Widgets/KhanaKyaBanauWidgets.swift \
  KhanaKit/Sources/KhanaKit/Logic/WidgetTimeline.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetRefreshDecisionTests.swift
git commit -m "feat: let the widget top up a stale snapshot from the network"
```

### Task 8: The meal rows, the phases, and the three families

**Files:**
- Create: `Widgets/WidgetDayContent.swift`
- Modify: `Widgets/KhanaKyaBanauWidgets.swift` (render the new content)

**Interfaces:**
- Consumes: `MenuEntry`, `KkbWidget`, `WidgetSnapshotStore.thumbnailData`, `WidgetPhase.remainingMeals`.
- Produces: `MenuContent(entry:family:)`, `WidgetMealRow(meal:container:compact:)`, `WidgetHeader(eyebrow:dayLabel:)`, `TomorrowDivider`

Layout only, so no unit test — the deliverable is the manual matrix in Step 4. Keeping it as its own task means a reviewer can reject the layout without rejecting the data path.

- [ ] **Step 1: Create `Widgets/WidgetDayContent.swift`**

```swift
import KhanaKit
import SwiftUI
import WidgetKit

/// The row list — the direct counterpart of Android's `LargeDayContent`, plus the
/// phase rule Android does not have.
struct MenuContent: View {
    let entry: MenuEntry
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            switch family {
            case .systemSmall:
                smallBody
            default:
                phasedBody
            }
            if family != .systemSmall { Spacer(minLength: 0) }
        }
    }

    /// Small is inherently rolling: the next meal still to come, whichever day it
    /// belongs to. That needs no phase logic and crosses midnight on its own.
    @ViewBuilder
    private var smallBody: some View {
        let remaining = WidgetPhase.remainingMeals(written(entry.today), at: entry.date)
        // After the last meal of the day, roll on to tomorrow's first rather than
        // showing an empty card for the rest of the evening.
        let next = remaining.first ?? written(entry.tomorrow).first
        let isTomorrow = remaining.isEmpty && next != nil

        WidgetHeader(
            eyebrow: isTomorrow ? "TOMORROW" : "NEXT",
            dayLabel: (isTomorrow ? entry.tomorrow : entry.today)?.day.displayName ?? ""
        )
        if let next {
            WidgetMealRow(meal: next, container: entry.container, compact: true)
        } else {
            WidgetShell(message: "Open the app to pick meals", emphasis: false)
        }
    }

    /// Medium and large follow the pivot: today's plan until 17:00, then what is
    /// left of tonight followed by tomorrow — the moment anyone actually plans
    /// ahead.
    @ViewBuilder
    private var phasedBody: some View {
        switch entry.phase {
        case .today:
            WidgetHeader(eyebrow: "TODAY", dayLabel: entry.today?.day.displayName ?? "")
            rows(written(entry.today))

        case .eveningAndTomorrow:
            let tonight = WidgetPhase.remainingMeals(written(entry.today), at: entry.date)
            if !tonight.isEmpty {
                WidgetHeader(eyebrow: "TONIGHT", dayLabel: entry.today?.day.displayName ?? "")
                rows(tonight)
            }
            TomorrowDivider(dayLabel: entry.tomorrow?.day.displayName ?? "")
            rows(written(entry.tomorrow), budget: budget - tonight.count)
        }
    }

    /// Medium fits three rows — four when no prep banner is taking a line. Large
    /// takes everything.
    private var budget: Int {
        family == .systemMedium ? 4 : Int.max
    }

    @ViewBuilder
    private func rows(_ meals: [WidgetMeal], budget: Int? = nil) -> some View {
        ForEach(Array(meals.prefix(max(0, budget ?? self.budget))), id: \.type) { meal in
            WidgetMealRow(meal: meal, container: entry.container, compact: false)
        }
    }

    private func written(_ day: WidgetDay?) -> [WidgetMeal] {
        (day?.meals ?? []).filter { !$0.isEmpty }
    }
}

struct WidgetHeader: View {
    let eyebrow: String
    let dayLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
            Text("·  \(dayLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KkbWidget.ink600)
        }
    }
}

/// Separates tonight from tomorrow after the pivot, so the two days never read as
/// one undifferentiated list.
struct TomorrowDivider: View {
    let dayLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Text("TOMORROW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
            Text(dayLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(KkbWidget.ink600)
            Rectangle()
                .fill(KkbWidget.cream300)
                .frame(height: 1)
        }
        .padding(.top, 2)
    }
}

/// Thumbnail, meal-type label, calorie pill, two-line name — Android's
/// `LargeMealRow`, at 72pt to match its 72dp.
struct WidgetMealRow: View {
    let meal: WidgetMeal
    let container: WidgetContainer?
    let compact: Bool

    private var thumbnailSize: CGFloat { compact ? 44 : 72 }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(meal.type.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KkbWidget.terracotta600)
                    if let calories = meal.calories {
                        Text("🔥 \(calories)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(KkbWidget.marigold700)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(KkbWidget.marigold100))
                    }
                }
                Text(meal.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KkbWidget.ink900)
                    // Two lines, matching Android: long names
                    // ("Maharashtrian Style Vegetable Omelette…") should read
                    // rather than truncate to a hyphen.
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        let data = meal.thumbnailKey.flatMap { key in
            container.flatMap { WidgetSnapshotStore.thumbnailData(key: key, in: $0) }
        }
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // A *fixed* frame in both axes, so `scaledToFill` cannot report a
                // size wider than the row. `frame(height:)` plus
                // `frame(maxWidth: .infinity)` would — that is the bug fixed in
                // f128dbf, and why `KkbFullBleedBand` exists in the app target.
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            // The dish has no photo, or the app has not stored it yet. Android
            // shows the meal-type emoji on cream; so do we.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KkbWidget.cream100)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .overlay(Text(meal.type.emoji).font(.system(size: compact ? 20 : 32)))
        }
    }
}
```

- [ ] **Step 2: Render it**

In `Widgets/KhanaKyaBanauWidgets.swift`, add the family to `MenuWidgetView` and use the new content:

```swift
struct MenuWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MenuEntry

    var body: some View {
        content
            .containerBackground(KkbWidget.cream50, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isAuthenticated || entry.today == nil {
            WidgetShell(message: "Tap to set up", emphasis: true)
        } else if entry.today?.hasAnyMeal != true, entry.tomorrow?.hasAnyMeal != true {
            WidgetShell(message: "Open the app to pick meals", emphasis: false)
        } else {
            MenuContent(entry: entry, family: family)
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify the matrix by hand**

Place the widget in all three families and check each cell. The two phase rows are the ones no test covers.

| Check | Expected |
|---|---|
| Small | one row, 44pt thumbnail, `NEXT` eyebrow, no clipping |
| Small after the last meal of the day | rolls on to tomorrow's first meal under a `TOMORROW` eyebrow |
| Medium before 17:00 | `TODAY`, three or four rows, 72pt thumbnails, none touching |
| Medium after 17:00 | `TONIGHT` with dinner, then the `TOMORROW` divider, then tomorrow's rows |
| Large after 17:00 | the same, with every enabled meal on both sides of the divider |
| Set the simulator clock to 16:58 and wait | the widget turns over on its own at 17:00, untouched |
| A dish with no photo | meal-type emoji on cream, not a gap |
| A long dish name | wraps to two lines, then truncates |
| Calories off in Settings | no pill on any family |
| No meals on either day | `Open the app to pick meals` |
| Signed out | `Tap to set up` |
| Dark mode | cream ground, legible text (the palette is fixed, not adaptive — same as Android) |
| StandBy (iPhone on charge, landscape) | renders, not blank |

For the clock check: **Settings → General → Date & Time** in the simulator, or
`xcrun simctl status_bar booted override --time "16:58"` for the status bar only —
the former is what actually moves the widget's timeline.

- [ ] **Step 5: Commit**

```bash
git add Widgets/WidgetDayContent.swift Widgets/KhanaKyaBanauWidgets.swift
git commit -m "feat: render the widget's phases and meal rows across all three families"
```

### Task 9: Deep links

**Files:**
- Create: `KhanaKit/Sources/KhanaKit/Logic/WidgetDeepLink.swift`
- Modify: `App/Info.plist`
- Modify: `App/AppRootView.swift`
- Modify: `Widgets/WidgetDayContent.swift`
- Test: `KhanaKit/Tests/KhanaKitTests/WidgetDeepLinkTests.swift`

**Interfaces:**
- Consumes: `AppRoute` is app-side, so the parser returns its own type and the app maps it.
- Produces:
  - `WidgetMealRow(meal:container:compact:day:)` — this task adds the `day`
    parameter to the row built in Task 8, so it can build its own meal link. After
    the pivot the rows on screen span two days, so the day travels with the row
    rather than being read from the entry
  - `WidgetDeepLink.scheme = "khanakyabanau"`
  - `WidgetDeepLink.url(day: DayOfWeek?, mealType: MealType?, target: String) -> URL?`
  - `WidgetDeepLink.parse(_ url: URL) -> WidgetDeepLink.Destination?` where `Destination` is `.today`, `.tomorrow`, `.meal(day: DayOfWeek, type: MealType)`

- [ ] **Step 1: Write the failing test**

Create `KhanaKit/Tests/KhanaKitTests/WidgetDeepLinkTests.swift`:

```swift
import XCTest
@testable import KhanaKit

/// The widget's tap targets. Round-tripped rather than asserted one way, because
/// the widget builds these URLs and the app parses them — a drift between the two
/// is a tap that opens the wrong screen.
final class WidgetDeepLinkTests: XCTestCase {

    func testTodayAndTomorrowRoundTrip() {
        for (target, expected) in [
            ("today", WidgetDeepLink.Destination.today),
            ("tomorrow", WidgetDeepLink.Destination.tomorrow),
        ] {
            let url = WidgetDeepLink.url(target: target)!
            XCTAssertEqual(WidgetDeepLink.parse(url), expected)
        }
    }

    func testAMealLinkRoundTrips() {
        let url = WidgetDeepLink.url(day: .thursday, mealType: .eveningSnack)!

        XCTAssertEqual(
            WidgetDeepLink.parse(url), .meal(day: .thursday, type: .eveningSnack)
        )
    }

    func testTheURLShapeIsWhatTheSpecSays() {
        XCTAssertEqual(
            WidgetDeepLink.url(day: .thursday, mealType: .eveningSnack)?.absoluteString,
            "khanakyabanau://meal/thursday/eveningSnack"
        )
        XCTAssertEqual(
            WidgetDeepLink.url(target: "tomorrow")?.absoluteString,
            "khanakyabanau://tomorrow"
        )
    }

    func testForeignAndMalformedURLsParseToNil() {
        for raw in [
            "https://www.khanakyabanau.in/today",   // right host, wrong scheme
            "khanakyabanau://",
            "khanakyabanau://elevenses",
            "khanakyabanau://meal/thursday",         // missing meal type
            "khanakyabanau://meal/notaday/lunch",
            "khanakyabanau://meal/thursday/brunch",
        ] {
            XCTAssertNil(
                WidgetDeepLink.parse(URL(string: raw)!), "\(raw) should not have parsed"
            )
        }
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd KhanaKit && swift test --filter WidgetDeepLinkTests 2>&1 | tail -10
```

Expected: `error: cannot find 'WidgetDeepLink' in scope`.

- [ ] **Step 3: Implement it**

Create `KhanaKit/Sources/KhanaKit/Logic/WidgetDeepLink.swift`:

```swift
import Foundation

/// The URLs the widgets hand back to the app.
///
/// Both halves live here — the widget builds, the app parses — because a drift
/// between a builder and a parser in two different targets is a tap that silently
/// opens the wrong screen.
public enum WidgetDeepLink {
    public static let scheme = "khanakyabanau"

    public enum Destination: Hashable, Sendable {
        case today
        case tomorrow
        case meal(day: DayOfWeek, type: MealType)
    }

    public static func url(target: String) -> URL? {
        URL(string: "\(scheme)://\(target)")
    }

    public static func url(day: DayOfWeek, mealType: MealType) -> URL? {
        URL(string: "\(scheme)://meal/\(day.key)/\(mealType.key)")
    }

    public static func parse(_ url: URL) -> Destination? {
        guard url.scheme == scheme, let host = url.host else { return nil }
        switch host {
        case "today": return .today
        case "tomorrow": return .tomorrow
        case "meal":
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2,
                  let day = DayOfWeek(rawValue: parts[0]),
                  let type = MealType(rawValue: parts[1])
            else { return nil }
            return .meal(day: day, type: type)
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd KhanaKit && swift test --filter WidgetDeepLinkTests 2>&1 | grep -E "Executed|error:"
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Register the scheme in `App/Info.plist`**

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>in.khanakyabanau.app</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>khanakyabanau</string>
			</array>
		</dict>
	</array>
```

- [ ] **Step 6: Handle the URL in the app**

In `App/AppRootView.swift`, add to the `KkbBackground { ... }` chain, next to the existing `.task` and `.onChange`:

```swift
        .onOpenURL { url in
            guard let destination = WidgetDeepLink.parse(url) else { return }
            // Routed through `pendingDestination` rather than a second navigation
            // path: it already survives being set before `HomeView` exists, which
            // is the cold-launch case a widget tap always is, and reusing it means
            // a notification tap and a widget tap cannot drift apart.
            env.push.pendingDestination = switch destination {
            case .today: .today
            case .tomorrow: .tomorrow
            case let .meal(day, type): .mealDetail(day: day, type: type)
            }
        }
```

- [ ] **Step 7: Add the tap targets in the widget**

In `Widgets/WidgetDayContent.swift`, give the whole widget a fallback link and each row its own. `widgetURL` rather than `Link`, because `Link` is inert in some families:

In `WidgetDayContent.body`, add after the `VStack`:

```swift
        .widgetURL(WidgetDeepLink.url(target: entry.phase == .evening ? "tomorrow" : "today"))
```

and in `WidgetMealRow.body`, wrap the `HStack` content. The row needs to know
which day it belongs to, which after the pivot is not always today:

```swift
        // Per-row links need `Link`; the whole-widget `widgetURL` above is the
        // fallback for families where a row cannot own its own tap target.
        Link(destination: WidgetDeepLink.url(
            day: day, mealType: meal.type
        ) ?? WidgetDeepLink.url(target: "today")!) {
            // ...existing HStack...
        }
```

`WidgetMealRow` therefore needs the day, so add `let day: DayOfWeek` to it and pass `section.day` from `WidgetDayContent` — which is why sections carry their day rather than the entry carrying one. In the evening a tomorrow row must deep-link to tomorrow's meal, and a single entry-level day would send both sections to the same place.

- [ ] **Step 8: Build and run every suite**

```bash
xcodegen generate
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KhanaKyaBanauTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
cd KhanaKit && swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:"
```

Expected: `BUILD SUCCEEDED`; 78 app tests and 269 KhanaKit tests, 0 failures.

- [ ] **Step 9: Verify the taps by hand**

```bash
# With the app force-quit, so this is the cold-launch path:
xcrun simctl openurl booted "khanakyabanau://meal/thursday/breakfast"
```

Expected: the app launches straight onto Thursday breakfast's detail page. Then, from the home screen: tap a meal row on a placed widget and land on that meal; tap the header area and land on Today or Tomorrow.

- [ ] **Step 10: Update the README test counts**

```bash
grep -n "tests, all green" README.md
```

Update to the totals from Step 8, and add "widget snapshot, timeline and deep links" to the KhanaKit parenthetical.

- [ ] **Step 11: Commit**

```bash
git add KhanaKit/Sources/KhanaKit/Logic/WidgetDeepLink.swift \
  KhanaKit/Tests/KhanaKitTests/WidgetDeepLinkTests.swift \
  App/Info.plist App/AppRootView.swift Widgets/WidgetDayContent.swift README.md
git commit -m "feat: open the tapped meal from a widget"
```

---

## Appendix: deferred and out of scope

Carried from the spec, restated so nobody adds them mid-plan:

| | Why |
|---|---|
| Prep content in the widgets | Its own spec — `2026-09-04-prep-in-widgets-design.md`. Task 4 leaves `WidgetTimeline.entryDates(extraBoundaries:)` as the seam it plugs into, and Task 2's `WidgetMeal.prep` is already carried in the snapshot |
| Lock Screen and StandBy families | The ask was home screen. `.accessoryRectangular` is the obvious follow-up and the snapshot already supports it |
| Interactive widgets (`AppIntent` buttons) | Nothing on this surface is an action — it is a menu board |
| A configuration screen | Android deliberately has none; even an empty `android:configure` makes the system delete the widget on placement |
| Bringing `showCalories` to Android's widget | A real inconsistency, but it belongs in the Android repo |
| watchOS | No watch app exists |
