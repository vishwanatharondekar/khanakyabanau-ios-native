import SwiftUI

/// Widens iOS's back-swipe from the left screen edge to the whole view.
///
/// The system's `UIScreenEdgePanGestureRecognizer` only activates in a narrow
/// strip at the left edge, and nothing on screen says so. On the meal detail page
/// the content that invites a swipe is a full-bleed 280pt photograph nowhere near
/// that strip, so a swipe across the middle of the page — the one most people
/// make — does nothing at all.
///
/// The native gesture is left exactly as it is: it keeps its interactive,
/// finger-tracking transition, and this only adds a second way in. Which is why
/// the modifier joins with `simultaneousGesture` rather than `gesture`.
///
/// See `docs/superpowers/specs/2026-09-04-meal-detail-back-swipe-design.md`.
enum BackSwipe {

    /// How far a drag travels before it is considered at all. Comfortably above
    /// the scroll view's own pan slop, so a tap or a vertical flick never enters
    /// the gesture.
    static let minimumDistance: CGFloat = 24

    /// A drag reads as "go back" when it is rightward, decisively horizontal, and
    /// either long or fast.
    ///
    /// Takes the two sizes rather than a `DragGesture.Value`, which has no
    /// accessible initializer and so cannot be built in a test:
    ///
    ///     error: 'DragGesture.Value' cannot be constructed because it has
    ///            no accessible initializers
    ///
    /// Keeping the decision here rather than inside the gesture closure is what
    /// makes `BackSwipeTests` a table of translations instead of a touch
    /// simulation.
    static func shouldPop(translation: CGSize, predictedEnd: CGSize) -> Bool {
        // A diagonal drag belongs to the scroll view, not to us. `abs` because a
        // swipe drifting upward is as much a diagonal as one drifting down.
        guard translation.width >= abs(translation.height) * 1.6 else { return false }
        // Long, or short and thrown — `predictedEndTranslation` is where the drag
        // would land at its release velocity, so a quick flick counts.
        return translation.width >= 90 || predictedEnd.width >= 160
    }
}

extension View {
    /// Runs `pop` on a rightward swipe from anywhere in this view.
    ///
    /// Acts on `onEnded` only. This is load-bearing rather than incidental: a
    /// gesture that reacts while the finger is still moving makes the page fight
    /// whatever is scrolling underneath it and feel sticky. Reading the
    /// translation once, on release, leaves vertical scrolling untouched — the
    /// scroll view still sees every touch it did before.
    ///
    /// A swipe that starts inside a `UIViewRepresentable` will not pop: UIKit
    /// keeps those touches. On the meal detail page that means the inline video
    /// player, which is a deliberate carve-out — a swipe there is plausibly aimed
    /// at the video, and the native edge gesture still works.
    func kkbBackSwipe(perform pop: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: BackSwipe.minimumDistance)
                .onEnded { value in
                    guard BackSwipe.shouldPop(
                        translation: value.translation,
                        predictedEnd: value.predictedEndTranslation
                    ) else { return }
                    pop()
                }
        )
    }
}
