import KhanaKit
import SwiftUI

/// The four preference screens. Each is a `SheetScaffold` with its own eyebrow and
/// title, matching Android's settings dialogs one for one.
struct SettingsSheet: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    var screen: SettingsScreen
    var onClose: () -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    // Dietary
    @State private var dietary = DietaryPreferences()
    // Meals
    @State private var enabledTypes: Set<MealType> = []
    // Language
    @State private var language = SupportedLanguage.english
    // Prep reminders
    @State private var reminders = PrepReminderSettings()
    /// Saving replaces the whole preferences object server-side, so a form that
    /// failed to load must not be presented as if it were the user's real settings.
    @State private var didLoad = false
    #if DEBUG
    @State private var testMessage: String?
    #endif

    var body: some View {
        Group {
            switch screen {
            case .dietary: dietaryScreen
            case .meals: mealsScreen
            case .language: languageScreen
            case .prepReminder: prepReminderScreen
            }
        }
        .task { await loadCurrentValues() }
    }

    private func loadCurrentValues() async {
        switch screen {
        case .dietary:
            didLoad = await env.settings.loadDietary()
            dietary = env.settings.dietary ?? DietaryPreferences()
            if !didLoad {
                errorMessage = "Couldn't load your preferences. Close and try again."
            }
        case .meals:
            await env.settings.ensureMealSettings()
            enabledTypes = Set(env.settings.enabledTypes)
            didLoad = true
        case .language:
            didLoad = await env.settings.loadLanguage()
            language = env.settings.language.supported
            if !didLoad {
                errorMessage = "Couldn't load your language setting. Close and try again."
            }
        case .prepReminder:
            didLoad = await env.settings.loadPrepReminders()
            await env.push.refreshAuthorizationStatus()
            reminders = env.settings.prepReminders
            if !didLoad {
                errorMessage = "Couldn't load your reminder settings. Close and try again."
            }
        }
    }

    // MARK: - Dietary

    private var dietaryScreen: some View {
        SheetScaffold(
            eyebrow: "What you eat",
            title: "Dietary Preferences",
            isSaving: isSaving,
            isConfirmEnabled: didLoad,
            errorMessage: errorMessage,
            onCancel: close,
            onConfirm: {
                save(
                    { try await env.settings.saveDietary(dietary) },
                    analytics: AnalyticsEvents.Preferences.updateDietary,
                    parameters: [
                        AnalyticsProperties.isVegetarian: dietary.isVegetarian,
                    ]
                )
            }
        ) {
            DietaryControls(preferences: $dietary)
        }
    }

    // MARK: - Meal settings

    private var mealsScreen: some View {
        SheetScaffold(
            eyebrow: "When you eat",
            title: "Meal Settings",
            isSaving: isSaving,
            isConfirmEnabled: didLoad && !enabledTypes.isEmpty,
            errorMessage: errorMessage,
            onCancel: close,
            onConfirm: {
                save(
                    { try await env.settings.saveMealSettings(Array(enabledTypes)) },
                    analytics: AnalyticsEvents.Preferences.updateMealSettings,
                    parameters: [
                        AnalyticsProperties.enabledMealTypes:
                            MealType.sorted(Array(enabledTypes)).map(\.key),
                    ]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Courses on the card".eyebrow)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)

                ForEach(MealType.allCases) { type in
                    Button {
                        if enabledTypes.contains(type) {
                            enabledTypes.remove(type)
                        } else {
                            enabledTypes.insert(type)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: enabledTypes.contains(type)
                                  ? "checkmark.square.fill" : "square")
                                .font(.system(size: 19))
                                .foregroundStyle(enabledTypes.contains(type)
                                                 ? Kkb.terracotta500 : Kkb.textSecondary.opacity(0.5))
                            Text(type.emoji).font(.system(size: 18))
                            Text(type.displayName)
                                .kkbFont(.bodyLarge)
                                .foregroundStyle(Kkb.textPrimary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(enabledTypes.contains(type) ? [.isSelected] : [])
                }

                if enabledTypes.isEmpty {
                    Text("Pick at least one meal to keep planning useful.")
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.terracotta600)
                }
            }
        }
    }

    // MARK: - Language

    private var languageScreen: some View {
        SheetScaffold(
            eyebrow: "PDF & shopping list",
            title: "Language",
            isSaving: isSaving,
            isConfirmEnabled: didLoad,
            errorMessage: errorMessage,
            onCancel: close,
            onConfirm: {
                save(
                    { try await env.settings.saveLanguage(language.code) },
                    analytics: AnalyticsEvents.Preferences.updateLanguage,
                    parameters: [AnalyticsProperties.language: language.code]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("""
                Meal plans and shopping lists are translated into this language when \
                you export them. The app's own text stays in English.
                """)
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(SupportedLanguage.allCases) { candidate in
                    Button { language = candidate } label: {
                        HStack(spacing: 12) {
                            Image(systemName: language == candidate
                                  ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 19))
                                .foregroundStyle(language == candidate
                                                 ? Kkb.terracotta500 : Kkb.textSecondary.opacity(0.5))
                            Text(candidate.displayName)
                                .kkbFont(.bodyLarge)
                                .foregroundStyle(Kkb.textPrimary)
                            if candidate != .english {
                                Text(candidate.nativeName)
                                    .kkbFont(.bodyMedium)
                                    .foregroundStyle(Kkb.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Prep reminders

    private var prepReminderScreen: some View {
        SheetScaffold(
            eyebrow: "Evening nudge",
            title: "Prep Reminders",
            isSaving: isSaving,
            isConfirmEnabled: didLoad,
            errorMessage: errorMessage,
            onCancel: close,
            onConfirm: {
                Task {
                    // Only ask for the system prompt when switching the feature on,
                    // and only if it hasn't been answered already.
                    if reminders.enabled, !env.push.areNotificationsEnabled {
                        await env.push.requestAuthorization()
                    }
                    save(
                        {
                            try await env.settings.savePrepReminders(reminders)
                            await env.prepReminders.reschedule()
                        },
                        analytics: AnalyticsEvents.Preferences.updateNotifications,
                        parameters: ["prep_reminders": reminders.enabled]
                    )
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("""
                The evening before, we'll tell you what tomorrow needs — soaking, \
                marinating, batter to ferment — so nothing derails the morning.
                """)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if !env.push.isConfigured {
                    noticeCard(
                        """
                        Reminders are scheduled on this phone, so open the app at \
                        least once a week to keep them coming — and changes you make \
                        on the web or on Android won't show up here until you do.
                        """
                    )
                }

                KkbToggleRow(
                    title: "Remind me the evening before",
                    isOn: $reminders.enabled
                )

                if reminders.enabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remind me at".eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.accentText)
                        HStack(spacing: 8) {
                            ForEach(PrepReminderSettings.selectableHours, id: \.self) { hour in
                                KkbChip(
                                    title: hourLabel(hour),
                                    isSelected: reminders.hour == hour
                                ) {
                                    reminders.hour = hour
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }

                // "Never asked" and "asked and refused" need different offers. iOS
                // only adds an app's Notifications page once permission has been
                // requested at least once, so sending a `.notDetermined` user to
                // Settings lands them on a page with no notification row at all.
                switch env.push.authorizationStatus {
                case .notDetermined:
                    KkbSecondaryButton(title: "Allow notifications", systemImage: "bell") {
                        Task {
                            if await env.push.requestAuthorization() {
                                await env.prepReminders.reschedule()
                            }
                        }
                    }
                case .denied:
                    VStack(alignment: .leading, spacing: 8) {
                        noticeCard("Notifications are switched off for this app.")
                        KkbSecondaryButton(title: "Open Settings", systemImage: "gear") {
                            env.push.openSystemSettings()
                        }
                    }
                default:
                    EmptyView()
                }

                #if DEBUG
                // Not shipped: `#if DEBUG` compiles this out of Release. It exists
                // because the honest way to check an evening reminder is otherwise
                // to wait until evening.
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(Kkb.hairline)
                    Text("Debug".eyebrow)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.textSecondary)
                    KkbSecondaryButton(title: "Send a test reminder now",
                                       systemImage: "bell.badge") {
                        Task { testMessage = await env.prepReminders.scheduleTestReminder() }
                    }
                    if let testMessage {
                        Text(testMessage)
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif
            }
            .animation(.snappy(duration: 0.2), value: reminders.enabled)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(suffix)"
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .kkbFont(.bodySmall)
            .foregroundStyle(Kkb.marigoldText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Kkb.marigoldSurface.opacity(0.7))
            )
    }

    // MARK: - Shared

    private func close() {
        onClose()
        dismiss()
    }

    private func save(
        _ operation: @escaping () async throws -> Void,
        analytics action: String,
        parameters: [String: Any]
    ) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await operation()
                env.analytics.track(
                    action, category: AnalyticsEvents.Category.preferences, parameters: parameters
                )
                close()
            } catch let error as APIError {
                errorMessage = error.userMessage(
                    fallback: "Failed to save preferences. Please try again."
                )
            } catch {
                errorMessage = "Failed to save preferences. Please try again."
            }
            isSaving = false
        }
    }
}
