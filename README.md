# KhanaKyaBanau — iOS

Native SwiftUI client for [khanakyabanau.in](https://www.khanakyabanau.in), at feature
parity with the Android app and talking to the same production backend.

## Getting started

```bash
brew install xcodegen        # once
xcodegen generate            # regenerate KhanaKyaBanau.xcodeproj after adding files
open KhanaKyaBanau.xcodeproj
```

`.xcodeproj` is generated and git-ignored — **edit `project.yml`, never the pbxproj**.

Build and test from the command line:

```bash
xcodebuild -scheme KhanaKyaBanau \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme KhanaKyaBanau \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
cd KhanaKit && swift test     # pure-logic suite, no iOS SDK required
```

**304 tests, all green:** 227 in `KhanaKit` (codec, week maths, shopping scope,
prep rules, API parsing), 63 app unit tests (PDF rendering incl. Indic scripts,
palette/appearance, meal-detail layout, shopping-list state, auth routing, prep
reminders, first-week seeding) and 14 UI journeys driven against the
**production** backend.

Two notes on the UI tests: they create real guest accounts and consume a guest's
three lifetime AI/shopping allowances, so don't loop them needlessly; and
`-only-testing` against a target whose files were added since the last
`xcodegen generate` reports `Executed 0 tests` **and still exits successfully** —
regenerate first.

## Installing on your own iPhone

Signing is already configured — `DEVELOPMENT_TEAM: HL88YQFR35` is in `project.yml`,
so it survives `xcodegen generate`. With the phone plugged in and unlocked:

```bash
./scripts/install-to-iphone.sh
```

That regenerates the project, builds, installs, and prints when the build expires.
Or just press ⌘R in Xcode with the phone selected.

**First time on a given phone**, iOS needs two things:
- Settings › Privacy & Security › **Developer Mode** › on, then restart.
- After the first install: Settings › General › **VPN & Device Management** ›
  your Apple ID › **Trust**.

### The 7-day limit

This is signed with a **free Personal Team**, so the provisioning profile lasts
7 days — the app then refuses to launch until it is reinstalled. Re-running
`./scripts/install-to-iphone.sh` renews it. Also: three sideloaded apps at a time,
and no *remote* push (`aps-environment` cannot be provisioned by a free account,
which is why it is opt-in — see `KKB_ENTITLEMENTS` in `project.yml`). Prep
reminders still work; see below.

A paid Apple Developer Program membership removes all three limits, and makes
TestFlight available — which is the better answer if you want this on your phone
permanently, or on anyone else's.

The app talks to the **live** backend, so your phone sees the same account and meal
plans as the web app and Android.

## Prep reminders without push

The server sends prep reminders as an FCM push, which needs an APNs token, which
needs `aps-environment` — so on a personally-signed build that path is simply
unavailable. The reminder itself does not actually need the server, though:
`PrepTonight` already derives it on-device from the meal plan, so
`App/Core/PrepReminderScheduler.swift` schedules the same reminder as a **local
notification**, using the same wording as the server's push
(`buildReminderCopy`, ported verbatim from `lib/prep-tonight.ts`). No entitlement,
no Firebase.

It re-lays the next **7 days** of reminders on sign-in, on foreground, after a week
is saved, and when the reminder time changes — replacing its own pending requests
rather than adding to them, so it converges instead of accumulating.

Two limits are inherent to scheduling locally, and the settings sheet says so:

- **Open the app at least once a week**, or the schedule runs past its horizon.
  (The same cadence as reinstalling, so in practice they coincide.)
- **Edits made on the web or on Android are not reflected** until this phone next
  opens the app.

The server push has neither limit, so it stays the primary path whenever a paid
membership and a real `GoogleService-Info.plist` are present — both mechanisms
carry the same `userInfo`, so a tap is handled identically either way.

## Layout

```
project.yml                XcodeGen manifest — the source of truth for the project
KhanaKit/                  Local SwiftPM package: models, business logic, networking
  Sources/KhanaKit/
    Models/                Meal, MealPlan, MealType, User, ShoppingList, …
    Logic/                 PlanDate, WeekDates, ShoppingScope, PrepTonight,
                           MealSuggestions, CuisineData, RecipeVideos
    Networking/            APIClient, Endpoints, DTOs, APIError
  Tests/KhanaKitTests/     Runs on any machine with a Swift toolchain
App/
  KhanaKyaBanauApp.swift   Entry point, AppRoute
  AppRootView.swift        The root switch over session state
  SessionStore.swift       Session state machine
  AppEnvironment.swift     Composition root, injected via @Environment
  Core/                    Keychain, tokens, analytics, push, translations
  Services/                Auth, meals, AI, settings, recipe-video repositories
  Features/                Auth · Onboarding · Home · Week · Today · ShoppingList
                           · RecipeVideo · Settings · Pdf
  DesignSystem/            Palette, type scale, PaperCard, SegmentedTabs, …
  Components/              MealThumbnail, Toast, SharePresenter
  Resources/               Assets, Noto fonts (PDF only), GoogleService-Info.plist
AppTests/                  App-layer tests (needs the iOS SDK)
```

Everything that can be tested without UIKit lives in `KhanaKit`, which is why the
package exists: `swift test` covers the codec, week maths, shopping-list scoping,
prep rules and API parsing without an iOS SDK or a simulator.

## Architecture notes

- **No navigation graph.** Android switches on session state and treats Tomorrow and
  Meal Detail as full-screen early returns. iOS keeps that shape: a root `switch` in
  `AppRootView`, plus a `NavigationStack` path for the two drill-downs so users get
  swipe-back.
- **`@Observable` view models**, `@MainActor`, one per screen, mirroring Android's
  `StateFlow<UiState>` structs. App-scoped stores (`SessionStore`,
  `SettingsRepository`, `RecipeVideoRepository`) come through `@Environment`.
- **One `APIClient` actor** with two timeout budgets: 10 s for ordinary calls and
  180 s for AI endpoints, which do not stream and can take most of a minute.

## Verified end to end

Against production, in the simulator: guest onboarding → Home; the week grid with
CDN dish images; writing a dish and proving it survives a server round-trip; edit,
clear-week confirmation and the AI prompt; shopping-list generation with correct
per-item "for <dish>" context and scope re-aggregation; all four settings screens;
Tomorrow with its prep-tonight box; and PDF export in Hindi rendering Devanagari
from the bundled Noto face.

## Things that will bite you

- **Never route from an auth response.** `POST /api/auth/login`, `/register` and
  `/guest` return only a subset of the user — `login` has no `onboardingCompleted`
  at all — so routing from them sends returning accounts back through onboarding,
  where finishing overwrites their saved cuisines. `SessionStore.signedIn()` always
  fetches `GET /api/auth/profile`, exactly as Android's `SessionViewModel` does.
  `ReturningUserRoutingTests` guards it.
- **The session token is not a JWT.** It is unsigned, non-expiring base64 of
  `{"userId":"…"}`, and the server cannot revoke it. It lives in the keychain and is
  discarded locally on sign-out. There is no refresh endpoint.
- **`Meal` is `String | Object` on the wire.** `Meal.swift` has a hand-written codec:
  a name-only meal encodes as a plain string, and `prep` is emitted **only** together
  with `prepFor`. See `MealCodecTests`.
- **`PUT /api/meals/{week}` replaces the entire grid.** Omitting `calories`,
  `videoUrl` or `prep` deletes them server-side for every slot in the week.
- **Never adopt the PUT response as local state.** It echoes what you sent with no
  image enhancement, so adopting it strips every resolved `imageUrl` and shimmers the
  whole week. `MealRepository.save` returns only the identifiers.
- **There is no `DELETE /api/meals/{week}`** — clearing a week is a PUT of the empty grid.
- **Guest quotas are lifetime, not daily**: 3 AI generations, 3 shopping lists.
  There is no paywall or subscription anywhere in this product.
- **The first week is generated during onboarding, and reads before it writes.**
  `FirstWeekSeeder` runs as phase 2 of `OnboardingView.finish()`, like Android's
  `OnboardingViewModel.complete()`. It diverges from Android in one way that
  matters: Android PUTs the AI grid without reading the week first, so a blip
  during onboarding can overwrite an existing plan. Here a week that already has
  meals — or one that could not be read — is never generated over, which is also
  what the web client does (`MealPlanner.tsx:246-280`, `:480`). Generation failure
  is silent by design; the user lands on Home and the Week tab's AI button is the
  retry. `FirstWeekSeederTests` guards both refusals.
- **Shopping-list scoping is client-side.** The server returns one full-week list;
  `ShoppingScope` recomposes it, so narrowing the day range costs nothing.
- **Week keys are the Monday, ISO `yyyy-MM-dd`, in device-local time.** `PlanDate` is
  a date-only type precisely so this arithmetic can't pick up DST bugs.

Cross-client behaviour (`ShoppingScope`, `PrepTonight`, `formatLeadTime`,
`CuisineData`, `RecipeVideos`) is ported line-by-line from the web app and Android. A
divergence there is a product bug, not an implementation detail — the tests pin it.

## Configuration

| Item | Status |
|---|---|
| Backend | `https://www.khanakyabanau.in` — hard-coded, same as Android |
| Bundle ID | `in.khanakyabanau.app` |
| Push | **Needs setup.** `Resources/GoogleService-Info.plist` is a placeholder; `PushService` detects it and skips Firebase entirely. See the comments in that file. |
| Analytics | Mixpanel, off unless a `MixpanelToken` is present in `Info.plist`. Event names are `{category}_{action}`, shared with the other clients; the `device` super-property is `ios-app`. See **Supplying the Mixpanel token** below. |

### Supplying the Mixpanel token

The token is never committed, matching the other two clients — the web app keeps it
in an env var, Android in a gitignored `local.properties`.

Create `Secrets.xcconfig` in the repo root (already gitignored):

```
MIXPANEL_TOKEN = <the project token>
```

`Analytics.xcconfig` includes it optionally and is wired to **Release only**, so an
archive gets the token and a debug run does not. Without the file the token is
empty, `AnalyticsService` no-ops, and everything still builds — a fresh clone needs
no setup.

Two things worth knowing:

- Debug pins `MIXPANEL_TOKEN` to empty *explicitly*. An exported `MIXPANEL_TOKEN`
  in your shell — which is how the Android build reads it — otherwise arrives as a
  build setting and would point debug runs at the production funnel.
- CI can pass `xcodebuild MIXPANEL_TOKEN=…`; a command-line setting outranks both
  the xcconfig and the environment.

## Releasing

`./release.sh` mirrors Android's script of the same name: it bumps the version,
regenerates the project, archives Release, exports an App Store `.ipa`, uploads it to
TestFlight, then commits the bump and pushes.

```
./release.sh --keep-version     # hold the version, bump the build
./release.sh                    # bump patch and build (1.0.0 -> 1.0.1)
./release.sh --no-upload        # stop at the .ipa, don't upload
./release.sh --dry-run          # print the plan, change nothing
./release.sh --help             # every flag
```

Output lands in `build/release/`.

### TestFlight credentials

The upload uses `xcrun altool`, which needs App Store Connect credentials in the
environment. An API key is preferred — it survives a password change and is scoped
to App Store Connect:

```sh
export ASC_KEY_ID=ABC123DEFG
export ASC_ISSUER_ID=<issuer-uuid>
# with AuthKey_ABC123DEFG.p8 in ~/.appstoreconnect/private_keys
```

Create the key under App Store Connect → Users and Access → Integrations, with the
App Manager role. An Apple ID with an [app-specific
password](https://appleid.apple.com) works too:

```sh
export ASC_APPLE_ID=you@example.com
export ASC_APP_PASSWORD=abcd-efgh-ijkl-mnop   # or @keychain:<name>
```

Neither secret is printed or passed as a literal argument — the password reaches
altool through its own `@env:` indirection, so it stays out of `ps` output.
Credentials are resolved *before* the archive, so a missing one costs a second
rather than a five-minute build, and `--dry-run` doubles as a preflight check for
them.

Uploading is the one irreversible step: a build number is spent the moment the
upload is accepted, whether or not that build is ever released. If a build number
is already taken, rerun with `--build=N` rather than retrying.

Three things it refuses to do quietly:

- **Build without a Mixpanel token.** A release without one ships with analytics
  disabled and nothing else fails, so this is a hard error. `--no-analytics` overrides.
- **Pretend an export succeeded.** An App Store export needs an Apple Distribution
  certificate; an "Apple Development" identity is not enough. If the export fails the
  archive is kept, and you can distribute it from Xcode's Organizer instead —
  which is also how you get that certificate the first time.
- **Silently skip the upload.** Missing credentials fail the run up front. Pass
  `--no-upload` if you actually want to stop at the `.ipa`.

## Not built (deliberate)

Dead code on Android, not resurrected here: the Amazon Fresh launcher (implemented but
never surfaced, and commented out on web), forgot/reset-password (analytics constants
only), `dish-preferences`, and the `portions` setting (always 1, no UI).

Web-only and out of scope: the SEO `/meal-plans` pages and plan import, PDF *import*,
admin tooling, and the marketing site.

Home-screen widgets are deferred; the data layer is kept App-Group-ready so a WidgetKit
extension can be added without restructuring.
