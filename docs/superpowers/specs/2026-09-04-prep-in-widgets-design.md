# Preparation in the home screen widgets

The widgets say what you are eating. They say nothing about what you should
already be doing about it — and advance prep is the one part of a meal plan that
fails silently, because by the time you look at the menu it is too late to soak
anything.

Two additions, on both platforms:

1. **A prep line on each meal row** — what this dish needs in advance, clock-free.
2. **An urgency banner above the rows** — what has to be started now, or soon.

> **This spec is cross-repo.** It covers `khanakyabanau-ios-native` and
> `khanakyabanau-android-native`. It lives in the iOS repo because that is where
> it was written, alongside the widget spec it depends on.

**Depends on** `2026-09-04-ios-home-screen-widgets-design.md` for iOS — there is
no iOS widget to add this to yet. On Android the widgets already exist, so the
Android half can ship first and independently.

## Why

The prep reminders already exist on both platforms — an evening push for
tomorrow's meals, an afternoon one for tonight's. But a notification is a
*moment*: it fires once, it is dismissed in a second, and if it arrives while
you are driving it is gone. A widget is ambient. It is the right surface for
"the chana needed to go in water two hours ago", because it is still saying so
when you next look at your phone.

The data is already there and already correct. Every dish in the plan carries
`validPrep`, and both platforms already have selectors that decide which steps
genuinely have to be started when — they are what drives the reminders. Nothing
here needs new server data or a new API call.

## The rule

### The per-meal line is clock-free

Under each meal name, the row shows that dish's earliest prep step:

```
💧 Soak chana overnight · 8 hours ahead
```

Category emoji from `PrepCategory.emoji`, the step's own `text`, and
`formatLeadTime(step.leadTimeMinutes)` — the exact wording the app already shows
in `PrepAheadBadge`, so the widget and the app never disagree in front of the
user. Several steps show the longest-lead one and `+N`.

Deliberately no clock here. A row is a fact about the dish, not about the
present, and keeping time arithmetic out of it keeps rollover and time-zone
bugs confined to one place — the banner.

Rows show a prep line **only** when `meal.validPrep` has steps. Absent prep and
empty prep both render nothing, for the reasons `PrepTonight` documents: a slot
with no prep has never been through generation and we do not know what it needs,
while a slot with an empty list has and genuinely needs nothing.

### The banner is the clock

One new pure function in `KhanaKit`, alongside the selectors it composes:

```swift
public struct PrepDue: Hashable, Sendable {
    public var item: PrepTonightItem
    public var startAt: Date
    public var isOverdue: Bool
}

public enum PrepNow {
    /// What has to be started now or within `horizon`, ordered by start time.
    ///
    /// Composes the two existing selectors rather than reimplementing their
    /// rules — whatever the reminders say, the widget says.
    public static func due(
        today: DayMeals,
        tomorrow: DayMeals,
        enabledTypes: [MealType],
        now: Date,
        calendar: Calendar,
        horizon: TimeInterval = 3 * 3600
    ) -> [PrepDue]
}
```

It resolves each selector's `startByMinutes` against the right midnight:

| Source | Relative to | Note |
|---|---|---|
| `PrepAfternoon.itemsForThisAfternoon(today)` | midnight **today** | always ≥ 07:00 by construction |
| `PrepTonight.itemsForTomorrow(tomorrow)` | midnight **tomorrow** | negative values land in this evening, which is the point |

It takes both days on purpose, and **the banner never varies with which day the
widget is showing**. Urgency is a property of the moment, not of the day you
happen to be looking at: at 19:00 the thing that has to go in water is tomorrow's
breakfast batter, and a widget that stayed silent about it because the step
belongs to tomorrow would be withholding the only time-critical fact on screen.

Concretely that means Android's two kinds show the same banner as each other, and
iOS's single time-aware widget shows the same banner either side of its evening
pivot (`2026-09-04-ios-home-screen-widgets-design.md`). The rule was written to
be independent of how many widgets a platform ships, so the iOS merge to one kind
changes nothing here.

Then classifies:

- **Overdue** — `startAt <= now`, and the meal's own nominal time is still in the
  future. Once dinner time has passed, a soak that should have started at noon is
  no longer advice, it is nagging; it drops out.
- **Soon** — `now < startAt <= now + horizon` (3 hours).
- Anything further out is not in the banner. It is already on its meal's row.

### Worked examples

Dinner is nominally 20:00, so an 8-hour soak has to start at 12:00.

| Now | Step | Banner |
|---|---|---|
| 09:30 | soak chana, 8h, today's dinner | *(nothing — 12:00 is beyond the 3h horizon)* |
| 11:00 | soak chana, 8h, today's dinner | `⏳ 12:00 · Soak chana overnight` |
| 13:00 | soak chana, 8h, today's dinner | `⏳ Start now · Soak chana overnight` |
| 21:00 | soak chana, 8h, today's dinner | *(nothing — dinner has passed)* |
| 19:00 | ferment batter, 14h, tomorrow's breakfast | `⏳ Start now · Ferment the dosa batter` |
| 13:00 | two steps due | `⏳ Start now · Soak chana overnight +1 more` |

## Copy

| State | Text |
|---|---|
| Overdue | `⏳ Start now · <step text>` |
| Soon | `⏳ <HH:mm> · <step text>` |
| More than one | append ` +N more` |
| Nothing due | no banner; the space returns to the meal rows |

The banner is terracotta on the marigold surface already used for prep notices in
the app (`Kkb.marigoldText` on `Kkb.marigoldSurface`, `WidgetColors.Marigold700`
on `Marigold100`), so it reads as the same object the user has seen inside the
app.

## Layout

| Surface | Banner | Per-meal line |
|---|---|---|
| iOS `.systemSmall` | yes — it is most of the point of the small family | yes, for the one meal shown |
| iOS `.systemMedium` | yes, one line above the rows | yes |
| iOS `.systemLarge` | yes | yes |
| Android 4×2 – 4×4 | yes, as the first `LazyColumn` item under the header | yes, a third line in the row's `Column` |

When the banner is absent the medium family shows one more meal row rather than
leaving a gap.

## iOS

- `PrepNow` in `KhanaKit`, tested by `swift test`.
- The widget snapshot already carries prep per meal. It must store
  **`meal.validPrep`**, not raw prep — the validity check belongs on the writing
  side so the extension never renders prep for a dish that has since been
  swapped.
- **The timeline is what makes the banner honest.** Entry dates include every
  `PrepDue.startAt` still ahead today, so the banner flips from `12:00` to
  `Start now` at exactly 12:00 with no refresh spent. This is the mechanism the
  widget spec's `WidgetTimeline.entryDates` exists for, and it is the one place
  iOS is strictly better than Android here.

## Android

- Kotlin `PrepNow` mirroring the Swift one, next to the existing selectors.
- `WidgetDaySnapshot` gains `prepDue: List<PrepDue>` and `WidgetMealItem` gains
  the dish's own steps; `loadDaySnapshot` already loads the week the selectors
  need, so no extra call.
- `LargeDayContent` grows a banner item above `items(...)`, and `LargeMealRow`'s
  `Column` grows a third `Text`.
- **Fidelity difference, accepted.** Android computes the banner at refresh
  time, so it can be up to six hours stale — `12:00` may still be showing at
  12:30. Adding an `AlarmManager` tick at each prep boundary would close it, and
  is deliberately not in this change: the prep *notification* already covers the
  urgent moment on Android, and the banner is a supplement to it. iOS gets exact
  timing for free from the timeline, so this is not worth divergent complexity.

## Testing

**The worked-example table above, twice** — once in `KhanaKitTests`
(`swift test`) and once in the Android JVM tests, with the same inputs and the
same expected banner strings. That table is the contract between the two
platforms; if they drift, one of the two suites goes red.

Both suites drive `PrepNow` with an injected `now` and a fixed calendar, so
neither has to reason about the real clock. Cases that matter:

- The 21:00 row — the meal has passed and the item is dropped.
- A negative `startByMinutes` from `itemsForTomorrow` landing in this evening.
- A step exactly on the horizon boundary, and one exactly at `now`.
- Empty prep vs absent prep, which must both yield nothing.
- A dish swapped after generation — `validPrep` nil — yielding nothing.

**iOS additionally:** `WidgetTimeline.entryDates` contains each future
`PrepDue.startAt`, so the flip to "Start now" is scheduled rather than hoped for.

**Manual:** place a widget with a dish that has prep due within the hour and
confirm the banner flips on its own without opening the app.

## Out of scope

| | Why |
|---|---|
| A separate prep-only widget kind | The banner rides on the widgets people will already have; a third kind competing for home-screen space needs evidence first |
| Ticking off a prep step from the widget | Interactive widgets are possible on iOS 17 and Glance, but nothing in the app tracks prep completion — there is no state to toggle |
| Changing the reminders | They are correct and this reuses their selectors verbatim. If the rules ever change, they change in one place and everything follows |
| Per-user meal times | `nominalMealTimes` is deliberately nominal; the reminders already made that call and the widget must not disagree with them |
