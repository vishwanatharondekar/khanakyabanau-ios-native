import KhanaKit
import SwiftUI

/// The whole app is a switch over session state — the same shape as Android's
/// `AppRoot.kt:115-145`. There is no navigation graph at this level.
struct AppRootView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Welcome ⇄ Auth is a local toggle, not a route.
    @State private var showingAuth = false

    /// Cold-launch only: this view lives for the life of the scene, so coming back
    /// from the background never replays the intro.
    @State private var showingSplash = true
    @State private var splashMinimumElapsed = false

    var body: some View {
        ZStack {
            content
            if showingSplash {
                SplashView()
                    // Zooms toward the viewer as it fades, so the app reads as
                    // coming out from behind the mark rather than cross-fading.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.25)))
                    .zIndex(1)
            }
        }
        .task {
            // Long enough for the intro to finish; any shorter and a fast profile
            // fetch cuts the mark off before it has settled.
            try? await Task.sleep(for: .seconds(1.3))
            splashMinimumElapsed = true
        }
        .onChange(of: splashShouldDismiss) { _, dismiss in
            if dismiss { withAnimation(.easeIn(duration: 0.3)) { showingSplash = false } }
        }
    }

    private var splashShouldDismiss: Bool {
        splashMinimumElapsed && session.state != .loading
    }

    private var content: some View {
        KkbBackground {
            switch session.state {
            case .loading:
                // Deliberately blank: the splash is still up over it.
                Color.clear

            case .unauthenticated:
                if showingAuth || session.wantsSignIn {
                    AuthView(onBack: {
                        showingAuth = false
                        session.wantsSignIn = false
                    })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    WelcomeView(onSignIn: { showingAuth = true })
                        .transition(.opacity)
                }

            case let .needsOnboarding(user):
                OnboardingView(user: user)
                    .transition(.opacity)

            case .ready:
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: showingAuth)
        .animation(.snappy(duration: 0.25), value: session.state)
        .task {
            // Firebase is configured here rather than in `init` so it happens on
            // the main actor with the scene already up, and so a placeholder
            // GoogleService-Info.plist can disable it without touching launch.
            env.push.configure()
            await session.start()
        }
        .onChange(of: session.state) { _, newValue in
            // Coming back to signed-out should not leave the auth form on screen.
            if newValue != .unauthenticated {
                showingAuth = false
                session.wantsSignIn = false
            }
        }
    }
}
