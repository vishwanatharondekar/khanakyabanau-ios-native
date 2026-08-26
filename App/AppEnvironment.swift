import Foundation
import KhanaKit
import SwiftUI

/// Composition root. One instance is created at launch and handed down through
/// `@Environment`, which keeps the repositories out of global mutable state while
/// still letting any screen reach the ones it needs.
@MainActor
@Observable
final class AppEnvironment {
    let api: APIClient
    let tokenStore: TokenStore
    let analytics: AnalyticsService

    let auth: AuthRepository
    let meals: MealRepository
    let ai: AiRepository
    let settings: SettingsRepository
    let videos: RecipeVideoRepository
    let translations: TranslationRepository
    let push: PushService
    let prepReminders: PrepReminderScheduler
    let firstWeek: FirstWeekSeeder

    init() {
        let tokenStore = TokenStore()
        // The provider closure is read on every request, so a login or guest
        // upgrade that swaps the token is picked up without re-wiring the client.
        let api = APIClient(tokenProvider: { TokenStore.currentToken() })

        self.tokenStore = tokenStore
        self.api = api
        self.analytics = AnalyticsService()
        self.auth = AuthRepository(api: api, tokenStore: tokenStore)
        self.meals = MealRepository(api: api)
        self.ai = AiRepository(api: api)
        self.videos = RecipeVideoRepository(api: api, ai: self.ai)
        self.translations = TranslationRepository(api: api)
        self.push = PushService(api: api)

        let settings = SettingsRepository(api: api)
        self.settings = settings
        let prepReminders = PrepReminderScheduler(meals: self.meals, settings: settings)
        self.prepReminders = prepReminders
        self.firstWeek = FirstWeekSeeder(
            ai: self.ai, meals: self.meals, prepReminders: prepReminders
        )
    }
}

extension AppEnvironment {
    /// Only reached if a view is rendered without the root injecting one — in
    /// practice previews and tests. The real instance is created in `KhanaKyaBanauApp`.
    @MainActor static let placeholder = AppEnvironment()
}

private struct AppEnvironmentKey: EnvironmentKey {
    // `EnvironmentValues` accessors are nonisolated, but every read happens while
    // rendering, which is main-actor bound.
    static var defaultValue: AppEnvironment {
        MainActor.assumeIsolated { AppEnvironment.placeholder }
    }
}

extension EnvironmentValues {
    var app: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
