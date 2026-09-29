import SwiftUI

/// The branded screen shown once per cold launch, over the root switch.
///
/// The system launch screen is only a flat `LaunchBackground`, so this picks up
/// on the same colour and plays the mark in: it pops up with a tilt, settles with
/// a bounce, and sends a soft glow out behind it. `AppRootView` removes it once the
/// intro has had its minimum time *and* the session has left `.loading` — so it
/// also covers the profile fetch that used to show as a blank page.
struct SplashView: View {
    static let markSize: CGFloat = 104

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    var body: some View {
        KkbBackground {
            ZStack {
                if !reduceMotion {
                    SplashRipple(started: started)
                }

                AppMarkIcon(size: Self.markSize)
                    .shadow(color: Kkb.terracotta700.opacity(0.2), radius: 18, y: 10)
                    .keyframeAnimator(initialValue: MarkPose.hidden, trigger: started) { view, pose in
                        view
                            .scaleEffect(reduceMotion ? 1 : pose.scale)
                            .rotationEffect(.degrees(reduceMotion ? 0 : pose.rotation))
                            .offset(y: reduceMotion ? 0 : pose.lift)
                            .opacity(pose.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1.12, duration: 0.32, spring: .snappy)
                            SpringKeyframe(0.95, duration: 0.16)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(6, duration: 0.32)
                            CubicKeyframe(-3, duration: 0.18)
                            SpringKeyframe(0, duration: 0.3)
                        }
                        KeyframeTrack(\.lift) {
                            CubicKeyframe(-10, duration: 0.32)
                            SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.18)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Khana Kya Banau")
        .onAppear { started = true }
    }
}

private struct MarkPose {
    var scale: Double
    var rotation: Double
    var lift: Double
    var opacity: Double

    static let hidden = MarkPose(scale: 0.35, rotation: -14, lift: 0, opacity: 0)
}

/// A soft terracotta glow spreading out from behind the mark as it lands: the
/// "something's cooking" beat. A radial fill rather than an outline, so it has no
/// edge to read as a shape — just warmth widening and fading.
private struct SplashRipple: View {
    let started: Bool

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Kkb.terracotta400.opacity(0.45), Kkb.terracotta300.opacity(0.18), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: SplashView.markSize
                )
            )
            .frame(width: SplashView.markSize * 2, height: SplashView.markSize * 2)
            .keyframeAnimator(initialValue: RipplePose(scale: 0.4, opacity: 0), trigger: started) { view, pose in
                view.scaleEffect(pose.scale).opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: 0.25)
                    CubicKeyframe(2.2, duration: 1.3)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.25)
                    CubicKeyframe(1, duration: 0.25)
                    CubicKeyframe(0, duration: 1.05)
                }
            }
    }
}

private struct RipplePose {
    var scale: Double
    var opacity: Double
}

#Preview {
    SplashView()
}
