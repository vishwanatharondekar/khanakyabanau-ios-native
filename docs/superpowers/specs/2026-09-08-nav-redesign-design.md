# Navigation redesign (web)

The app's chrome is the last thing that hasn't kept up with the product. Two
tabs and a five-button toolbar were the right shape when the app did one thing;
today they hide half of it. Notifications — prep reminders, the single feature
users come back for — is the sixth item in a gear dropdown. The shopping list is
a modal that dies on refresh and can't be linked to. The week pager offers
infinite navigation in both directions when nobody wants either.

This design replaces the chrome. It does not touch the planner grid: days stay
as rows, courses stay as columns, on desktop and mobile both.

It is also the first half of a rebrand. A second brand is coming — a nutrition
product whose users receive a plan rather than compose one — and possibly the
retirement of Khana Kya Banau. That work is **not** in this spec. What is in this
spec is the seam it needs, and the reason that seam is here now is in
[Building for a brand that doesn't exist yet](#building-for-a-brand-that-doesnt-exist-yet).

Web only as designed — but it shipped, and this document is now the input for
the Android and iOS versions. **Read
[What changed while building it](#what-changed-while-building-it) before
anything else: roughly fifteen decisions below were superseded during
implementation, and several of the sections that follow describe a design we
abandoned.** [For Android and iOS](#for-android-and-ios) separates the
decisions that carry across platforms from the web mechanics that do not.

## Three destinations

```
Today  ·  Plan  ·  Me
```

Bottom bar on mobile, top nav on desktop. Both live in `AppChrome`, which is
already where `ViewNav` lives.

| Route | | Replaces | Holds |
|---|---|---|---|
| `/today` | destination | `/plan/[week]?mode=cook` | Today's and tomorrow's meals, tonight's prep |
| `/plan/[weekStartDate]` | destination | path unchanged | The week's grid |
| `/plan/[weekStartDate]/shopping` | *child of Plan* | a modal | That week's shopping list |
| `/me` | destination | the gear dropdown | Reminders, preferences, account |

Four routes, three destinations. Shopping is a route but not a place in the nav —
it was a candidate for a fourth destination and it is the wrong shape for one,
see [Shopping belongs to a week](#shopping-belongs-to-a-week).

`/today` needs no week parameter. Cook mode already derives its own week from
the current date rather than from the URL (`MealPlanner.tsx:1817`), so the week
in the address bar was never load-bearing for it — which is precisely why it
deserves a route of its own rather than a query string on somebody else's.

### Legacy URLs

`?mode=cook` is in bookmarks, in sent links, and in at least one shipped mobile
build's notification tap target. `/plan/[week]?mode=cook` must redirect to
`/today`, permanently.

There is already a redirect chain here: `?todaysMealsAvailable=true` rewrites to
`?mode=cook` (`app/(app)/plan/[weekStartDate]/page.tsx`). Extend it rather than
adding a second, parallel one — the old parameter should land on `/today` in one
hop, not two.

`/plan/[weekStartDate]` for **any** week keeps resolving, including weeks in the
past. Every weekly email ever sent contains
`https://www.khanakyabanau.in/plan/${weekStartDate}` (`lib/email-templates.ts:57`),
and those links outlive any navigation decision made here.

## Where the app opens

`/today`. Always — whether or not there is a plan for today.

`/home` is currently a redirect ladder that picks between two destinations, and
to pick it makes a blocking API call:

```
no token            → /
invalid token       → /
not onboarded       → /plan/[currentWeek]        (onboarding renders there)
today has meals     → /plan/[currentWeek]?mode=cook
today has no meals  → /plan/[currentWeek]
```

`checkTodaysMealsAvailable()` fetches the current week purely to choose between
the last two branches — and the page it redirects to then fetches the same week
again. Every app open pays two round-trips to answer a question the destination
is better placed to answer.

It also answers it slightly wrong. The check hardcodes
`['breakfast', 'lunch', 'dinner']` (`app/home/page.tsx`) and ignores the user's
`enabledMealTypes`, so someone whose enabled courses fall outside that trio is
told there is nothing today and sent to the grid.

Both problems disappear the moment the destination stops being conditional:

```
no token       → /
invalid token  → /
not onboarded  → onboarding
otherwise      → /today
```

`checkTodaysMealsAvailable()` is deleted. `/home` keeps its auth checks: it sits
outside the `(app)` route group, so it never gets `AppChrome`'s gate and cannot
simply be collapsed into it. Note the two are not equivalent even where they
overlap — `/home` sends a tokenless visitor to the marketing page, while
`AppChrome` starts guest onboarding. Merging them is a separate behavioural
change and is not part of this spec.

### Today with nothing on it

The state that used to be routed around now has to be designed. An empty Today
is a normal state, not a failure, and what it offers depends on whether this
user is allowed to do anything about it:

| `canEditPlan` | Empty Today shows |
|---|---|
| `true` | "Nothing planned for today" + **Plan your week →** |
| `false` | "Your plan for this week hasn't arrived yet" — no CTA |

The second row is the nutrition client, and it is the third place in this spec
where the capability seam does real work rather than sitting there as
scaffolding.

### After onboarding

Onboarding hands off to `/app`, which mounts the planner, generates the first
week in place, and leaves the user on the grid.

It should land on `/today` like every other entry. `/app` keeps the generation —
that is the only reason it exists, and `FullScreenLoader` already exists to
cover it — and replaces to `/today` once the week is written.

One thing to be careful about: a brand-new user who lands on Today has no idea a
whole week was just planned for them. That was fine when the week *was* the
landing screen. The mitigation is a one-time affordance on Today after the first
generation — "Your week is planned — see all 7 days →" — and it is mostly
belt-and-braces, because Plan is now a permanent destination in the nav instead
of something to be discovered.

## Shopping belongs to a week

A top-level Shopping tab has to answer *shopping for which week?* It can only do
that by carrying its own week selector — a second place to change weeks,
guaranteed to drift out of sync with the first — or by silently assuming the
current week, which is wrong in exactly the case that matters, when you are
planning next week's food.

Competitors get away with a Shopping tab because their lists aren't week-scoped.
Ours is.

So the list becomes a **child route of the week**, `/plan/[weekStartDate]/shopping`,
with a sub-tab strip under the week selector:

```
This week  ·  Next week          ← which week
Meals      ·  Shopping           ← which view of it
```

The week is chosen once, above; the sub-tab inherits it. Switching weeks keeps
you on whichever sub-tab you were on. There is no way to be looking at one
week's meals and another week's list.

This is not cosmetic. As a route the list survives a refresh, can be deep-linked
from a prep reminder or the weekly email, and — the real prize — the browser
back button works through the Instamart cart flow, which is a multi-step,
money-spending flow currently living inside a sheet.

### What this costs

`ShoppingListModal.tsx` is 1512 lines and takes eight props that
`handleGenerateShoppingList` computes inside `MealPlanner`
(`MealPlanner.tsx:1532`): ingredients, weights, categorised, mealPlan, dayWise,
haveAlready, newItems, orders.

The generation has to move with the list. Extract it into
`useShoppingList(weekStartDate)` — the page calls the hook, the hook owns the
fetch and the derived state. The modal's *content* becomes the page body; the
Instamart flow inside it is not rewritten, not refactored, and not touched
beyond what the container change forces.

This is the largest single item in the spec and the most likely to overrun. It
is also the only part that can be deferred without unpicking anything else: if
it slips, the list stays a modal fired from the week's overflow menu and the
sub-tab strip ships with one tab. Everything below still holds.

## Weeks: forward-only, data-driven

Nobody pages backwards through a meal planner, and nobody plans three weeks out.
The `◀ Prev / Next ▶` pager offers infinite navigation in both directions to
serve neither case.

Replace it with a chip row. What almost everyone sees, almost always:

```
This week  ·  Next week
```

The rule that generates it:

```
chips = {this week, next week} ∪ {future weeks that have a saved plan}
```

Forward only. Past weeks never get a chip.

### Why not just two chips

Because `buildWeekPlans` splits an imported PDF across however many weeks its
dates cover — `ImportPDFModal` reports *"Meal plan imported across N weeks"*
(`ImportPDFModal.tsx:185`), and `handlePDFImportComplete` already jumps the user
to `importedWeeks[0].weekStartDate` "so the import isn't invisible"
(`MealPlanner.tsx:1179`).

A nutritionist handing a client a four-week plan is not an edge case. It is the
core flow of the brand this app is being prepared for. With two hardcoded chips,
weeks three and four of that plan would exist in Firestore and be unreachable in
the UI. Hence the union with weeks that have plans:

```
This week  ·  Next week  ·  22 Sep  ·  29 Sep
```

Mixed labelling is deliberate. "This week" and "Next week" are how people refer
to the two weeks they care about; anything further out is a date, because that's
how people refer to those.

### Landing off the rails

A user arriving from a six-week-old email lands on a week with no chip. That
week renders normally, with a `← This week` affordance. Not a redirect, not an
error — the link did what it promised, and there is a way home.

Default chip is **This week**, always. `/today` covers immediacy; the week view
should not also try to guess.

### Looking backwards, solved elsewhere

Three reasons people look at past weeks, none of which a pager is the right
answer to:

**Avoiding repetition** is already solved, and solved better.
`buildInitialSuggestions(user, mealHistory, mealType, 8)` feeds cooking history
into the suggestion dropdown at the moment a dish is chosen — which is where
variety is actually decided, not by eyeballing two weeks side by side.

**Recalling a dish** is a dish lookup wearing a week lookup's clothes. A
searchable *Recently cooked* list in `/me` serves it strictly better than paging
back four weeks hoping to spot the thing.

> **Removed after implementation.** The list was built and then taken out: it
> read half a year of meal-plan documents to render, which is a real cost for a
> feature no one had asked for. So this need is currently **unserved** — the
> forward-only week strip stands on repetition being handled by
> `buildInitialSuggestions`, not on this. Whatever replaces it should still be a
> dish lookup rather than a way back through weeks.

**Checking adherence** — did I follow the plan — is a real need for the coming
nutrition brand and is deliberately not addressed here. It needs per-day
check-in data that doesn't exist yet, and it belongs in that brand's spec.

## In-week actions

Five buttons of equal visual weight, permanently docked, is the wrong answer to
a set of actions that are wanted at very different moments.

| Today | Becomes |
|---|---|
| Generate with AI / Regenerate with AI | **Fill empty days** / **Regenerate week** |
| Import PDF | label from brand config |
| Download PDF | **Share** |
| Shopping List | *(leaves — it's a sub-tab)* |
| Clear | *(overflow, with confirmation)* |

**Fill empty days / Regenerate week.** The labels finally say what the code
does. `generateAIMeals` branches on `hasEmptySlots()` and either fills only the
empty slots or replaces the entire week — two genuinely different operations
that "Generate with AI" and "Regenerate with AI" describe only vaguely. Dropping
"with AI" costs nothing; nobody chooses a meal planner for the acronym.

**Share, not Download.** Download is the mechanism. The intent is sending the
week to a partner, a cook, or a family group. Native share sheet with the PDF
attached where `navigator.share` supports files, download as the fallback. The
PDF generation itself (`lib/meal-plan-pdf.ts`) is unchanged — only how the
result is handed over.

**Clear survives, barely.** Regenerate already replaces a full week and a bad
import is fixed by re-importing, which leaves one genuine case: wanting an empty
week to fill by hand, with no other way to empty thirty-five cells. It stays,
but a destructive bulk action does not belong in the primary toolbar at equal
weight with everything else. Overflow, behind a confirmation.

### The empty-state trick

Mobile currently stacks a 64px header and a sticky five-button bar. Adding a
week chip row and a sub-tab strip on top of that would be three strips above any
content.

The state resolves it:

- **Empty week** — the primary action is a hero CTA in the body ("Fill the
  week"). The toolbar is minimal.
- **Filled week** — the CTA is gone. The toolbar is `[Share] [⋯]`, with
  Regenerate, Import and Clear inside the overflow.

Generate is only urgent on an empty week. On a filled week, Share is what
anyone actually wants. The permanent five-button bar stops existing.

## `/me`

The gear dropdown holds six destinations. The most important of them —
Notifications, which is where prep reminders are configured — is the last item,
and hidden entirely from guests.

`/me` is a list of rows in four groups:

| Group | Rows |
|---|---|
| **Reminders** | Prep reminders (evening + midday), notification hours |
| **Plan** | Dietary preferences, meal settings |
| **Kitchen** | Saved recipe videos |
| **App** | Language, ready-made meal plans, account, logout |

**The five existing settings components are not rewritten.** `DietaryPreferences`,
`MealSettings`, `VideoURLManager`, `LanguagePreferences` and
`NotificationPreferences` keep their current modal form; the rows on `/me` open
them exactly as the dropdown items do today. Turning them into sub-routes is a
later, separate improvement and carries none of this spec's value.

*Recently cooked* was specced here as the one new surface — a searchable list of
dishes from `mealHistory`. It shipped and was then removed on cost grounds; see
[Looking backwards, solved elsewhere](#looking-backwards-solved-elsewhere).

## Building for a brand that doesn't exist yet

A second brand is coming, and its users are the inverse of today's: they receive
a plan from a nutritionist rather than composing one. Khana Kya Banau itself may
be retired.

None of that is built here. But the shape of the navigation depends on it, and
discovering that in six months is expensive, so this spec introduces one seam.

**The seam is capability flags, not theming.** Colours don't change the shape of
a UI; capabilities do. Theming waits.

`lib/brand.ts` ships with exactly **one** brand:

```ts
export const brand = {
  id: 'kkb',
  capabilities: {
    aiGeneration: true,
    pdfImport: true,
    readyMadePlans: true,
    canEditPlan: true,
  },
  labels: {
    fillWeek: 'Fill empty days',
    regenerateWeek: 'Regenerate week',
    importPlan: 'Import plan',
  },
} as const;
```

One brand, not two. A registry of N brands, a tenancy model, a theme system —
all of it is speculative until the second brand is real. What is not speculative
is that every user-visible label and every conditional feature reads through
this object instead of being written inline.

The rule that makes a brand deletable later:

> Brand differences are expressed as **data**. Never as a forked code path.
> No `if (brand === 'kkb')` in feature code — ever. Retiring a brand should be
> deleting a record and its assets, with no change to any component.

### The flags earn their place immediately

`canEditPlan` is not hypothetical padding. If a nutritionist authors plans on her
own platform, her clients cannot edit theirs — no cell editing, no drag-to-swap,
no suggestion dropdown, no Clear, no import button. That strips most of
`PlanModeView`'s interaction surface.

`pdfImport` is already gated per user (`user.features.pdfImport`, enforced at
`app/api/meals/import-pdf/route.ts:73`). It now needs **both**: the brand flag
says the feature exists in this product, the user flag says it's enabled for this
person. Brand first, then user.

### The acceptance test that matters

> The navigation must be built and verified with
> `{ aiGeneration: false, canEditPlan: false, pdfImport: false }`.

Under those flags:

- The empty week reads *"Your plan for this week hasn't arrived yet"* — not an
  empty grid with no CTA.
- A filled week is a read-only grid with `[Share]` and nothing else.
- `/me` has no Ready-made Meal Plans row.
- Nothing renders a disabled button, an empty toolbar, or a dead overflow menu.

It must look deliberate, not broken. This is the whole reason the seam is in this
spec instead of the next one: without the test, the next brand discovers that the
navigation quietly assumed a Generate button existed.

## What gets deleted

- `ViewNav` in `AppChrome.tsx` — including the `weekInView` regex, which exists
  purely to preserve pager position across the Today/Week switch and has nothing
  to preserve once the pager is gone
- The settings dropdown and its outside-click handler
- The `◀ Prev / Next ▶` block in `PlanModeView`
- The mobile sticky five-button bar (`MealPlanner.tsx:2803`)
- The desktop five-button bar (`MealPlanner.tsx:2867`)
- `checkTodaysMealsAvailable()` in `app/home/page.tsx`, and the conditional
  branch of the redirect ladder it exists to feed — see
  [Where the app opens](#where-the-app-opens)

`CookModeView` (`MealPlanner.tsx:2122`) and `PlanModeView` (`MealPlanner.tsx:2448`)
move into their own files as part of this work. They are already self-contained
function components, and `/today` and `/plan` becoming separate routes makes
leaving them in one 3730-line module indefensible.

## Analytics

`AnalyticsEvents.NAVIGATION.MODE_SWITCH` currently records a two-way plan↔cook
switch. Three destinations need a destination property rather than a boolean
flip. Keep the event name — the existing funnels are worth more than the
tidiness — and add `to_destination` alongside the current `from_mode`/`to_mode`.

New events: shopping tab opened, week chip selected (with whether the chip was
this/next/dated), share invoked, overflow opened.

## Out of scope

Named explicitly, because each has been discussed and deferred on purpose:

- **Theming and the second brand** — Phase 3. This spec ships one brand.
- **Android and iOS** — their own specs, after this settles in production.
- **The planner grid** — days as rows, courses as columns, unchanged.
- **Tenancy, the nutritionist console, adherence check-ins, WhatsApp** — separate
  products, separate specs.
- **Rewriting the five settings modals** — `/me` opens them as they are.
- **Renaming internal namespaces** — no user sees a Kotlin package or a `Kkb`
  prefix, and churning them buys nothing.

## Risks

**The shopping list extraction overruns.** 1512 lines with a live payment flow
inside it. Mitigation is in [What this costs](#what-this-costs): the sub-tab
strip degrades to a single tab and the list stays a modal. Nothing else in the
spec depends on it.

**Legacy `?mode=cook` links break.** They arrive from bookmarks, sent links, and
shipped mobile builds that cannot be updated. The redirect is not optional and
should be covered by a test, not by inspection.

**Three strips on mobile.** Header, week chips, sub-tabs. The empty-state trick
removes the button bar that would have made it four, but the stacking still needs
looking at on a real device before it is called done.

**`canEditPlan: false` is never exercised in production** during this phase — no
real user has it. It can rot between this spec and the brand that needs it, so it
needs a test, not a manual check.

---

# What changed while building it

Everything above is the design as specified. This section is what shipped where
the two differ, and why. Where they conflict, **this section wins**.

## Mobile has no chrome but the bar

The spec said "bottom bar on mobile, top nav on desktop" and left it there. What
shipped goes further: on a phone there is **no header and no footer at all**.
Content, and a bottom bar.

The header was carrying a logo, a nav already hidden at that width, and a
profile link whose label is itself hidden below 768px — 64px of sticky chrome
for an icon, once the bar could reach `/me`. The footer is a wall of site links
that belongs to a web page, not to an app; it stays on the public marketing and
SEO pages at every width.

Removing the header exposed the notch, so the content reserves the top inset
itself. The bottom reserve is the bar's real height — its own height *plus* the
home-indicator inset it pads itself with — because a flat reserve buried the
last rows of every page on notched devices.

**The breakpoint is 1280px, not 640.** That is where the planner already
switches its own grid between the desktop table and the mobile card stack.
Switching the nav at 640 gave every viewport between the two a mobile layout
under a desktop nav.

## Today opens with a greeting

Not in the original spec, and it is what stopped the headerless page reading as
a web page with its chrome cut off:

```
Good evening, Vishwanath
Wednesday, 9 September
```

Time of day from the device clock, first name only, dropped silently for guests.
It is content rather than chrome, so it costs nothing from the vertical budget.

The panel around Today's cards — border, radius, cream ground, its own padding —
is desktop dressing and is gone below the breakpoint. It was stacking its
padding on the page's, spending 80px of a 360px screen on margins. "On today's
card" went with it: the greeting already names the day, and two titles for one
list is one too many.

## The week header is one component, owned above both views

Supersedes the sketch in [Shopping belongs to a week](#shopping-belongs-to-a-week).

Meals and Shopping are siblings under one week, so the week selector and the
sub-tabs belong to **neither** — they belong to a shared container that wraps
both. Shopping first shipped with no week selector at all because the chips
lived inside the meals view.

The page's actions still differ (Meals can generate, import and clear; Shopping
cannot), so the container owns the row and leaves a **slot** the page fills.

### Phone

```
[ This week ⌄ ]                         ↗   ⋯
────────────────────────────────────────────
      Meals                  Shopping
```

- The week is a **dropdown**, not chips. Chips are right where every week fits
  at once; on a phone they were a whole row spent on two options.
- It is outlined, because bold text with a chevron reads as a heading that
  happens to have an icon rather than as a control.
- The tabs are **underlined and full-width, not a segmented pill**. One pill per
  screen: the selector and the tabs do different jobs — one picks the scope, the
  other picks a view of it — and identical shapes claimed they were the same
  kind of control.
- Left-aligned, not centred. Everything below is left-aligned, and holding a
  title centred against two icons gets tight at 360px.

### Desktop

Chips and underlined tabs, both of which fit.

## In-week actions split in two

Supersedes [In-week actions](#in-week-actions) and
[The empty-state trick](#the-empty-state-trick).

The spec described "one primary action plus an overflow". What shipped separates
them by *where they belong*:

- **The toolbar** is two icons in the title row — Share, and an overflow holding
  Regenerate, Import, Clear and Earlier weeks.
- **The hero** is a separate element in the content area, where the grid would
  be, and renders only on an entirely empty week.

Splitting them is what let the toolbar stop being a strip of its own.

**Clear has exactly one confirmation.** The spec asked for one and the build
briefly had two — an inline confirm in the menu plus the existing dialog. Two
questions for one action teaches people to dismiss them. The dialog is the one
that stays; the menu just invokes it and closes.

## Shopping fetches or builds on open

Supersedes the `idle`-with-a-button behaviour implied by
[What this costs](#what-this-costs).

Opening the tab is the request. Nothing waits for a button.

It is two steps because they cost different things:

1. **Probe** — ask storage whether a list already exists for this week. Free: no
   AI call, no allowance spent.
2. **Generate** — only on a miss.

That split is what stops the tab charging a guest for walking past it.

States: `probing`, `loading`, `ready`, `error`, `limit` (guest out of
allowance — offer an upgrade, not a retry), `empty` (no dishes to shop for),
`past` (**never generate for a week that has already happened**).

Navigation is never blocked. Generations are deduped per week, so leaving and
returning joins the one in flight rather than starting a second; a generation
walked away from still completes and still writes the cache; and a response for
a week the user has left is dropped rather than applied.

The list's **action bar is pinned above the bottom nav** — one bar over another,
the way a cart bar sits over a tab bar. As a page it would otherwise fall to the
end of a long scrolling list, which is where the counts and the order button
went when this first shipped.

Its own "Market List / Shopping List" banner and "Ingredients for <week>"
heading are gone: reached through a tab labelled Shopping under a week selector,
they were the second and third statement of the same fact.

## Past weeks are browsable and read-only

Supersedes [Looking backwards, solved elsewhere](#looking-backwards-solved-elsewhere),
which deferred this and proposed a dish list that was built and then removed.

The plans are already stored and every week already has an address, so browsing
history needed no new data and no per-write bookkeeping. A week also answers
what you ate a dish *with*, which a flat dish list never could.

- Entry is the **overflow menu** → *Earlier weeks*. The normal case never
  carries it.
- The backwards step then lives in a bar shown only while looking at a past
  week. A permanent pager is the thing the week strip replaced.
- It **skips gaps**, landing on weeks that actually hold a plan, and disappears
  at the oldest rather than walking into empty years.
- The bar states plainly that the week has happened and is view-only, and offers
  a way back to the present.

**Read-only is enforced, not merely hidden.** Editability is the brand
capability **and** the week not being past, and it guards the write paths
themselves, not just the buttons that reach them.

This is what finally puts `canEditPlan: false` in front of real users. The spec
worried it would rot before the second brand arrived; past weeks exercise it
daily.

## Days already gone stop asking to be planned

New since the spec, and caused by a change made alongside it: generation now
fills from **today** rather than from Monday, rolling the days already past into
next week. That leaves the earlier days of the current week empty, and they were
offering "add a meal" — an action that cannot mean anything once the day is
over.

- An empty past day shows a dash. A past day that *does* hold a dish still shows
  it: that is the record of what was eaten.
- Both grids collapse them behind one **"Earlier this week · 3 days"** row.
- Only the current week has this shape. A past week is read-only throughout; a
  future week has no days behind it.

---

# For Android and iOS

## Carries over — these are product decisions

1. **Three destinations**: Today, Plan, Me. Shopping is a child of the week, not
   a fourth tab; it would have to answer *shopping for which week?*
2. **The app always opens on Today**, whether or not today has meals. An empty
   Today is a designed state, not something to route around.
3. **Today opens with a greeting.**
4. **Forward-only weeks** — this week and next always, plus any further week
   that actually holds a plan. No backwards paging in the normal case.
5. **Past weeks reachable deliberately, read-only**, with the backwards step
   only present once you are already in history, skipping gaps, stopping at the
   oldest.
6. **Past days within the current week** read as history and collapse.
7. **One primary action, everything rarer behind an overflow.** Verbs: *Fill
   empty days* / *Regenerate week*, *Share* (not Download — the intent is
   sending the week to someone), *Import*, *Clear*.
8. **Clear gets exactly one confirmation.**
9. **Shopping fetches or builds on open**, with the free probe first, and never
   generates for a past week.
10. **Reminders come first in Me**, and are visible to guests as a reason to
    create an account rather than hidden from them.
11. **Capabilities, not brand checks.** Which actions exist is decided by
    booleans — `aiGeneration`, `pdfImport`, `readyMadePlans`, `canEditPlan` — so
    the coming nutrition brand is a different record, not a forked code path.
    Build and test the read-only case now; on web it was a dead path held honest
    only by a test until past weeks made it real.

## Does not carry over — web mechanics

These cost real time on web and are meaningless natively. Do not port them, and
do not be confused by them in the code:

- A `backdrop-filter` makes an element a containing block for fixed-position
  descendants, and a stacking context for its children. This caused three
  separate bugs: a bottom bar pinned to a header instead of the screen, and a
  menu painting under the grid.
- `overflow: hidden` clips absolutely-positioned children and disables
  `position: sticky`. Two more bugs.
- Route groups leave no trace in the URL, so anything rendered above them cannot
  tell whether it is inside the app.

Native has its own versions of the *problem* — z-ordering, clipping to bounds,
insets — but none of the same causes.

## Solve differently on native

- **Safe areas.** Web needed explicit insets once the header went. Use the
  platform's own — `WindowInsets` on Android, `safeAreaInsets` on iOS — rather
  than reproducing the arithmetic.
- **Back.** Web gets browser back through the shopping and Instamart flows for
  free by making them routes. Native must give the hardware/gesture back the
  same meaning: out of the cart, not out of the app.
- **The bottom bar** is a platform component on both. Do not rebuild it.
- **The breakpoint** is a web concern. Phones get the phone layout; tablets are a
  judgement call, and on web the line is where the planner grid already switches.
- **Prep reminders already live natively** and are the reason the app is
  installed. Nothing here changes them, but Me is where they are configured, and
  that is why Reminders is the first group.

## Worth knowing before you start

- The planner grid keeps its orientation on every platform: **days as rows,
  courses as columns**. Collapsing rows is not a change to that; reorienting is.
- Verbs matter more than layout. *Download* → *Share*, *Generate with AI* →
  *Fill empty days* / *Regenerate week*. The labels should say what the action
  does, and the AI is not the point.
- The one-pill rule: two controls doing different jobs should not share a shape.
