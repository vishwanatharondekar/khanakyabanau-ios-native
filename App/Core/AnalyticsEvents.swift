import Foundation

/// The event vocabulary, copied from Android's `AnalyticsEvents.kt` and the web
/// app's `lib/analytics.ts`.
///
/// Mixpanel event names are `"{category}_{action}"`, so a rename here silently
/// forks the funnels the other two clients already populate. Treat these strings
/// as a wire contract.
enum AnalyticsEvents {
    enum Category {
        static let auth = "auth"
        static let mealPlanning = "meal_planning"
        static let aiFeatures = "ai_features"
        static let preferences = "preferences"
        static let navigation = "navigation"
        static let onboarding = "onboarding"
        static let pdf = "pdf"
        static let shopping = "shopping"
        static let share = "share"
        static let mood = "mood"
        static let videoManagement = "video_management"
    }

    enum Auth {
        static let login = "login"
        static let register = "register"
        static let logout = "logout"
        static let guestStart = "guest_start"
        static let deleteAccount = "delete_account"
    }

    enum Meal {
        static let add = "meal_add"
        static let update = "meal_update"
        static let delete = "meal_delete"
        static let clearWeek = "meal_clear_week"
    }

    enum AI {
        static let generateMeals = "ai_generate_meals"
        static let suggestMeal = "ai_suggest_meal"
        static let extractIngredients = "ai_extract_ingredients"
    }

    enum Preferences {
        static let updateDietary = "preferences_update_dietary"
        static let updateCuisine = "preferences_update_cuisine"
        static let updateLanguage = "preferences_update_language"
        static let updateMealSettings = "preferences_update_meal_settings"
        static let updateNotifications = "preferences_update_notifications"
    }

    enum Navigation {
        static let weekChange = "navigation_week_change"
        static let modeSwitch = "navigation_mode_switch"
        static let preferencesOpen = "navigation_preferences_open"
    }

    enum Onboarding {
        static let start = "onboarding_start"
        static let complete = "onboarding_complete"
    }

    enum PDF {
        static let generateMealPlan = "pdf_generate_meal_plan"
        static let generateShoppingList = "pdf_generate_shopping_list"
        static let downloadMealPlan = "pdf_download_meal_plan"
        static let downloadShoppingList = "pdf_download_shopping_list"
    }

    enum Shopping {
        static let listShare = "shopping_list_share"
        static let listCopy = "shopping_list_copy"
        static let scopeChange = "shopping_list_scope_change"
        static let pruneToggle = "shopping_list_prune_toggle"
    }

    enum Share {
        static let whatsappWeekPlan = "share_whatsapp_week_plan"
        static let whatsappShoppingList = "share_whatsapp_shopping_list"
    }

    enum Mood {
        static let open = "mood_open"
        static let submit = "mood_submit"
        static let applySuggestion = "mood_apply_suggestion"
    }

    enum Video {
        static let openModal = "video_open_modal"
        static let addURL = "video_add_url"
        static let play = "video_play"
    }
}

enum AnalyticsProperties {
    static let device = "device"
    static let day = "day"
    static let mealType = "meal_type"
    static let mealName = "meal_name"
    static let isNewMeal = "is_new_meal"
    static let weekStart = "week_start"
    static let userID = "user_id"
    static let isGuest = "is_guest"
    static let fromMode = "from_mode"
    static let toMode = "to_mode"
    static let ingredientCount = "ingredient_count"
    static let hasIngredients = "has_ingredients"
    static let moodCuisineCount = "mood_cuisine_count"
    static let source = "source"
    static let shareTarget = "share_target"
    static let language = "language"
    static let isVegetarian = "is_vegetarian"
    static let enabledMealTypes = "enabled_meal_types"
    static let direction = "direction"
    static let screen = "screen"
    static let cuisineCount = "cuisine_count"
    static let itemCount = "item_count"
    static let dayCount = "day_count"
    static let prunedCount = "pruned_count"
    static let videoURL = "video_url"
}

struct AnalyticsEvent {
    var action: String
    var category: String
    var label: String?
    var value: Double?
    var parameters: [String: Any]

    init(
        action: String,
        category: String,
        label: String? = nil,
        value: Double? = nil,
        parameters: [String: Any] = [:]
    ) {
        self.action = action
        self.category = category
        self.label = label
        self.value = value
        self.parameters = parameters
    }

    /// Mixpanel's name for this event.
    var name: String { "\(category)_\(action)" }
}
