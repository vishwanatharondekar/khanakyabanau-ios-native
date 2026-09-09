# iOS Nav Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring iOS to the navigation and information architecture the webapp shipped in PR #207 and Android shipped on its own `nav-redesign` branch — three destinations on a tab bar (Today, Plan, Me), Shopping as a view of a week rather than a sheet, forward-only week selection, read-only history, and a capability seam a second brand can be a record in rather than a fork of.

**Architecture:** Every product decision lands in `KhanaKit/Sources/KhanaKit/Logic/` as pure Swift, testable with `swift test` and no simulator — the convention `ShoppingScope`, `WeekDates` and `PrepAfternoon` already set. Above that it is SwiftUI: `@Observable` view models owned by the shell so they survive tab switches, views under `App/Features/`. No new package.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17), Observation, XcodeGen, swift-testing + XCTest.

**Specs:** `docs/superpowers/specs/2026-09-08-nav-redesign-design.md` — read **"What changed while building it"** and **"For Android and iOS"** first; where the original sections disagree with those two, the later sections win.

**Reference implementation:** `~/projects/khanakyabanau-android-native` on branch `nav-redesign`, 15 commits. Every decision here was made there first; where this plan is terse, that branch is the worked example. The pure-logic files map one-to-one:

| KhanaKit (this plan) | Android | Webapp |
|---|---|---|
| `Logic/Brand.swift` | `core/model/Brand.kt` | `lib/brand.ts` |
| `Logic/WeekChips.swift` | `core/model/WeekChips.kt` | `lib/week-chips.ts` |
| `Logic/WeekHistory.swift` | `core/model/WeekHistory.kt` | `lib/week-history.ts` |
| `Logic/PastDays.swift` | `core/model/PastDays.kt` | `lib/past-days.ts` |
| `Logic/Greeting.swift` | `core/model/Greeting.kt` | `components/today/Greeting.tsx` |
| `Logic/ShoppingOpen.swift` | `core/model/ShoppingOpen.kt` | `lib/use-shopping-list.ts` |

## Global Constraints

- **Port parity is the test oracle.** Every pure-logic file names the webapp file it mirrors in its doc comment. When they disagree, the webapp is the specification.
- **Brand differences are data, never a forked code path.** No `if brand.id == .kkb` in feature code, ever.
- **Copy is fixed:** `This week`, `Next week`, `Fill empty days`, `Regenerate week`, `Import plan`, `Clear week`, `Earlier weeks`, `Already happened · view only`, `Nothing planned for today`, `Plan your week`, `No meals yet this week`.
- **Verbs say what the action does.** *Share*, never *Download* or *PDF*. *Fill empty days* / *Regenerate week*, never *AI*.
- **Days as rows, courses as columns.** Collapsing a row is not a change to that; reorienting is.
- **Clear gets exactly one confirmation.** iOS already has one — do not add a second.
- **Safe areas come from the platform.** `TabView` and `safeAreaInset` handle the home indicator; do not reproduce the webapp's `env(safe-area-inset-*)` arithmetic.
- Test command: `cd KhanaKit && swift test`. Baseline is **292 tests, 0 failures**.
- New files under `App/` need `xcodegen generate` before an Xcode build sees them; new files under `KhanaKit/Sources/` are picked up by SPM automatically.
- Every task ends green and committed.

## Server dependencies — already live

Both shipped with webapp PR #207 and are on `main`:

- `GET /api/meals/weeks?from=<monday>&direction=back` → `{ weekStartDates: [String] }`.
- `POST /api/ai/get-shopping-list` with `cachedOnly: true` → the cached list, or `{ absent: true, cached: false }` with HTTP 200. A miss is an answer, not an error, and costs no AI call and no guest allowance.

## Where iOS differs from Android

Three real differences, all in iOS's favour — do not "fix" them into parity:

1. **The guest ceiling is known client-side.** `User.remainingShoppingLists` and `APIError.guestLimitReached` already exist. Android had neither and had to infer the limit from a 403; here `shoppingOpenOutcome` can be given a truthful `isGuestAtLimit` before spending anything, which is what the webapp does.
2. **`ShoppingListViewModel` already exists**, with `flushPending()` already written. Android had to grow both.
3. **Drill-downs are a `NavigationStack` path**, not full-screen early-returns, so Meal Detail and Tomorrow already get the swipe-back gesture. The tab bar must be hidden on those pushes — `.toolbar(.hidden, for: .tabBar)` — so they stay drill-downs rather than becoming peers of the three destinations.

## File structure

**Created — `KhanaKit/Sources/KhanaKit/Logic/`:** `Brand.swift`, `WeekChips.swift`, `WeekHistory.swift`, `PastDays.swift`, `Greeting.swift`, `ShoppingOpen.swift`.

**Created — `KhanaKit/Tests/KhanaKitTests/`:** `BrandTests.swift`, `WeekChipsTests.swift`, `WeekHistoryTests.swift`, `PastDaysTests.swift`, `GreetingTests.swift`, `ShoppingOpenTests.swift`.

**Created — `App/`:** `Features/Me/MeView.swift`, `Features/Week/PlanView.swift`, `Features/Week/WeekPicker.swift`, `Features/Week/WeekSubTabs.swift`, `Features/Week/WeekActions.swift`, `Features/Week/WeekHero.swift`, `Features/Week/PastWeekBar.swift`, `Features/ShoppingList/ShoppingPane.swift`, `Features/Today/GreetingHeader.swift`, `Features/Today/EmptyToday.swift`.

**Modified:** `KhanaKit/.../Models/User.swift`, `Models/ShoppingList.swift`, `Networking/DTOs.swift`, `Networking/Endpoints.swift`, `App/Services/MealRepository.swift`, `App/Services/AiRepository.swift`, `App/Core/AnalyticsEvents.swift`, `App/Features/Home/HomeView.swift`, `App/Features/Week/WeekView.swift`, `App/Features/Week/WeekViewModel.swift`, `App/Features/Today/TodayView.swift`, `App/Features/Week/DayCard.swift`.

**Deleted:** `App/Features/Home/AppDrawer.swift` (becomes `MeView`), `WeekView`'s `WeekHeader` and `actionRow`.

---

## Task 1: The capability seam

Ships exactly ONE brand. What is not speculative is the rule that makes a brand deletable later: differences are data, never a forked code path.

**Files:** create `KhanaKit/Sources/KhanaKit/Logic/Brand.swift`, `KhanaKit/Tests/KhanaKitTests/BrandTests.swift`; modify `KhanaKit/Sources/KhanaKit/Models/User.swift`.

**Produces:** `BrandID`, `BrandCapabilities`, `BrandLabels`, `Brand`, `Brand.current`, `canImportPlan(_:for:)`, `canGenerate(_:for:)`, `canEditPlan(_:)`, `primaryGenerateLabel(_:hasEmptySlots:)`, `UserFeatures`, `User.features`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import KhanaKit

@Suite("Brand capability seam — mirrors the webapp's lib/brand.ts")
struct BrandTests {
    let brand = Brand.current

    private func user(isGuest: Bool = false, pdfImport: Bool = false) -> User {
        var u = User.stub()
        u.isGuest = isGuest
        u.features = UserFeatures(pdfImport: pdfImport)
        return u
    }

    @Test func kkbHasEveryCapability() {
        #expect(brand.capabilities.aiGeneration)
        #expect(brand.capabilities.pdfImport)
        #expect(brand.capabilities.readyMadePlans)
        #expect(brand.capabilities.canEditPlan)
    }

    @Test func labelsSayWhatTheActionDoes() {
        #expect(brand.labels.fillWeek == "Fill empty days")
        #expect(brand.labels.regenerateWeek == "Regenerate week")
        #expect(brand.labels.importPlan == "Import plan")
        #expect(brand.labels.emptyTodayTitle == "Nothing planned for today")
        #expect(brand.labels.emptyTodayCTA == "Plan your week")
        #expect(brand.labels.emptyWeekTitle == "No meals yet this week")
    }

    @Test func importNeedsTheUserFlag() {
        #expect(!canImportPlan(brand, for: user(pdfImport: false)))
        #expect(canImportPlan(brand, for: user(pdfImport: true)))
    }

    @Test func guestsNeverImport() {
        #expect(!canImportPlan(brand, for: user(isGuest: true, pdfImport: true)))
    }

    @Test func noUserMeansNoImport() {
        #expect(!canImportPlan(brand, for: nil))
    }

    @Test func aBrandWithoutImportRefusesAFlaggedUser() {
        var b = brand
        b.capabilities.pdfImport = false
        #expect(!canImportPlan(b, for: user(pdfImport: true)))
    }

    @Test func guestsMayGenerate() {
        #expect(canGenerate(brand, for: user(isGuest: true)))
    }

    @Test func noUserMeansNoGeneration() {
        #expect(!canGenerate(brand, for: nil))
    }

    @Test func aBrandWithoutAIRefusesEveryone() {
        var b = brand
        b.capabilities.aiGeneration = false
        #expect(!canGenerate(b, for: user()))
    }

    @Test func editingFollowsTheBrandAlone() {
        #expect(canEditPlan(brand))
        var b = brand
        b.capabilities.canEditPlan = false
        #expect(!canEditPlan(b))
    }

    @Test func featuresDefaultOffSoAnOldProfileCannotGrantOne() {
        #expect(!User.stub().features.pdfImport)
    }

    @Test func generateLabelNamesThePromise() {
        #expect(primaryGenerateLabel(brand, hasEmptySlots: true) == "Fill empty days")
        #expect(primaryGenerateLabel(brand, hasEmptySlots: false) == "Regenerate week")
    }
}
```

`User.stub()` may not exist. Check how the existing KhanaKit tests build a `User`; if there is no helper, construct one inline with the real initialiser and drop the helper — do not add a stub to production code.

- [ ] **Step 2: Run and watch it fail** — `cd KhanaKit && swift test --filter BrandTests`. Expected: compile failure, `cannot find 'Brand' in scope`.

- [ ] **Step 3: Add `features` to `User`**

```swift
/// Per-user feature switches from the profile endpoint. Login, register and
/// guest responses omit the object entirely, so every flag defaults to off:
/// a missing answer must never read as a granted capability.
public struct UserFeatures: Codable, Hashable, Sendable {
    public var pdfImport: Bool

    public init(pdfImport: Bool = false) {
        self.pdfImport = pdfImport
    }
}
```

Add `public var features: UserFeatures` to `User`, defaulting to `UserFeatures()` in the memberwise init. `User` has a custom `init(from:)` — decode it there with `decodeIfPresent`, defaulting to `UserFeatures()`, the same way the other optional profile fields are handled.

- [ ] **Step 4: Write `Brand.swift`** — a direct port of `core/model/Brand.kt` from the Android branch, keeping the doc comments verbatim (they carry the reasoning, and it is the same reasoning). Swift shapes: `enum BrandID { case kkb }`, `struct BrandCapabilities`, `struct BrandLabels` (with `emptyTodayCTA: String?`), `struct Brand` with `static let current`. Free functions `canImportPlan(_ brand: Brand, for user: User?) -> Bool`, `canGenerate(_:for:)`, `canEditPlan(_:)`, `primaryGenerateLabel(_:hasEmptySlots:)`.

- [ ] **Step 5: Run green** — `swift test --filter BrandTests`, 12 tests.
- [ ] **Step 6: Whole suite** — `swift test`. Expected 292 + 12.
- [ ] **Step 7: Commit** — `feat: capabilities decide which actions exist, not brand checks`

---

## Task 2: Which weeks the planner offers

**Files:** create `Logic/WeekChips.swift`, `Tests/KhanaKitTests/WeekChipsTests.swift`.

**Produces:** `WeekChipKind`, `WeekChip`, `buildWeekChips(today:weeksWithPlans:)`, `isOffRails(_:in:)`.

**Watch the fixtures.** `2026-09-07` is a Monday; `2026-09-08` is a Tuesday. Getting this wrong produced ten spurious failures against a correct implementation on the webapp.

- [ ] **Step 1: Write the failing tests** — port `WeekChipsTest.kt` verbatim, as a `@Suite`. The nine cases: this-and-next always and in order; a Monday is its own start; a Sunday belongs to the Monday's week; further weeks with plans get `d MMM` chips, sorted; the two fixed chips never duplicate; past weeks are not offered; duplicates collapse; a malformed date does not take the strip down; `isOffRails`.

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Write `WeekChips.swift`.** Use `PlanDate` (KhanaKit's existing ISO date type) rather than `Date` + formatters — `WeekDates` already works in it, and it compares as a string correctly. Month labels come from a hardcoded `["Jan", ...]` array, not `DateFormatter`: the chip must read the same in every locale, because the week key it names is a fixed ISO string.

- [ ] **Step 4: Run green** (9 tests). **Step 5: Commit** — `feat: the weeks on offer come from the data, not a pager`

---

## Task 3: Weeks and days that have already happened

**Files:** create `Logic/WeekHistory.swift`, `Logic/PastDays.swift`, and both test files.

**Produces:** `earlierHorizon`, `isPastWeek(_:today:)`, `earlierWeekStarts(_:count:)`, `nearestEarlierWeekWithPlan(_:in:)`, `pastDaysInWeek(_:today:)`, `isPastDay(_:day:today:)`.

- [ ] **Step 1: Write the failing tests** — port `WeekHistoryTest.kt` (8 cases) and `PastDaysTest.kt` (6 cases).
- [ ] **Step 2: Run and watch them fail.**
- [ ] **Step 3: Write both files**, porting the Android versions including doc comments. `pastDaysInWeek` returns `[DayOfWeek]`; the current week's answer is `Array(DayOfWeek.allCases.prefix(weekdayIndex))` where `weekdayIndex` is Monday-based — take it from `WeekDates`, which already computes Monday-based indices for `todayIndex`, rather than deriving it from `Calendar` (whose `weekday` is Sunday-based, and is exactly the off-by-one this is prone to).
- [ ] **Step 4: Run green** (14 tests). **Step 5: Commit** — `feat: know which weeks and days have already happened`

---

## Task 4: Ask the server which weeks hold a plan

**Files:** modify `Networking/Endpoints.swift`, `Networking/DTOs.swift`, `App/Services/MealRepository.swift`; create `Tests/KhanaKitTests/WeeksWithPlansTests.swift`.

**Produces:** `WeeksWithPlansResponse`, `Endpoints.weeksWithPlans(from:direction:)`, `MealRepository.weeksWithPlans(from:direction:)`.

The endpoint answers with week start dates only — rendering four chips must not cost a month of meal documents. It is deliberately not a range scan: plans are keyed `mealPlans/{userId}_{weekStartDate}`, so the candidates are computable and fetched by key, needing no composite index.

- [ ] **Step 1: Write the failing test** — decoding `{"weekStartDates":[...]}`, `{"weekStartDates":[]}`, and `{}` (an older deployment omitting the key) to an empty array rather than a throw.
- [ ] **Step 2: Run and watch it fail.**
- [ ] **Step 3: Add the DTO** — `public struct WeeksWithPlansResponse: Decodable, Sendable { public var weekStartDates: [String] }` with a `decodeIfPresent ?? []` custom init.
- [ ] **Step 4: Add the endpoint**, following `Endpoints.history`'s query-item style:

```swift
/// Which nearby weeks already have a saved plan — upcoming from `from` by
/// default, or the ones before it with `direction=back`.
///
/// Bounded on both sides (12 weeks each way) and served by the datastore's
/// built-in key index, so browsing history costs what the chip strip costs.
public static func weeksWithPlans(from: String, direction: String? = nil) -> Endpoint
```

- [ ] **Step 5: Add `MealRepository.weeksWithPlans`** returning `[String]` and swallowing failure to `[]` — a missing chip must never take the week itself down.
- [ ] **Step 6: Run green.** **Step 7: Commit** — `feat: ask which weeks hold a plan, by key not by scan`

---

## Task 5: A free probe for the shopping list

**Files:** modify `Models/ShoppingList.swift`, `Networking/DTOs.swift`, `App/Services/AiRepository.swift`; create `Tests/KhanaKitTests/ShoppingListAbsentTests.swift`.

**Produces:** `ShoppingList.absent`, `ShoppingListRequest.cachedOnly`, `AiRepository.shoppingList(for:cachedOnly:)`.

Shopping is about to open itself when the tab is tapped. Firing the generating call on navigation would charge a guest for walking past, so the open probes first: `cachedOnly` answers "is there already a list?" for free, and only a miss starts a real generation.

- [ ] **Step 1: Write the failing test** — `{"absent":true,"cached":false}` decodes with `absent == true` and an empty `categorized`; a real list has `absent == false`; a response with no `absent` key is not absent.
- [ ] **Step 2: Run and watch it fail.**
- [ ] **Step 3: Add `absent`** to `ShoppingList` (defaulting false, decoded with `decodeIfPresent`).
- [ ] **Step 4: Add `cachedOnly`** to `ShoppingListRequest`, defaulting false so every existing call site is unchanged.
- [ ] **Step 5: Thread it** through `AiRepository.shoppingList(for:cachedOnly:)`.
- [ ] **Step 6: Run green.** **Step 7: Commit** — `feat: ask whether a shopping list exists without paying for one`

---

## Task 6: Three destinations on a tab bar, and Me to receive the drawer

Supersedes the segmented control and the drawer sheet. **These ship together**: deleting the drawer without Me strands every settings entry.

**Files:** create `App/Features/Me/MeView.swift`; modify `App/Features/Home/HomeView.swift`; delete `App/Features/Home/AppDrawer.swift`.

**Produces:** `AppTab` (`today`, `plan`, `me`), `MeView`.

- [ ] **Step 1: Add the tab enum** in `HomeView.swift`:

```swift
/// Where the app can be. Three, and only three.
///
/// Shopping is deliberately not here: it is a view of a week, and a fourth tab
/// would have to answer "shopping for which week?" — which it could only do by
/// carrying a second week selector that would drift out of sync with the first.
enum AppTab: String, Hashable { case today, plan, me }
```

- [ ] **Step 2: Write `MeView`** — the drawer's rows, regrouped, with **Reminders first**. Reuse `MenuRow` exactly as the drawer used it; the settings sheets are unchanged. Groups: **Reminders** (Prep reminders — for a guest, a row that says "Create an account to get soaking and thawing nudges" and opens the upgrade sheet); **Plan** (Dietary preferences, Meal settings); **App** (Language, then Create account + "Already have an account? Sign In" for a guest, or Account for a registered user).

  Reminders comes first because prep reminders are the feature people install the app for, they were the third item in the drawer, and the drawer told a guest nothing about them at all.

  Two omissions from the webapp's `/me`, both deliberate: **Saved recipe videos** has no standalone screen on iOS (videos are picked per meal through `RecipeVideoSheet`), and **Ready-made meal plans** is a web route with no iOS destination. `readyMadePlans` stays true in the brand record; it has nothing to point at here.

- [ ] **Step 3: Replace the shell.** In `HomeView`, swap the `VStack { header; SegmentedTabs; … }` for a `TabView(selection:)` with three tabs, keeping the `NavigationStack` **inside** the Today and Plan tabs so each keeps its own push stack. Delete `header`, `showingDrawer`, the drawer sheet, and the `SegmentedTabs` block.

- [ ] **Step 4: Keep the drill-downs drill-downs.** Add `.toolbar(.hidden, for: .tabBar)` to `TomorrowView` and `MealDetailView` in the `navigationDestination`, so a pushed screen covers the bar rather than sitting beside the three destinations.

- [ ] **Step 5: Point the deep link at the tab.** In `consumePendingDestination`, replace `tab = 0` with `selectedTab = .today`, keeping the comment's meaning.

- [ ] **Step 6: Delete `AppDrawer.swift`** and run `xcodegen generate`.
- [ ] **Step 7: Run `swift test`** (KhanaKit is untouched but must stay green) **and commit** — `feat: three destinations on a tab bar, and Me replaces the drawer`

---

## Task 7: Today opens with a greeting, and an empty Today is a designed state

**Files:** create `Logic/Greeting.swift`, `Tests/KhanaKitTests/GreetingTests.swift`, `App/Features/Today/GreetingHeader.swift`, `App/Features/Today/EmptyToday.swift`; modify `App/Features/Today/TodayView.swift`.

**Produces:** `greeting(forHour:)`, `firstName(_:)`, `GreetingHeader`, `EmptyToday`.

This replaces `TodayView`'s `header` — the gradient bar reading **"On today's card"**, which spends a full display-size line and a divider saying nothing the screen does not already say. The greeting says something, and costs less.

- [ ] **Step 1: Write the failing tests** — six cases: before noon morning, noon–17 afternoon, 17+ evening, first word only, no usable name is nil, extra whitespace is not the name.
- [ ] **Step 2: Run and watch it fail.**
- [ ] **Step 3: Write `Greeting.swift`** — `greeting(forHour hour: Int) -> String` and `firstName(_ name: String?) -> String?`. An `Int` hour, not a `Date`: the view already reads the clock, and the hour is the whole of what the rule depends on.
- [ ] **Step 4: Run green** (6 tests).
- [ ] **Step 5: Write `GreetingHeader`** — greeting plus first name on one line, weekday and date beneath. Use the same `.displayMedium` weight the old header had, so the top of Today keeps its visual anchor.
- [ ] **Step 6: Write `EmptyToday`** — a `PaperCard` taking `emptyTodayTitle` and `emptyTodayCTA` from the brand. A nil CTA renders no button, which is how a product whose users receive their plan says the same thing without offering an action.
- [ ] **Step 7: Wire into `TodayView`** — replace `header(model)` with `GreetingHeader(name:)`, and branch the meal cards: when every enabled type is empty, render `EmptyToday` with a CTA that switches the tab to Plan. `TodayView` gains `userName: String?` and `onPlanWeek: () -> Void`.
- [ ] **Step 8: `xcodegen generate`, `swift test`, commit** — `feat: Today greets you, and says so when there is nothing on it`

---

## Task 8: One week header, shared by both views of the week

**Files:** create `App/Features/Week/PlanView.swift`, `WeekPicker.swift`, `WeekSubTabs.swift`; modify `WeekViewModel.swift`, `WeekView.swift`, `HomeView.swift`.

**Produces:** `WeekPane` (`meals`, `shopping`), `WeekViewModel.chips`, `.earlierWeeks`, `.pane`, `.selectWeek(_:)`, `.refreshChips()`, `PlanView`, `WeekPicker`, `WeekSubTabs`.

Which week, then which view of it, in one place — because Meals and Shopping are siblings under the same week, and if either owned the selector the other would duplicate it or lose it. On the webapp, Shopping first shipped with no week selector at all for exactly this reason.

Two shapes, deliberately: the selector is a **pill** (it picks the scope), the view tabs are **underlined** (they pick the view of it). Making both pills said they were the same kind of control, and stacking two rounded containers made the header read as decoration.

- [ ] **Step 1: Add `chips`, `earlierWeeks`, `pane` to `WeekViewModel`.**
- [ ] **Step 2: Add `refreshChips()`** — both directions, each swallowing failure. Separate from the week load because an imported multi-week plan creates weeks that need chips without changing the displayed week. Call it from `load()`, `pullToRefresh()` and `selectWeek(_:)`.
- [ ] **Step 3: Replace the pager.** Delete `goToPreviousWeek`, `goToNextWeek` and `changeWeek(by:direction:)`; add `selectWeek(_ weekStartDate: String)` which no-ops on the current week, tracks `week_change` with a `chip_kind` of the tapped chip or `off_rails`, and loads. Add `selectPane(_:)`.
- [ ] **Step 4: Write `WeekPicker`** — a bordered pill showing the current week's label with a chevron, opening a `.sheet` (or `.confirmationDialog`) listing the chips with a checkmark on the current one. Off-rails weeks are labelled `Another week` rather than claiming to be a chip the strip knows about. Outlined rather than bare text: this doubles as the screen's title, and the border is what makes it a control.
- [ ] **Step 5: Write `WeekSubTabs`** — two equal-width underlined labels, Meals and Shopping.
- [ ] **Step 6: Write `PlanView`** — owns the header (picker + actions row, then sub-tabs) and switches the pane beneath. `WeekView` becomes the Meals pane and takes the model as a parameter rather than resolving its own.
- [ ] **Step 7: Strip `WeekHeader` from `WeekView`** and delete the composable and its `navButton`.
- [ ] **Step 8: Point `HomeView`'s Plan tab at `PlanView`.**
- [ ] **Step 9: `xcodegen generate`, `swift test`, commit** — `feat: one week header for both views, and no more pager`

---

## Task 9: Shopping builds itself when the tab opens

**Files:** create `Logic/ShoppingOpen.swift`, `Tests/KhanaKitTests/ShoppingOpenTests.swift`, `App/Features/ShoppingList/ShoppingPane.swift`; modify `ShoppingListSheet.swift`, `WeekViewModel.swift`, `PlanView.swift`.

**Produces:** `ShoppingOpen` (`show`, `generate`, `empty`, `past`, `limit`), `shoppingOpenOutcome(...)`, `ShoppingPaneState`, `WeekViewModel.openShopping()`, `.retryShopping()`, `ShoppingPane`.

Seven states, all real: `probing` (cheap, spends nothing), `loading` (the slow AI path), `ready`, `error`, `limit` (a guest needs an account, not a retry), `empty` (no dishes to derive from), `past` (the shop is over).

**Use the real guest ceiling.** Unlike Android, `User.remainingShoppingLists` exists — pass `isGuestAtLimit: (session.user?.remainingShoppingLists ?? 1) <= 0` so a guest at their limit is told before anything is spent, which is what the webapp does. Keep the `APIError.guestLimitReached` catch as the backstop.

- [ ] **Step 1: Write the failing tests** — six cases: a cached list shows whatever week it is; no dishes is empty; a past week is never generated for; a guest at their limit is told; otherwise opening is the request; emptiness is checked before the past.
- [ ] **Step 2: Run and watch it fail.**
- [ ] **Step 3: Write `ShoppingOpen.swift`** — the five-way `switch` in the same order as Android, with the same doc comment.
- [ ] **Step 4: Run green** (6 tests).
- [ ] **Step 5: Add `shoppingState` to `WeekViewModel`** and replace `buildShoppingList()` with `openShopping()` — probe, decide, generate — plus `retryShopping()` which skips the probe because it already missed. Guard against a second concurrent open with a stored `Task`, and cancel it when the week changes: a late response from a week the user has already left must not overwrite what they are looking at.
- [ ] **Step 6: Turn the sheet into a pane** — rename `ShoppingListSheet` to `ShoppingListContent`, drop the sheet chrome and the `onDismiss`, and delete its title header: the week selector and the Shopping tab directly above already say which week this is and what it is.
- [ ] **Step 7: Write `ShoppingPane`** — switches on the seven states. `past` gets no action button at all; generating for a week already gone would spend an AI call on a shop that is over.
- [ ] **Step 8: Mount it in `PlanView`** — `.task(id: weekStartDate) { await model.openShopping() }` on entry, and `.onDisappear { Task { await shoppingModel.flushPending() } }` so the debounced "already have" ticks survive a tab switch. As a tab there is no close button to flush on.
- [ ] **Step 9: Remove the old entry point** — the `.sheet(item: $model.shoppingSession)` in `WeekView`, and the `isBuildingShoppingList` arm of its `FullScreenLoader`; the pane renders its own loader and must not block navigation.
- [ ] **Step 10: `xcodegen generate`, `swift test`, commit** — `feat: shopping is a view of the week, and builds itself on open`

---

## Task 10: One primary action, everything rarer behind an overflow

**Files:** create `App/Features/Week/WeekActions.swift`, `WeekHero.swift`; modify `PlanView.swift`, `WeekView.swift`, `App/Core/AnalyticsEvents.swift`.

Four pills of equal weight said every action mattered the same. Shopping is a tab now and leaves the row; generate is only urgent on an empty week. Verbs change with the shapes: **PDF → Share** (the intent is sending the week to someone), **AI → Fill empty days / Regenerate week** (the AI is not the point).

- [ ] **Step 1: Add `Navigation.overflowOpen`** to `AnalyticsEvents`.
- [ ] **Step 2: Add `hasEmptySlots` and `isEmptyWeek`** as computed properties on `WeekViewModel`.
- [ ] **Step 3: Write `WeekActions`** — a Share button plus a `Menu` holding, in order: the generate label (when `canGenerate`), Import (when `canImportPlan` — false on iOS today, which is the seam doing its job), Earlier weeks (when there is one), and Clear week (when `canEdit`), destructive-roled. A SwiftUI `Menu` renders in its own presentation, so it cannot be clipped by its container — the webapp's two clipping bugs have no equivalent here.
- [ ] **Step 4: Write `WeekHero`** — shown only on an empty week, taking `emptyWeekTitle` and the generate label from the brand.
- [ ] **Step 5: Mount both** — actions in `PlanView`'s title row, hero at the top of `WeekView`'s list when `isEmptyWeek`. Delete `actionRow` from `WeekView`.
- [ ] **Step 6: `xcodegen generate`, `swift test`, commit** — `feat: one primary action and an overflow, with verbs that say what they do`

---

## Task 11: Past weeks are browsable, and read-only

**Files:** create `App/Features/Week/PastWeekBar.swift`; modify `WeekViewModel.swift`, `PlanView.swift`, `App/Features/Week/DayCard.swift`.

Read-only is not a restriction so much as the truth: you cannot change what you already ate. It also finally exercises `canEditPlan` with real users — the path the nutrition brand needs, which was a dead branch until now.

- [ ] **Step 1: Add `viewingPastWeek`, `canEdit`, `earlierWeek`** as computed properties on `WeekViewModel`. `canEdit` is brand capability **and** not history, as one gate, so a read-only brand and a past week take the same path through every write.
- [ ] **Step 2: Add `browseEarlier()` and `backToThisWeek()`.**
- [ ] **Step 3: Guard every write** — `confirmEdit`, `applySuggestion`, `clearWeek`, `generateWithAI`, and the `editing`/`suggesting` setters in `WeekView`'s row callbacks. Five guards on one flag, not a separate mode.
- [ ] **Step 4: Write `PastWeekBar`** — it has to say three things at once, because a past week otherwise looks exactly like the current one and someone will try to edit it: that this is history (`Already happened · view only`), that it cannot be changed, and how to get out. The backwards step lives here rather than in the header: a permanent pager is what the header replaced, and this one exists only once you have chosen to look back, disappearing at the oldest week rather than walking into empty years.
- [ ] **Step 5: Mount it** in `PlanView` above the pane when `viewingPastWeek`, and pass `onBrowseEarlier` into `WeekActions`.
- [ ] **Step 6: Make read-only visible** in `WeekDaySection`/`DayCard`: an empty slot renders a dash rather than an add affordance, and the edit and swap controls are absent. Not disabled — a read-only week should look deliberate, not broken. The video control stays: watching how something was cooked is not editing it.
- [ ] **Step 7: `xcodegen generate`, `swift test`, commit** — `feat: browse past weeks, read-only, only when asked for`

---

## Task 12: Days already gone stop asking to be planned

**Files:** modify `App/Features/Week/WeekView.swift`.

Generating from today leaves the earlier days of the current week empty — onboard on a Thursday and Monday to Wednesday have no meals, each offering to add one, an action that cannot mean anything. **Collapsing rows is not a change to the grid's orientation**; days stay rows and courses stay columns.

- [ ] **Step 1: Split the day list** on `pastDaysInWeek(model.weekStartDate)` — a disclosure row reading "N earlier days this week" above the upcoming days, expanding to show them. A wholly past week keeps all seven: collapsing them would leave the screen with nothing on it.
- [ ] **Step 2: Keep expanded past days read-only** — pass `canEdit: model.canEdit && !pastDays.contains(day)`, because a day that has gone is history even in a week that has not.
- [ ] **Step 3: `swift test`, commit** — `feat: days already gone stop asking to be planned`

---

## Task 13: Clear still asks exactly once

iOS already has one confirmation (`isClearConfirmOpen` → `.alert`). This task is a **verification**, not a change: confirm the overflow's Clear entry opens that same alert and does not add a second confirmation of its own, and that the alert's destructive button is the only path to `clearWeek()`.

- [ ] **Step 1: Read `WeekActions`' Clear entry and `WeekView`'s alert.** Confirm exactly one confirmation exists on the path.
- [ ] **Step 2: If a second crept in during Task 10, remove it.** Asking twice for the same action teaches people to dismiss the question.
- [ ] **Step 3: Commit only if something changed.**

---

## Verification before handing it over

- [ ] `cd KhanaKit && swift test` — green, 292 + ~47 new.
- [ ] `xcodegen generate` — the project picks up every new file under `App/`.
- [ ] A simulator build: `xcodebuild -scheme KhanaKyaBanau -destination 'platform=iOS Simulator,name=iPhone 16' build`

Then by hand, on a device or simulator — each is something a unit test structurally cannot catch:

- [ ] Cold launch lands on **Today**, whether or not today has meals.
- [ ] The tab bar sits above the home indicator, and is hidden on Meal Detail and Tomorrow.
- [ ] Swipe-back still works out of Meal Detail and Tomorrow, and returns to the tab it was opened from.
- [ ] A prep-reminder tap lands on Today with the prep card visible, from any tab.
- [ ] Switching to Shopping starts a fetch without blocking the tab bar; leaving mid-generation and returning finds the finished list rather than starting a second one.
- [ ] Ticking "already have", then switching tab immediately, persists the tick.
- [ ] A past week shows the bar, refuses every edit, and its Shopping tab says so rather than generating.
- [ ] Clear asks exactly once.
