import Foundation

// Request and response shapes for the backend, named after the routes they serve.
// Field names are the wire contract — do not rename without checking the matching
// Next.js route handler.

// MARK: - Auth

public struct LoginRequest: Encodable, Sendable {
    public var email: String
    public var password: String
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RegisterRequest: Encodable, Sendable {
    public var email: String
    public var password: String
    public var name: String
    public init(email: String, password: String, name: String) {
        self.email = email
        self.password = password
        self.name = name
    }
}

public struct GuestRequest: Encodable, Sendable {
    /// Must start with `guest_` or the route 400s.
    public var deviceId: String
    public init(deviceId: String) { self.deviceId = deviceId }
}

public struct DeleteAccountRequest: Encodable, Sendable {
    /// Registered accounts re-enter their password; a guest has none. Optional so
    /// the synthesised encoder omits the key entirely rather than sending null,
    /// which the route would have to special-case.
    public var password: String?
    public init(password: String?) { self.password = password }
}

public struct UpgradeGuestRequest: Encodable, Sendable {
    public var email: String
    public var password: String
    public var name: String
    public init(email: String, password: String, name: String) {
        self.email = email
        self.password = password
        self.name = name
    }
}

/// `{token, user}` — note that upgrade-guest returns a *new* token for a *new* user id.
public struct AuthResponse: Decodable, Sendable {
    public var token: String
    public var user: User
}

public struct ProfileResponse: Decodable, Sendable {
    public var user: User
}

public struct GuestProfileResponse: Decodable, Sendable {
    public var user: User
}

// MARK: - Preferences

public struct MealSettingsEnvelope: Codable, Sendable {
    public var mealSettings: MealSettings
    public init(mealSettings: MealSettings) { self.mealSettings = mealSettings }
}

public struct CuisinePreferencesRequest: Encodable, Sendable {
    public var cuisinePreferences: [String]
    public var onboardingCompleted: Bool
    public init(cuisinePreferences: [String], onboardingCompleted: Bool = false) {
        self.cuisinePreferences = cuisinePreferences
        self.onboardingCompleted = onboardingCompleted
    }
}

public struct IngredientsRequest: Encodable, Sendable {
    public var ingredients: [String]
    public init(ingredients: [String]) { self.ingredients = ingredients }
}

// MARK: - Meals

public struct SaveMealsRequest: Encodable, Sendable {
    /// A full replacement of the week's grid — `PUT /api/meals/{week}` does not merge.
    public var meals: [String: DayMeals]
    public init(meals: [String: DayMeals]) { self.meals = meals }
}

/// `{}` means "the whole week"; optional fields encode via `encodeIfPresent`.
public struct GeneratePrepRequest: Encodable, Sendable {
    public var day: String?
    public var mealType: String?
    public init(day: String? = nil, mealType: String? = nil) {
        self.day = day
        self.mealType = mealType
    }
}

public struct GeneratePrepResponse: Decodable, Sendable {
    public var updated: Int
    public var dishes: [String]
    public var skipped: String?

    private enum CodingKeys: String, CodingKey {
        case updated, dishes, skipped
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = (try? c.decode(Int.self, forKey: .updated)) ?? 0
        dishes = (try? c.decode([String].self, forKey: .dishes)) ?? []
        skipped = try? c.decode(String.self, forKey: .skipped)
    }
}

public struct SetSlotVideoRequest: Encodable, Sendable {
    public var day: String
    public var mealType: String
    /// Empty deletes the field server-side.
    public var videoUrl: String
    public init(day: String, mealType: String, videoUrl: String) {
        self.day = day
        self.mealType = mealType
        self.videoUrl = videoUrl
    }
}

public struct SetSlotVideoResponse: Decodable, Sendable {
    public var success: Bool
    public var meal: Meal?

    private enum CodingKeys: String, CodingKey {
        case success, meal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        meal = try? c.decode(Meal.self, forKey: .meal)
    }
}

// MARK: - Images

public struct ImageMappingRequest: Encodable, Sendable {
    public var mealNames: [String]
    public init(mealNames: [String]) { self.mealNames = mealNames }
}

public struct ImageMappingResponse: Decodable, Sendable {
    public var mealImageMappings: [String: String]

    private enum CodingKeys: String, CodingKey {
        case mealImageMappings
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealImageMappings = (try? c.decode([String: String].self, forKey: .mealImageMappings)) ?? [:]
    }
}

// MARK: - AI

public struct AIGenerateRequest: Encodable, Sendable {
    public var weekStartDate: String
    public var ingredients: [String]
    /// A per-generation override, separate from the persisted cuisine preference.
    public var moodCuisines: [String]
    public init(weekStartDate: String, ingredients: [String] = [], moodCuisines: [String] = []) {
        self.weekStartDate = weekStartDate
        self.ingredients = ingredients
        self.moodCuisines = moodCuisines
    }
}

public struct ShoppingListRequest: Encodable, Sendable {
    /// Flat list of every dish name in the week.
    public var meals: [String]
    /// day key → meal type key → dish name.
    public var dayWiseMeals: [String: [String: String]]
    /// Always 1 — Android has no portions UI, so neither does iOS.
    public var portions: Int
    public var weekStartDate: String

    public init(
        meals: [String],
        dayWiseMeals: [String: [String: String]],
        portions: Int = 1,
        weekStartDate: String
    ) {
        self.meals = meals
        self.dayWiseMeals = dayWiseMeals
        self.portions = portions
        self.weekStartDate = weekStartDate
    }
}

public struct UpdateHaveAlreadyRequest: Encodable, Sendable {
    /// Server caps at 500 items, 120 chars each.
    public var haveAlready: [String]
    public init(haveAlready: [String]) { self.haveAlready = haveAlready }
}

public struct UpdateHaveAlreadyResponse: Decodable, Sendable {
    public var success: Bool
    public var haveAlready: [String]

    private enum CodingKeys: String, CodingKey {
        case success, haveAlready
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        haveAlready = (try? c.decode([String].self, forKey: .haveAlready)) ?? []
    }
}

/// The non-LLM suggestion path: fast, free, and not subject to the guest quota.
public struct CorpusSuggestionsRequest: Encodable, Sendable {
    public var mealType: String
    public var exclude: [String]
    public init(mealType: String, exclude: [String] = []) {
        self.mealType = mealType
        self.exclude = exclude
    }
}

public struct CorpusSuggestionsResponse: Decodable, Sendable {
    public var suggestions: [String]
    public var corpusSize: Int

    private enum CodingKeys: String, CodingKey {
        case suggestions, corpusSize
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = (try? c.decode([String].self, forKey: .suggestions)) ?? []
        corpusSize = (try? c.decode(Int.self, forKey: .corpusSize)) ?? 0
    }
}

// MARK: - Video

public struct SaveVideoURLRequest: Encodable, Sendable {
    public var recipeName: String
    /// Empty removes the saved pick for this dish.
    public var videoUrl: String
    public init(recipeName: String, videoUrl: String) {
        self.recipeName = recipeName
        self.videoUrl = videoUrl
    }
}

public struct SaveVideoURLResponse: Decodable, Sendable {
    public var success: Bool
    /// The server echoes the whole map back, which the client adopts wholesale.
    public var videoURLs: [String: String]

    private enum CodingKeys: String, CodingKey {
        case success, videoURLs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        videoURLs = (try? c.decode([String: String].self, forKey: .videoURLs)) ?? [:]
    }
}

/// Note `thumbnail`, not `thumbnailUrl`, and an ISO-8601 `duration` like `"PT4M13S"`.
public struct YouTubeVideoDTO: Decodable, Sendable {
    public var id: String
    public var title: String
    public var thumbnail: String?
    public var channelTitle: String
    public var duration: String?
    public var url: String

    private enum CodingKeys: String, CodingKey {
        case id, title, thumbnail, channelTitle, duration, url
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        thumbnail = try? c.decode(String.self, forKey: .thumbnail)
        channelTitle = (try? c.decode(String.self, forKey: .channelTitle)) ?? ""
        duration = try? c.decode(String.self, forKey: .duration)
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
    }

    public var asResult: RecipeVideoResult {
        RecipeVideoResult(
            id: id,
            title: title,
            channelTitle: channelTitle,
            duration: RecipeVideos.formatDuration(duration),
            thumbnailUrl: thumbnail,
            url: url
        )
    }
}

public struct YouTubeSearchResponse: Decodable, Sendable {
    public var items: [YouTubeVideoDTO]
    public var nextPageToken: String?

    private enum CodingKeys: String, CodingKey {
        case items, nextPageToken
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([YouTubeVideoDTO].self, forKey: .items)) ?? []
        nextPageToken = try? c.decode(String.self, forKey: .nextPageToken)
    }

    public var asPage: RecipeVideoSearchPage {
        RecipeVideoSearchPage(items: items.map(\.asResult), nextPageToken: nextPageToken)
    }
}

// MARK: - Translation

public struct TranslateBatchRequest: Encodable, Sendable {
    public var texts: [String]
    public var targetLanguage: String
    public var sourceLanguage: String
    public init(texts: [String], targetLanguage: String, sourceLanguage: String = "en") {
        self.texts = texts
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
    }
}

public struct TranslateBatchResponse: Decodable, Sendable {
    /// Order-aligned with the request's `texts`.
    public var translatedTexts: [String]

    private enum CodingKeys: String, CodingKey {
        case translatedTexts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        translatedTexts = (try? c.decode([String].self, forKey: .translatedTexts)) ?? []
    }
}

// MARK: - Notifications

public struct RegisterDeviceRequest: Encodable, Sendable {
    /// The FCM registration token, not the APNs device token.
    public var token: String
    public var platform: String
    /// IANA identifier; re-sent on every launch so the server's UTC slot
    /// self-corrects across travel and DST.
    public var timezone: String
    public var prepReminders: Bool?
    public var hourLocal: Int?
    public var afternoonPrepReminders: Bool?
    public var afternoonHourLocal: Int?

    public init(
        token: String,
        platform: String = "ios",
        timezone: String,
        prepReminders: Bool? = nil,
        hourLocal: Int? = nil,
        afternoonPrepReminders: Bool? = nil,
        afternoonHourLocal: Int? = nil
    ) {
        self.token = token
        self.platform = platform
        self.timezone = timezone
        self.prepReminders = prepReminders
        self.hourLocal = hourLocal
        self.afternoonPrepReminders = afternoonPrepReminders
        self.afternoonHourLocal = afternoonHourLocal
    }
}

public struct UnregisterDeviceRequest: Encodable, Sendable {
    public var token: String
    public init(token: String) { self.token = token }
}

public struct NotificationPreferencesRequest: Encodable, Sendable {
    public var prepReminders: Bool?
    public var hourLocal: Int?
    public var timezone: String?
    public var weeklyMenuEmails: Bool?
    public var afternoonPrepReminders: Bool?
    public var afternoonHourLocal: Int?

    public init(
        prepReminders: Bool? = nil,
        hourLocal: Int? = nil,
        timezone: String? = nil,
        weeklyMenuEmails: Bool? = nil,
        afternoonPrepReminders: Bool? = nil,
        afternoonHourLocal: Int? = nil
    ) {
        self.prepReminders = prepReminders
        self.hourLocal = hourLocal
        self.timezone = timezone
        self.weeklyMenuEmails = weeklyMenuEmails
        self.afternoonPrepReminders = afternoonPrepReminders
        self.afternoonHourLocal = afternoonHourLocal
    }
}

public struct NotificationPreferencesDTO: Decodable, Sendable {
    public var prepReminders: Bool
    public var hourLocal: Int
    public var timezone: String?
    /// Optional rather than defaulted, so a server that omits it can be told apart
    /// from one that sent `false`. See NotificationPreferencesDTOTests.
    public var afternoonPrepReminders: Bool?
    public var afternoonHourLocal: Int

    private enum CodingKeys: String, CodingKey {
        case prepReminders, hourLocal, timezone, afternoonPrepReminders, afternoonHourLocal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prepReminders = (try? c.decode(Bool.self, forKey: .prepReminders)) ?? true
        hourLocal = (try? c.decode(Int.self, forKey: .hourLocal)) ?? PrepReminderSettings.defaultHour
        timezone = try? c.decode(String.self, forKey: .timezone)
        afternoonPrepReminders = try? c.decode(Bool.self, forKey: .afternoonPrepReminders)
        afternoonHourLocal = (try? c.decode(Int.self, forKey: .afternoonHourLocal))
            ?? PrepReminderSettings.afternoonDefaultHour
    }
}

public struct NotificationPreferencesResponse: Decodable, Sendable {
    public var notificationPreferences: NotificationPreferencesDTO?
    public var weeklyMenuEmails: Bool?

    private enum CodingKeys: String, CodingKey {
        case notificationPreferences, weeklyMenuEmails
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notificationPreferences = try? c.decode(
            NotificationPreferencesDTO.self, forKey: .notificationPreferences
        )
        weeklyMenuEmails = try? c.decode(Bool.self, forKey: .weeklyMenuEmails)
    }

    public var settings: PrepReminderSettings {
        PrepReminderSettings(
            enabled: notificationPreferences?.prepReminders ?? true,
            hour: notificationPreferences?.hourLocal ?? PrepReminderSettings.defaultHour,
            // Inherit when the server omits it, matching the server's own rule.
            afternoonEnabled: notificationPreferences?.afternoonPrepReminders
                ?? notificationPreferences?.prepReminders ?? true,
            afternoonHour: notificationPreferences?.afternoonHourLocal
                ?? PrepReminderSettings.afternoonDefaultHour
        )
    }
}
