import Foundation
import KhanaKit

/// User preferences: which courses are on the card, dietary rules, language and
/// prep reminders.
///
/// `mealSettings` is cached to disk because it decides how many rows every day
/// card renders. Without the cache the first frame shows all five courses and then
/// collapses to three, which reads as a bug.
@MainActor
@Observable
final class SettingsRepository {
    private enum Keys {
        static let mealSettings = "kkb.mealSettings"
        static let language = "kkb.language"
    }

    private let api: APIClient
    private let defaults: UserDefaults

    private(set) var mealSettings: MealSettings
    private(set) var dietary: DietaryPreferences?
    private(set) var language: LanguagePreferences
    private(set) var prepReminders = PrepReminderSettings()

    /// Guards the once-per-launch fetch. Reset on failure so the next screen that
    /// needs settings retries rather than living with the fallback forever.
    private var mealSettingsLoaded = false
    private var inFlight: Task<Void, Never>?

    init(api: APIClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.mealSettings),
           let cached = try? JSONDecoder().decode(MealSettings.self, from: data) {
            mealSettings = cached
        } else {
            mealSettings = .fallback
        }
        if let code = defaults.string(forKey: Keys.language) {
            language = LanguagePreferences(language: code)
        } else {
            language = LanguagePreferences()
        }
    }

    var enabledTypes: [MealType] { mealSettings.enabledTypes }

    var isVegetarian: Bool { dietary?.isVegetarian ?? false }

    var showCalories: Bool { dietary?.showCalories ?? false }

    /// Fetches meal settings at most once per launch. Concurrent callers await the
    /// same task rather than each firing their own request.
    func ensureMealSettings() async {
        if mealSettingsLoaded { return }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await api.send(
                    Endpoints.mealSettings, as: MealSettingsEnvelope.self
                )
                applyMealSettings(response.mealSettings)
                mealSettingsLoaded = true
            } catch {
                // Leave `mealSettingsLoaded` false so the next screen retries.
                mealSettingsLoaded = false
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func refreshAll() async {
        async let settings: Void = ensureMealSettings()
        async let dietaryLoad = loadDietary()
        async let languageLoad = loadLanguage()
        _ = await (settings, dietaryLoad, languageLoad)
    }

    /// Loads dietary preferences, reporting whether it actually succeeded.
    ///
    /// On failure the previously loaded value is **kept**, not cleared. `nil` here
    /// is indistinguishable from the server's legitimate bare-`null` response, and
    /// `PUT /api/auth/dietary-preferences` replaces the whole object — so a form
    /// rendered from a nilled cache would silently overwrite the user's real
    /// preferences with defaults the moment they pressed Save. Android keeps the
    /// previous value for the same reason (`SettingsViewModel.loadDietary`).
    @discardableResult
    func loadDietary() async -> Bool {
        do {
            dietary = try await api.sendAllowingNull(
                Endpoints.dietaryPreferences, as: DietaryPreferences.self
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func loadLanguage() async -> Bool {
        do {
            let prefs = try await api.send(
                Endpoints.languagePreferences, as: LanguagePreferences.self
            )
            language = prefs
            defaults.set(prefs.language, forKey: Keys.language)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func loadPrepReminders() async -> Bool {
        guard let response = try? await api.send(
            Endpoints.notificationPreferences, as: NotificationPreferencesResponse.self
        ) else { return false }
        prepReminders = response.settings
        return true
    }

    // MARK: - Saving

    func saveMealSettings(_ types: [MealType]) async throws {
        // The server re-sorts into chronological order on save; sorting here too
        // means the local state matches without waiting for a round trip.
        let sorted = MealType.sorted(types)
        let payload = MealSettings(enabledMealTypes: sorted.map(\.key))
        let response = try await api.send(
            Endpoints.saveMealSettings(MealSettingsEnvelope(mealSettings: payload)),
            as: MealSettingsEnvelope.self
        )
        applyMealSettings(response.mealSettings)
        mealSettingsLoaded = true
    }

    func saveDietary(_ preferences: DietaryPreferences) async throws {
        _ = try await api.send(Endpoints.saveDietaryPreferences(preferences))
        dietary = preferences
    }

    func saveCuisines(_ cuisines: [String], onboardingCompleted: Bool = false) async throws {
        _ = try await api.send(Endpoints.saveCuisinePreferences(
            CuisinePreferencesRequest(
                cuisinePreferences: cuisines, onboardingCompleted: onboardingCompleted
            )
        ))
    }

    func saveLanguage(_ code: String) async throws {
        let payload = LanguagePreferences(language: code)
        _ = try await api.send(Endpoints.saveLanguagePreferences(payload))
        language = payload
        defaults.set(code, forKey: Keys.language)
    }

    func savePrepReminders(_ settings: PrepReminderSettings) async throws {
        _ = try await api.send(Endpoints.saveNotificationPreferences(
            NotificationPreferencesRequest(
                prepReminders: settings.enabled,
                hourLocal: settings.hour,
                timezone: TimeZone.current.identifier,
                afternoonPrepReminders: settings.afternoonEnabled,
                afternoonHourLocal: settings.afternoonHour
            )
        ))
        prepReminders = settings
    }

    /// Wipes cached preferences on sign-out so the next user doesn't inherit them.
    func reset() {
        mealSettings = .fallback
        dietary = nil
        language = LanguagePreferences()
        prepReminders = PrepReminderSettings()
        mealSettingsLoaded = false
        defaults.removeObject(forKey: Keys.mealSettings)
        defaults.removeObject(forKey: Keys.language)
    }

    private func applyMealSettings(_ settings: MealSettings) {
        mealSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.mealSettings)
        }
    }
}
