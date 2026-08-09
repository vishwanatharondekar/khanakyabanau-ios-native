import Foundation
import KhanaKit
import SwiftUI

/// What the root view is showing. Mirrors Android's `SessionState`
/// (`SessionViewModel.kt:38-96`) — there is no navigation graph in this product,
/// just a switch over this.
enum SessionState: Equatable {
    case loading
    case unauthenticated
    case needsOnboarding(User)
    case ready(User)

    var user: User? {
        switch self {
        case let .needsOnboarding(user), let .ready(user): user
        case .loading, .unauthenticated: nil
        }
    }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var state: SessionState = .loading
    /// Surfaced on the Welcome screen when guest creation or a profile fetch fails.
    var errorMessage: String?
    /// Set *before* signing a guest out so the root lands on the sign-in form
    /// rather than Welcome — a guest who taps "Already have an account?" wants the
    /// form, not the front door. Android sequences it the same way
    /// (`AppRoot.kt:136`).
    var wantsSignIn = false

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var user: User? { state.user }
    var isGuest: Bool { user?.isGuest ?? false }

    /// Called once at launch. A stored token means we can go straight to fetching
    /// the profile; anything else lands on Welcome.
    func start() async {
        await env.api.setUnauthorizedHandler { [weak self] in
            await self?.handleUnauthorized()
        }
        guard env.tokenStore.isAuthenticated else {
            state = .unauthenticated
            return
        }
        await loadProfile()
    }

    /// Re-fetches the profile and routes accordingly.
    ///
    /// A failure here keeps the token but drops to `.unauthenticated`, matching
    /// Android: we can't tell a revoked account from a flaky network, and showing a
    /// half-loaded planner would be worse than asking the user to continue.
    func loadProfile() async {
        do {
            let user = try await env.auth.fetchProfile()
            env.analytics.identify(user)
            state = user.onboardingCompleted ? .ready(user) : .needsOnboarding(user)
            errorMessage = nil
            await afterSignIn()
        } catch {
            state = .unauthenticated
            if case APIError.unauthorized = error {
                env.tokenStore.clear()
            }
        }
    }

    /// "Get Started" — creates the anonymous account and drops into onboarding.
    func startAsGuest() async {
        errorMessage = nil
        do {
            _ = try await env.auth.createGuest()
            env.analytics.track(
                AnalyticsEvents.Auth.guestStart, category: AnalyticsEvents.Category.auth
            )
            // `POST /api/auth/guest` omits cuisine and dietary preferences, which a
            // returning guest on the same device already has — and which seed the
            // suggestion sheet. Route through the profile like every other path.
            try await signedIn()
        } catch let error as APIError {
            errorMessage = error.userMessage(fallback: "Could not get you started. Please try again.")
        } catch {
            errorMessage = "Could not get you started. Please try again."
        }
    }

    /// Routes after a successful sign-in, registration or guest upgrade.
    ///
    /// The auth endpoints return only `{id, email, name}` — `onboardingCompleted`,
    /// `cuisinePreferences` and `dietaryPreferences` are all absent from that body
    /// (`app/api/auth/login/route.ts:63-69`). Routing from it would decode
    /// `onboardingCompleted` as its `false` default and march every returning user
    /// back through onboarding, where finishing would overwrite the cuisines they
    /// already had. `GET /api/auth/profile` is the only complete picture, which is
    /// why Android routes from it too (`SessionViewModel.loadProfile`).
    ///
    /// Takes no user on purpose: the auth response is not trustworthy enough to
    /// route from, so there is nothing useful for a caller to hand over.
    ///
    /// - Throws: if the profile cannot be loaded, so the caller can show the error
    ///   rather than guessing at the user's onboarding state.
    func signedIn() async throws {
        let profile = try await env.auth.fetchProfile()
        env.analytics.identify(profile)
        state = profile.onboardingCompleted ? .ready(profile) : .needsOnboarding(profile)
        errorMessage = nil
        await afterSignIn()
    }

    /// Onboarding writes preferences server-side; this flips the local flag so the
    /// root view swaps to Home without a second profile round trip.
    func completeOnboarding() {
        guard var user = state.user else { return }
        user.onboardingCompleted = true
        state = .ready(user)
    }

    func refreshUser() async {
        guard let refreshed = try? await env.auth.fetchProfile() else { return }
        state = refreshed.onboardingCompleted ? .ready(refreshed) : .needsOnboarding(refreshed)
    }

    /// Order matters: the device has to be unregistered while the token is still
    /// valid, so push cleanup runs before the token is discarded.
    func signOut() async {
        await env.push.unregisterDevice()
        env.analytics.track(
            AnalyticsEvents.Auth.logout, category: AnalyticsEvents.Category.auth
        )
        env.analytics.reset()
        env.auth.logout()
        env.settings.reset()
        env.videos.reset()
        env.meals.clearImageCache()
        await env.prepReminders.cancelAll()
        state = .unauthenticated
    }

    /// The server rejected our bearer token. Android has no handling for this at
    /// all and simply shows generic errors; here we sign out cleanly instead.
    private func handleUnauthorized() async {
        guard state != .unauthenticated else { return }
        env.auth.logout()
        env.settings.reset()
        env.videos.reset()
        env.meals.clearImageCache()
        env.analytics.reset()
        state = .unauthenticated
        errorMessage = "Your session has expired. Please sign in again."
    }

    /// Work that should happen on every fresh session, in the background.
    private func afterSignIn() async {
        Task { await env.settings.refreshAll() }
        Task { await env.videos.ensureLoaded() }
        // Re-registering on every launch is what keeps the server's UTC reminder
        // slot correct across travel and daylight-saving changes.
        Task { await env.push.registerIfAuthorized() }
        // Local reminders need the plan and the user's chosen hour, so they are
        // laid down after settings load rather than alongside.
        Task {
            await env.settings.loadPrepReminders()
            await env.prepReminders.reschedule()
        }
    }
}
