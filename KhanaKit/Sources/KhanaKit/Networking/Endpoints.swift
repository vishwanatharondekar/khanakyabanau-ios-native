import Foundation

/// Every backend route the app uses, in one place.
///
/// Auth requirements and timeout profiles are encoded here rather than at call
/// sites so a new caller can't accidentally send a 45-second AI request on the
/// 10-second budget, or attach a bearer token to one of the public endpoints.
public enum Endpoints {

    // MARK: - Auth

    public static func login(_ body: LoginRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/auth/login",
                 body: Endpoint.json(body), requiresAuth: false)
    }

    public static func register(_ body: RegisterRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/auth/register",
                 body: Endpoint.json(body), requiresAuth: false)
    }

    public static func createGuest(_ body: GuestRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/auth/guest",
                 body: Endpoint.json(body), requiresAuth: false)
    }

    public static func fetchGuest(deviceId: String) -> Endpoint {
        Endpoint(method: .get, path: "api/auth/guest",
                 query: [URLQueryItem(name: "deviceId", value: deviceId)],
                 requiresAuth: false)
    }

    /// Requires the *guest's* bearer token; returns a new token for a new user id.
    public static func upgradeGuest(_ body: UpgradeGuestRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/auth/upgrade-guest", body: Endpoint.json(body))
    }

    /// Permanently deletes the signed-in account and everything it owns.
    ///
    /// A wrong password answers 403, not 401: `APIClient.validate` reads a 401 on
    /// an authenticated route as a dead session and signs the user out globally,
    /// which is the wrong outcome for a typo.
    public static func deleteAccount(_ body: DeleteAccountRequest) -> Endpoint {
        Endpoint(method: .delete, path: "api/auth/delete-account",
                 body: Endpoint.json(body))
    }

    public static var profile: Endpoint {
        Endpoint(method: .get, path: "api/auth/profile")
    }

    // MARK: - Preferences

    public static var dietaryPreferences: Endpoint {
        Endpoint(method: .get, path: "api/auth/dietary-preferences")
    }

    /// The body is the preferences object itself, not a wrapper.
    public static func saveDietaryPreferences(_ body: DietaryPreferences) -> Endpoint {
        Endpoint(method: .put, path: "api/auth/dietary-preferences", body: Endpoint.json(body))
    }

    public static func saveCuisinePreferences(_ body: CuisinePreferencesRequest) -> Endpoint {
        Endpoint(method: .put, path: "api/auth/cuisine-preferences", body: Endpoint.json(body))
    }

    public static var mealSettings: Endpoint {
        Endpoint(method: .get, path: "api/auth/meal-settings")
    }

    public static func saveMealSettings(_ body: MealSettingsEnvelope) -> Endpoint {
        Endpoint(method: .put, path: "api/auth/meal-settings", body: Endpoint.json(body))
    }

    public static var languagePreferences: Endpoint {
        Endpoint(method: .get, path: "api/auth/language-preferences")
    }

    public static func saveLanguagePreferences(_ body: LanguagePreferences) -> Endpoint {
        Endpoint(method: .put, path: "api/auth/language-preferences", body: Endpoint.json(body))
    }

    // MARK: - Meals

    /// Creates an empty plan server-side when none exists, so this never 404s.
    public static func week(_ weekStartDate: String) -> Endpoint {
        Endpoint(method: .get, path: "api/meals/\(weekStartDate)")
    }

    /// A full replacement of the grid. Omitting `calories`, `videoUrl` or
    /// `prep`+`prepFor` deletes them server-side.
    public static func saveWeek(_ weekStartDate: String, _ body: SaveMealsRequest) -> Endpoint {
        Endpoint(method: .put, path: "api/meals/\(weekStartDate)", body: Endpoint.json(body))
    }

    /// Returns a bare JSON array, newest first, strictly before `targetWeek`.
    public static func history(targetWeek: String, limit: Int = 10) -> Endpoint {
        Endpoint(
            method: .get,
            path: "api/meals/history",
            query: [
                URLQueryItem(name: "targetWeek", value: targetWeek),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    /// One AI call for every distinct dish that still lacks prep.
    public static func generatePrep(
        _ weekStartDate: String,
        _ body: GeneratePrepRequest
    ) -> Endpoint {
        Endpoint(method: .post, path: "api/meals/\(weekStartDate)/prep",
                 body: Endpoint.json(body), profile: .ai)
    }

    public static func setSlotVideo(
        _ weekStartDate: String,
        _ body: SetSlotVideoRequest
    ) -> Endpoint {
        Endpoint(method: .put, path: "api/meals/\(weekStartDate)/video",
                 body: Endpoint.json(body), profile: .ai)
    }

    // MARK: - AI

    /// Returns a raw planner grid and does **not** save; the client PUTs it back.
    public static func generateMeals(_ body: AIGenerateRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/ai/generate", body: Endpoint.json(body), profile: .ai)
    }

    public static func shoppingList(_ body: ShoppingListRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/ai/get-shopping-list",
                 body: Endpoint.json(body), profile: .ai)
    }

    public static func corpusSuggestions(_ body: CorpusSuggestionsRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/suggestions/from-corpus",
                 body: Endpoint.json(body), profile: .ai)
    }

    public static func updateHaveAlready(
        _ weekStartDate: String,
        _ body: UpdateHaveAlreadyRequest
    ) -> Endpoint {
        Endpoint(method: .patch, path: "api/shopping-list/\(weekStartDate)",
                 body: Endpoint.json(body))
    }

    // MARK: - Video

    /// A 404 here means "no saved videos yet", not an error.
    public static var videoURLs: Endpoint {
        Endpoint(method: .get, path: "api/auth/video-urls")
    }

    public static func saveVideoURL(_ body: SaveVideoURLRequest) -> Endpoint {
        Endpoint(method: .put, path: "api/auth/video-urls", body: Endpoint.json(body))
    }

    /// Unauthenticated. Server-side cache is 24 h and the YouTube quota allows only
    /// ~99 uncached searches per day *across all users*, so cache hard on device.
    public static func searchVideos(
        query: String,
        maxResults: Int = 10,
        pageToken: String? = nil
    ) -> Endpoint {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return Endpoint(method: .get, path: "api/youtube/search",
                        query: items, requiresAuth: false, profile: .ai)
    }

    // MARK: - Images, translation

    /// Unauthenticated, and never fails — returns `{}` on any server-side error.
    public static func imageMapping(_ body: ImageMappingRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/image-mapping",
                 body: Endpoint.json(body), requiresAuth: false)
    }

    /// Unauthenticated.
    public static func translateBatch(_ body: TranslateBatchRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/translate/batch",
                 body: Endpoint.json(body), requiresAuth: false, profile: .ai)
    }

    // MARK: - Notifications

    public static func registerDevice(_ body: RegisterDeviceRequest) -> Endpoint {
        Endpoint(method: .post, path: "api/notifications/devices", body: Endpoint.json(body))
    }

    public static func unregisterDevice(_ body: UnregisterDeviceRequest) -> Endpoint {
        Endpoint(method: .delete, path: "api/notifications/devices", body: Endpoint.json(body))
    }

    public static var notificationPreferences: Endpoint {
        Endpoint(method: .get, path: "api/notifications/preferences")
    }

    public static func saveNotificationPreferences(
        _ body: NotificationPreferencesRequest
    ) -> Endpoint {
        Endpoint(method: .put, path: "api/notifications/preferences", body: Endpoint.json(body))
    }
}
