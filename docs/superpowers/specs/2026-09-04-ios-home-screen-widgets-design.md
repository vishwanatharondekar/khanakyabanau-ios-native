# iOS home screen widgets

One home screen widget that decides for itself whether you need today's menu or
tomorrow's, drawing on the same data as the two Glance widgets Android ships.

Prep content is specified separately, in
`2026-09-04-prep-in-widgets-design.md`. This spec covers the machinery: the
target, how data crosses the process boundary, and when it refreshes. Read this
one first — the prep spec assumes the snapshot described here exists.

## What Android ships

| | |
|---|---|
| Kinds | `TodayWidget`, `TomorrowWidget` — one shared `LargeDayContent` layout |
| Size | 4×3 default, drag-resizable 4×2 ↔ 4×4, width locked |
| Row | 72dp thumbnail, meal-type label, calorie pill, 2-line meal name |
| Tap | opens `MainActivity` — no deep link to a meal |
| Data | Hilt entry point straight into `authRepository`, `settingsRepository`, `mealsRepository.getWeek`, each bounded by a timeout (2s / 2s / 5s) with independent fallbacks |
| Refresh | 6-hour `WorkManager` job, plus `WidgetRefresher.requestRefresh()` fired by `MealsRepository` when a saved week `coversWidgetWeek` |

## Why it cannot be ported directly

An Android app widget runs **in the app's process**, so Glance reaches the real
repositories through Hilt. A WidgetKit extension is a **separate process** with
its own sandbox, its own container, a render memory budget around 30MB, and a
timeline it must hand back promptly. Nothing in `AppEnvironment` is reachable
from it.

Four things the app does not have yet are prerequisites:

| Needed | Today |
|---|---|
| A shared container | no `application-groups` entitlement |
| A token the extension can read | `KeychainStore.baseQuery` sets only `kSecAttrService`; the app and the extension get *different* default access groups, so the extension cannot see the session token |
| A deep link target | no `CFBundleURLTypes`, no `onOpenURL` anywhere in the app |
| A plan on disk to render | `MealRepository` is network-only; its only cache is in-memory image URLs |

### This needs a paid Apple Developer membership

App Groups and keychain access groups are both provisioned capabilities, and a
free Apple ID gets neither. `App/KhanaKyaBanau.entitlements` is deliberately
empty for exactly this reason today — push needs `aps-environment`, which a free
account cannot provision, so it lives in a second file selected by the
`KKB_ENTITLEMENTS` build setting.

**The widget follows that same pattern.** The extension is not built for a
free-account install, and the README's "Installing on your own iPhone" route
keeps working without it. This is a constraint to state before anyone starts,
not a surprise to hit at the signing step.

## Architecture: snapshot on disk, network as a top-up

The app owns the data path it already has; the extension renders what it is
given and only reaches the network when it can and needs to.

```
app process                          shared container                extension
───────────                          ────────────────                ─────────
MealRepository.getWeek/save
  └─ covers today or tomorrow?
       └─ WidgetSnapshotStore.write ──►  snapshot.json          ──►  read (always)
       └─ thumbnails (256px)        ──►  thumbnails/<key>.jpg   ──►  read (always)
       └─ WidgetCenter.reloadAllTimelines()
                                                                     └─ stale + token?
                                                                          └─ refresh
```

**Why snapshot-first.** It is the only arrangement where the widget renders at
all when the network is slow, the token is missing, or the extension is being
asked for a timeline while the device is offline — which is most of the times a
widget is actually asked to render. The network top-up then buys back what
Android gets for free from its 6-hour worker: freshness without opening the app.

**Why not extension-fetches-only.** It would make every render depend on a
round-trip inside a memory- and time-bounded process, and show nothing at all
until the first successful fetch.

**Why not snapshot-only.** The plan would go stale whenever the user does not
open the app, which for a meal planner is precisely the week they most need the
widget.

### The snapshot lives in KhanaKit

`WidgetSnapshot` and its store belong in `KhanaKit`, alongside the models they
carry — it is pure Foundation, the app and the extension both link it, and it is
covered by `swift test` with no simulator. This is the same reasoning that put
the codec and the prep selectors there.

```swift
public struct WidgetSnapshot: Codable, Sendable {
    public var isAuthenticated: Bool
    public var writtenAt: Date
    public var days: [WidgetDay]        // today and tomorrow, resolved when written
}

public struct WidgetDay: Codable, Sendable {
    public var day: DayOfWeek
    public var date: String             // ISO, so a rollover is detectable
    public var meals: [WidgetMeal]      // enabled types only, canonical order
}

public struct WidgetMeal: Codable, Sendable {
    public var type: MealType
    public var name: String
    public var calories: Int?
    public var thumbnailKey: String?    // file name in the container, not a URL
    public var prep: MealPrep?          // `meal.validPrep` only — see the prep spec
}
```

`thumbnailKey` rather than a URL is deliberate: the extension must never be the
thing that discovers it has to download an image.

### Writing it

A `WidgetSnapshotWriter` in the app, called from the same place Android calls
`requestRefresh()` — after `MealRepository` resolves or saves a week that
contains today or tomorrow — plus on sign-in, sign-out, and any change to
`enabledTypes`. Thumbnails are fetched at write time, resized to 256px (matching
Android) and written next to the JSON; the writer prunes files no longer
referenced so the container cannot grow without bound.

Writes are atomic (write to a temp file, then `replaceItem`), because a render
can happen mid-write.

### Reading it

`WidgetSnapshotReader.read()` returns `nil` rather than throwing when the file
is absent or unreadable, and the timeline provider treats `nil` exactly as it
treats unauthenticated: the "Tap to set up" shell. A widget that renders an
error where it could render an invitation is a worse widget.

## Token sharing, and the migration nobody should miss

To let the extension refresh, both targets get
`keychain-access-groups = $(AppIdentifierPrefix)in.khanakyabanau.shared`, and
`KeychainStore.baseQuery` gains a matching `kSecAttrAccessGroup`.

> **Adding an access group changes the item's identity.** Every existing user's
> token becomes invisible to the query that looks for it, and the app decides
> they are signed out. `TokenStore` must, once, read the token and the guest
> device id from the old group-less query, rewrite them into the shared group,
> and delete the originals. Without this, shipping the widget signs out the
> entire installed base — including guests, whose accounts are only reachable
> through `guest_device_id` and would be **permanently orphaned**.

That migration deserves its own test before any widget code is written.

## Targets and configuration

`project.yml` gains one target — the `.xcodeproj` is generated, so this is the
only place it is described:

```yaml
  KhanaKyaBanauWidgets:
    type: app-extension
    platform: iOS
    sources: [Widgets]
    dependencies:
      - package: KhanaKit
        product: KhanaKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: in.khanakyabanau.app.widgets
        INFOPLIST_FILE: Widgets/Info.plist
        CODE_SIGN_ENTITLEMENTS: "$(KKB_WIDGET_ENTITLEMENTS)"
```

with `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, and the app
target taking it as an embedded dependency. `KKB_WIDGET_ENTITLEMENTS` mirrors
the existing `KKB_ENTITLEMENTS` switch.

Anyone adding files here regenerates with `xcodegen generate` — the README
already warns that `-only-testing` against a target with unregenerated files
reports "Executed 0 tests" and still exits successfully.

## What is shown

**One kind, which decides for itself what day to show.** Android ships two
widgets, `TodayWidget` and `TomorrowWidget`, and the first draft of this spec
copied that. It is the wrong shape for a home screen: a Tomorrow widget is dead
space for most of the day, and asking someone to place two widgets to get one
coherent answer is asking them to do the app's thinking.

Instead the widget is time-aware, because WidgetKit makes that the cheap option.
A timeline is a list of entries each stamped with the moment it becomes valid, so
"what to show at 19:00" is decided when the timeline is built, not by reading a
clock at render time. Several phase changes a day cost **one** reload, not one
each.

`StaticConfiguration` still, and now for a better reason than Android parity:
there is nothing left to configure. If someone wants tomorrow's plan while the
widget is showing today's, the app is one tap away — a better experience than a
widget long-press and a picker.

### The pivot

`WidgetPhase.eveningPivotMinutes` — 17:00, the same value as
`nominalMealTimes[.eveningSnack]` — lives in `KhanaKit` beside the prep selectors
so it is shared and testable.

**The body never shows a meal that has already been eaten.** Every phase renders
`WidgetPhase.upcoming` — today's meals whose nominal time is still ahead — so
breakfast stops occupying a row at 08:00 and lunch at 13:00. By mid-afternoon the
widget is about dinner without that being a special case anywhere.

| Phase | When | Body |
|---|---|---|
| `.today` | Meals still ahead, before the pivot | What is left of today |
| `.tonight` | Meals still ahead, after the pivot | What is left of today, then tomorrow beneath a `TOMORROW` divider |
| `.tomorrow` | **Nothing left to cook today** | Tomorrow's plan, in full |

The phase turns on *what remains*, not on the clock alone. A household with only
breakfast enabled is finished by 08:00 and should be looking at tomorrow long
before any fixed evening hour; one that eats late is still on today at 20:00.
Asking "is there anything left?" answers both without either being special.

The pivot's job is narrower than it first looks: it decides only when tomorrow
becomes worth *previewing* alongside what is left. Before it, dinner is still
today's business. After it, the useful question has become what happens next.

A wall-clock constant rather than a value derived from enabled meal types: a user
with `eveningSnack` disabled still wants the evening to begin at the same time,
and deriving it would make the pivot jump when someone edits their settings.

| Family | Content |
|---|---|
| `.systemSmall` | the next meal still to come, its name, and its prep line — inherently rolling, so it needs no phase logic and crosses midnight on its own |
| Every family | a time-aware greeting in place of a static `TODAY` eyebrow, and a warm gradient ground. Both cost no height, which is the only currency a widget has |
| `.systemMedium` | three meal rows with thumbnails — Android's 4×2 — or four when no prep banner is showing |
| `.systemLarge` | every enabled meal — Android's 4×4 |

Rows are identical to Android's: thumbnail, meal-type label, calorie pill, meal
name over two lines. Calories follow the app's `showCalories` setting, which
Android's widget does not currently honour — the app gates on it and the widget
should not disagree with the app on the same device.

### This diverges from Android, deliberately

Android keeps two widgets and this keeps one. That is a real inconsistency, and
it is accepted rather than overlooked: the Android widgets already ship, retiring
one is a change to a surface users have already placed on their home screens, and
it belongs in the Android repo as its own decision. The prep work in
`2026-09-04-prep-in-widgets-design.md` is unaffected either way — its banner rule
was already written to be identical across kinds.

Every family sets `.containerBackground(for: .widget)`. Without it the widget
renders blank in StandBy and on iPad.

### States

Mirroring Android's copy exactly, so screenshots and support answers match:

| Condition | Shown |
|---|---|
| No snapshot, or not authenticated | "Tap to set up" |
| Authenticated, no meals written | "Open the app to pick meals" |
| Snapshot unreadable | "Couldn't load today's plan" |
| Today cooked, tomorrow unplanned | "That's today sorted · Tap to plan tomorrow" |
| No App Group (DEBUG only) | names the missing entitlement, rather than impersonating a signed-out user |

The rested state earns its place: it is where every user lands each evening once
dinner is behind them, and a blank card would read as a broken widget rather than
a finished day.

## Deep links

Android opens `MainActivity` and stops there. iOS can do better cheaply, because
the app already has the machinery: `PushService.pendingDestination: AppRoute?`,
consumed by `HomeView.consumePendingDestination()`, which already handles being
set before the view exists — the cold-launch case.

Register `khanakyabanau://` and add `.onOpenURL` to the root, parsing:

```
khanakyabanau://today
khanakyabanau://tomorrow
khanakyabanau://meal/<day>/<mealType>
```

into the same `AppRoute` values and assigning `pendingDestination`. Each meal row
gets a `widgetURL` (`Link` is not available in every family), so tapping a meal
lands on that meal rather than the app's front door.

Reusing `pendingDestination` rather than adding a second routing path means the
notification tap and the widget tap cannot drift apart.

## Refresh

Two mechanisms, neither of which is a polling loop:

**The app pushes.** `WidgetCenter.shared.reloadAllTimelines()` after every
snapshot write. This is the equivalent of Android's `requestRefresh()`, and is
what makes an edit in the app show up on the home screen immediately.

**The timeline schedules itself.** Entries are generated for: now, the evening
pivot if it is still ahead, each remaining prep start time today (see the prep
spec — this is what makes the urgency banner correct without spending refresh
budget), and the next local midnight, with `.after(nextMidnight)` so the day
rolls over on its own.

The pivot is one more date in that list, which is the entire cost of making the
widget time-aware. Entries are capped at 12 so a week with unusually heavy prep
cannot generate an unbounded timeline; the cap drops the furthest-out prep
entries first, since those are the ones already visible on their meal's row.

WidgetKit allows roughly 40–70 timeline reloads a day. Putting the clock into
*entry dates* rather than into reloads is what keeps this comfortably inside the
budget, and it is strictly better than Android's 6-hour tick.

The extension refreshes from the network only when the snapshot is older than
six hours *and* a token is readable, bounded by the same timeouts Android uses,
falling back to the snapshot on any failure.

## Testing

**KhanaKit (`swift test`, no simulator):**

- `WidgetSnapshot` codec round-trip, including a meal with no thumbnail, no
  calories and no prep.
- The snapshot writer's day resolution across a Sunday→Monday rollover — the
  case Android calls out in `loadTomorrowSnapshot`, where tomorrow belongs to
  next week's plan.
- `WidgetTimeline.entryDates(snapshot:now:)` as a pure function: prep boundaries
  today, the evening pivot, plus midnight, sorted, deduplicated, never in the
  past, and capped at 12.
- `WidgetPhase.phase(at:calendar:)`: today's plan before 17:00, tonight-plus-
  tomorrow after it, and the boundary itself resolving to the evening phase.
  Worth a DST case — on a day with no 17:00 the pivot must still fall exactly
  once, which is the bug a naive `date + 17h` would ship.

**App tests:** the keychain migration — a token written the old way is readable
after migration and the old item is gone; and a guest device id survives it.
This is the highest-consequence test in the change.

**Manual:** placement in all three families; the widget observed across the
evening pivot without being touched, which is the one behaviour no unit test
proves; a meal tap landing on the right meal from a cold launch; the widget with the app force-quit; airplane mode
falling back to the snapshot rather than an error tile.

## Out of scope

| | Why |
|---|---|
| Lock Screen and StandBy families | The ask was home screen. `.accessoryRectangular` is the obvious follow-up and the snapshot already supports it |
| Interactive widgets (`AppIntent` buttons) | Nothing on this surface is an action — it is a menu board |
| A configuration screen | Nothing left to configure once the widget picks the day itself; see above |
| Pinning a day ("always show tomorrow") | The app is one tap away, and it answers the question better than a widget can. Add only if asked for |
| Bringing `showCalories` to Android's widget | Real inconsistency, but it belongs in the Android repo, not in this change |
| watchOS | No watch app exists |
