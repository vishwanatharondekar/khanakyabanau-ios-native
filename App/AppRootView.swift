import KhanaKit
import SwiftUI

/// The whole app is a switch over session state — the same shape as Android's
/// `AppRoot.kt:115-145`. There is no navigation graph at this level.
struct AppRootView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    /// Welcome ⇄ Auth is a local toggle, not a route.
    @State private var showingAuth = false

    var body: some View {
        KkbBackground {
            switch session.state {
            case .loading:
                // Deliberately blank: the launch screen is still up, and a spinner
                // here would flash for the duration of one profile fetch.
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
