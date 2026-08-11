import Foundation

public struct User: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var email: String?
    public var name: String
    public var isGuest: Bool
    public var onboardingCompleted: Bool
    /// Only populated by `GET /api/auth/profile` and `GET /api/auth/guest`.
    public var cuisinePreferences: [String]
    /// Only populated by `GET /api/auth/profile` and `GET /api/auth/guest`.
    public var dietaryPreferences: DietaryPreferences?
    /// Guest allowances are lifetime, not per-day, and only enforced for guests.
    public var aiUsageCount: Int
    public var shoppingListUsageCount: Int
    /// Server-supplied ceilings; absent for registered users, who are unlimited.
    public var guestUsageLimits: GuestUsageLimits?

    public init(
        id: String,
        email: String? = nil,
        name: String,
        isGuest: Bool = false,
        onboardingCompleted: Bool = false,
        cuisinePreferences: [String] = [],
        dietaryPreferences: DietaryPreferences? = nil,
        aiUsageCount: Int = 0,
        shoppingListUsageCount: Int = 0,
        guestUsageLimits: GuestUsageLimits? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.isGuest = isGuest
        self.onboardingCompleted = onboardingCompleted
        self.cuisinePreferences = cuisinePreferences
        self.dietaryPreferences = dietaryPreferences
        self.aiUsageCount = aiUsageCount
        self.shoppingListUsageCount = shoppingListUsageCount
        self.guestUsageLimits = guestUsageLimits
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        email = try? c.decode(String.self, forKey: .email)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        isGuest = (try? c.decode(Bool.self, forKey: .isGuest)) ?? false
        onboardingCompleted = (try? c.decode(Bool.self, forKey: .onboardingCompleted)) ?? false
        cuisinePreferences = (try? c.decode([String].self, forKey: .cuisinePreferences)) ?? []
        dietaryPreferences = try? c.decode(DietaryPreferences.self, forKey: .dietaryPreferences)
        aiUsageCount = (try? c.decode(Int.self, forKey: .aiUsageCount)) ?? 0
        shoppingListUsageCount = (try? c.decode(Int.self, forKey: .shoppingListUsageCount)) ?? 0
        guestUsageLimits = try? c.decode(GuestUsageLimits.self, forKey: .guestUsageLimits)
    }

    /// Remaining free AI generations, or nil when the user is unlimited.
    public var remainingAIGenerations: Int? {
        guard isGuest, let limit = guestUsageLimits?.aiGeneration else { return nil }
        return max(0, limit - aiUsageCount)
    }

    /// Remaining free shopping lists, or nil when the user is unlimited.
    public var remainingShoppingLists: Int? {
        guard isGuest, let limit = guestUsageLimits?.shoppingList else { return nil }
        return max(0, limit - shoppingListUsageCount)
    }
}

public struct GuestUsageLimits: Codable, Hashable, Sendable {
    public var aiGeneration: Int
    public var shoppingList: Int

    public init(aiGeneration: Int = 3, shoppingList: Int = 3) {
        self.aiGeneration = aiGeneration
        self.shoppingList = shoppingList
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aiGeneration = (try? c.decode(Int.self, forKey: .aiGeneration)) ?? 3
        shoppingList = (try? c.decode(Int.self, forKey: .shoppingList)) ?? 3
    }
}

/// Sent and received flat (not wrapped) by `GET|PUT /api/auth/dietary-preferences`.
/// The GET can legitimately return a bare `null` when the user has never saved any.
public struct DietaryPreferences: Codable, Hashable, Sendable {
    public var isVegetarian: Bool
    /// Lowercase `DayOfWeek` keys.
    public var nonVegDays: [String]
    public var showCalories: Bool
    public var dailyCalorieTarget: Int
    public var preferHealthy: Bool
    public var glutenFree: Bool
    public var nutsFree: Bool
    public var lactoseIntolerant: Bool

    public static let calorieRange = 500...5000
    public static let calorieStep = 100
    public static let defaultCalorieTarget = 2000

    public init(
        isVegetarian: Bool = false,
        nonVegDays: [String] = [],
        showCalories: Bool = false,
        dailyCalorieTarget: Int = DietaryPreferences.defaultCalorieTarget,
        preferHealthy: Bool = false,
        glutenFree: Bool = false,
        nutsFree: Bool = false,
        lactoseIntolerant: Bool = false
    ) {
        self.isVegetarian = isVegetarian
        self.nonVegDays = nonVegDays
        self.showCalories = showCalories
        self.dailyCalorieTarget = dailyCalorieTarget
        self.preferHealthy = preferHealthy
        self.glutenFree = glutenFree
        self.nutsFree = nutsFree
        self.lactoseIntolerant = lactoseIntolerant
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isVegetarian = (try? c.decode(Bool.self, forKey: .isVegetarian)) ?? false
        nonVegDays = (try? c.decode([String].self, forKey: .nonVegDays)) ?? []
        showCalories = (try? c.decode(Bool.self, forKey: .showCalories)) ?? false
        dailyCalorieTarget = (try? c.decode(Int.self, forKey: .dailyCalorieTarget))
            ?? DietaryPreferences.defaultCalorieTarget
        preferHealthy = (try? c.decode(Bool.self, forKey: .preferHealthy)) ?? false
        glutenFree = (try? c.decode(Bool.self, forKey: .glutenFree)) ?? false
        nutsFree = (try? c.decode(Bool.self, forKey: .nutsFree)) ?? false
        lactoseIntolerant = (try? c.decode(Bool.self, forKey: .lactoseIntolerant)) ?? false
    }

    /// The value reported to analytics as `dietary_preference`.
    public var analyticsValue: String {
        if isVegetarian { return "vegetarian" }
        return nonVegDays.isEmpty ? "non-vegetarian" : "mixed"
    }
}

/// Wrapped as `{"mealSettings": {…}}` on both GET and PUT.
public struct MealSettings: Codable, Hashable, Sendable {
    public var enabledMealTypes: [String]

    public init(enabledMealTypes: [String] = MealType.allCases.map(\.key)) {
        self.enabledMealTypes = enabledMealTypes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledMealTypes = (try? c.decode([String].self, forKey: .enabledMealTypes))
            ?? MealType.allCases.map(\.key)
    }

    /// Enabled types, always in chronological order regardless of stored order.
    public var enabledTypes: [MealType] {
        MealType.sorted(enabledMealTypes.compactMap(MealType.fromKey))
    }

    /// What the app shows before any server response has arrived. Android caches
    /// the last known value to disk precisely so this default is rarely seen.
    public static let fallback = MealSettings(enabledMealTypes: MealType.defaultEnabled.map(\.key))
}

/// Returned and sent flat by `GET|PUT /api/auth/language-preferences`.
public struct LanguagePreferences: Codable, Hashable, Sendable {
    public var language: String

    public init(language: String = "en") { self.language = language }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? c.decode(String.self, forKey: .language)) ?? "en"
    }

    public var supported: SupportedLanguage { SupportedLanguage.fromCode(language) }
}

/// The 10 languages the PDF exporters can render. Codes match the web app's
/// `lib/translate-api.ts`; the native names are what the picker shows.
public enum SupportedLanguage: String, CaseIterable, Sendable, Identifiable {
    case english = "en"
    case hindi = "hi"
    case marathi = "mr"
    case bengali = "bn"
    case tamil = "ta"
    case telugu = "te"
    case kannada = "kn"
    case malayalam = "ml"
    case gujarati = "gu"
    case punjabi = "pa"

    public var id: String { rawValue }
    public var code: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .hindi: "Hindi"
        case .marathi: "Marathi"
        case .bengali: "Bengali"
        case .tamil: "Tamil"
        case .telugu: "Telugu"
        case .kannada: "Kannada"
        case .malayalam: "Malayalam"
        case .gujarati: "Gujarati"
        case .punjabi: "Punjabi"
        }
    }

    public var nativeName: String {
        switch self {
        case .english: "English"
        case .hindi: "हिन्दी"
        case .marathi: "मराठी"
        case .bengali: "বাংলা"
        case .tamil: "தமிழ்"
        case .telugu: "తెలుగు"
        case .kannada: "ಕನ್ನಡ"
        case .malayalam: "മലയാളം"
        case .gujarati: "ગુજરાતી"
        case .punjabi: "ਪੰਜਾਬੀ"
        }
    }

    public static func fromCode(_ code: String) -> SupportedLanguage {
        SupportedLanguage(rawValue: code.lowercased()) ?? .english
    }
}

/// Local mirror of the server's `notificationPreferences`. `hour` is the local
/// hour the evening nudge should arrive and `afternoonHour` the midday one; the
/// server derives its own UTC slots.
public struct PrepReminderSettings: Hashable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var afternoonEnabled: Bool
    public var afternoonHour: Int

    public static let defaultHour = 21
    public static let selectableHours = Array(19...23)

    /// Late enough that the morning is over, early enough to still act: an 8-hour
    /// soak for a 20:00 dinner has to start at 12:00.
    public static let afternoonDefaultHour = 11
    public static let afternoonSelectableHours = Array(10...14)

    public init(
        enabled: Bool = true,
        hour: Int = PrepReminderSettings.defaultHour,
        afternoonEnabled: Bool = true,
        afternoonHour: Int = PrepReminderSettings.afternoonDefaultHour
    ) {
        self.enabled = enabled
        self.hour = hour
        self.afternoonEnabled = afternoonEnabled
        self.afternoonHour = afternoonHour
    }
}
