# Full-width back-swipe on the meal detail page

A rightward swipe anywhere on the meal detail page returns to the screen it was
opened from. Today only a swipe that *starts within the left ~20pt* does that,
because that is all iOS's own pop gesture listens to.

Scope is one screen: `MealDetailView`, opened from Today's Menu.

## What already works

The system's interactive pop gesture is **already live on this screen**. That was
worth establishing before designing anything, because `HomeView` hides the
navigation bar for the whole stack and `MealDetailView` adds
`.navigationBarBackButtonHidden()` — in UIKit either one disables
`interactivePopGestureRecognizer`, so the reasonable assumption is that this screen
has no back-swipe at all.

Probed in the simulator against the real modifier combination, asking the
recognizer's own delegate whether it would begin:

```
hideToolbar=true  hideBackButton=true  depth=2  edgePan.enabled=true  edgePan.shouldBegin=true
```

SwiftUI, unlike UIKit, keeps the gesture when the back button is hidden. Nothing
else in the tree competes for it either:

| Suspect | Verdict |
|---|---|
| The page's vertical `ScrollView` | `contentSize.width == bounds.width`, so never horizontally pannable — even in the pre-fix overflowing layout, where the scroll view itself grew to 463.7pt rather than staying at 393pt and becoming scrollable |
| The inline YouTube player (`WKWebView`) | Its scroll view is directional-locked and inset 20pt from the screen edge, clear of the edge activation zone |
| `kkbToast` | A conditional bottom overlay with no gesture recognizers |
| Custom `DragGesture`s anywhere in the app | None exist |

So this spec does not add back navigation. It widens where the swipe can start.

## Why

iOS activates `UIScreenEdgePanGestureRecognizer` only in a narrow strip at the
screen's left edge. A user who swipes right across the middle of the page — over
the hero photograph, over the prep card — gets nothing, and the page gives no clue
that the edge is special. On this screen in particular the content that invites a
swipe is the full-bleed 280pt photograph, which is nowhere near the edge.

Widening the activation area to the full width is what apps like Telegram and
Instagram do, and it subsumes the edge case: a user who was already swiping from
the edge sees no change.

> **Assumption.** The report was "swipe right on a screen to take you to previous
> screen", which reads as a mid-screen swipe doing nothing. If the intent was that
> the *edge* swipe is broken on device, the probe above says it should work, and
> this design is still the fix — a full-width recognizer covers the edge too — but
> the mechanism would be worth re-checking on hardware first.

## The rule

A pure decision, so it can be tested without simulating touches:

```swift
enum BackSwipe {
    /// Minimum travel before the gesture is even considered, comfortably above
    /// the scroll view's own pan slop so a tap or a vertical flick never enters it.
    static let minimumDistance: CGFloat = 24

    /// Takes the two sizes rather than a `DragGesture.Value`, which has no
    /// accessible initializer and so cannot be built in a test — verified against
    /// the iOS 17 SDK:
    ///
    ///     error: 'DragGesture.Value' cannot be constructed because it has
    ///            no accessible initializers
    static func shouldPop(translation: CGSize, predictedEnd: CGSize) -> Bool {
        // Rightward and decisively horizontal: a diagonal drag belongs to the
        // scroll view, not to us.
        guard translation.width >= abs(translation.height) * 1.6 else { return false }
        return translation.width >= 90 || predictedEnd.width >= 160
    }
}
```

The modifier is the only thing that touches `DragGesture.Value`, and only to
forward the two sizes:

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: BackSwipe.minimumDistance)
        .onEnded { value in
            guard BackSwipe.shouldPop(
                translation: value.translation,
                predictedEnd: value.predictedEndTranslation
            ) else { return }
            pop()
        }
)
```

Worked examples:

| Drag (dx, dy) | Predicted dx | Pops | Why |
|---|---|---|---|
| (120, 10) | 180 | yes | deliberate horizontal swipe |
| (40, 5) | 200 | yes | short fast flick |
| (40, 5) | 60 | no | small, slow — probably a stray touch |
| (100, 80) | 150 | no | diagonal; `100 < 80 × 1.6` |
| (10, 300) | 20 | no | a scroll |
| (−120, 10) | −180 | no | leftward; there is nothing forward to go to |

## Where it lives

**`App/DesignSystem/BackSwipe.swift`** (new) — the `BackSwipe` decision above plus
a modifier:

```swift
extension View {
    /// Pops on a rightward swipe from anywhere in the view, widening iOS's own
    /// left-edge-only pop gesture. Acts on `onEnded` only — see below.
    func kkbBackSwipe(perform pop: @escaping () -> Void) -> some View
}
```

**`App/Features/Today/MealDetailView.swift`** — one line in `body`, on the same
`Group` that already takes `.kkbPageGround()`:

```swift
.kkbBackSwipe { dismiss() }
```

`dismiss()` is already in scope there; the custom chevron button uses it.

### Arbitration with the scroll view

The modifier attaches with `.simultaneousGesture`, and **acts only in `onEnded`,
never `onChanged`**. This is the load-bearing detail: a gesture that reacts while
the finger moves makes the page fight the vertical scroll and feel sticky. Reading
the translation once, on release, means vertical scrolling is bit-for-bit
unaffected — the scroll view sees every touch it does today.

### The player is a carve-out

A swipe that starts on the inline YouTube player will not pop. Touches inside a
`UIViewRepresentable` belong to the UIKit view, and `WKWebView` keeps them. This is
acceptable: it is one 16:9 card, a swipe there is plausibly aimed at the video, and
the system edge gesture still works. Not worth `UIGestureRecognizerDelegate`
plumbing to reclaim.

### The system gesture stays

Nothing disables `interactivePopGestureRecognizer`. Edge swipes keep their
interactive, finger-tracking transition; the new gesture only adds a second,
non-interactive way in.

## What "back" means from a meal reached via prev/next

`onNavigate` replaces the top of the path rather than pushing:

```swift
path.removeLast()
path.append(.mealDetail(day: newDay, type: newType))
```

So from Today → Breakfast → *NEXT* → Lunch, a back-swipe returns to **Today**, not
to Breakfast.

**Decision: keep this.** Prev/next is lateral movement within a day, not drilling
deeper, and the existing comment is right that pushing would grow an unbounded back
stack — ten taps of NEXT would mean ten swipes to get out. Back consistently means
"leave the detail page", which is also what the chevron button does. Documented
here so it reads as intended rather than as a bug someone should fix.

## Accessibility

Unchanged. The chevron button keeps its `Back` label, and VoiceOver's escape
gesture is independent of this. A swipe gesture is not an accessible affordance on
its own, which is exactly why the button stays.

## Testing

**`AppTests/BackSwipeTests.swift`** (new):

1. The worked-example table above, driven straight through
   `BackSwipe.shouldPop` — this is why the decision is a pure function over two
   `CGSize`s rather than logic buried in a gesture closure.
2. A guard that the system edge gesture is still live on the meal-detail shape:
   host the pushed screen, walk to the `UINavigationController`, assert
   `interactivePopGestureRecognizer` is enabled and its delegate returns `true`
   from `gestureRecognizerShouldBegin`. This is the probe from the top of this
   spec, kept — it is the assertion that a future `.gesture(...)` or a
   `simultaneousGesture` mistake has not silently cost us the native swipe.

No touch simulation is needed for either.

**Manual, on device** — the part tests cannot answer:

- Vertical scrolling through a long prep list still feels normal.
- A swipe across the hero photo pops.
- A swipe across the prep card pops.
- A swipe on the video player does not pop, and the video still scrubs.
- An edge swipe still tracks the finger.

## Out of scope

| | Why |
|---|---|
| Tomorrow | Same `NavigationStack`, already has the edge gesture; a candidate for the same one-line modifier later, deliberately not in this change |
| Auth, Onboarding | The real gaps found in the wider audit — both animate in horizontally but are state toggles, not pushes, so neither has any back-swipe. Separate work |
| The 10 sheet presentations | Already dismiss with a downward drag and show a drag indicator, which is the iOS convention. Two of them own horizontal scrollers a right-swipe would fight |
| An interactive full-width transition | The page would track the finger like the edge gesture does. Needs either the private `handleNavigationTransition:` selector — an App Store risk — or a hand-rolled `UIPercentDrivenInteractiveTransition`. Neither is worth it for a second entry point to an action that already has a button |
