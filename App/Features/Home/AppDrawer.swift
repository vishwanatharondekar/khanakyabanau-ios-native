import KhanaKit
import SwiftUI

enum SettingsScreen: String, Identifiable {
    case dietary, meals, language, prepReminder
    var id: String { rawValue }

    /// Sent as the `screen` property on `navigation_preferences_open`.
    var analyticsName: String {
        switch self {
        case .dietary: "dietary"
        case .meals: "meals"
        case .language: "language"
        case .prepReminder: "prep_reminder"
        }
    }
}

/// The side menu. On Android this is a `ModalNavigationDrawer`; on iOS it arrives
/// as a sheet, which is the platform-native equivalent for a menu of destinations.
///
/// The guest rules are load-bearing and match the web app: a guest is offered
/// "Create account" and "Already have an account? Sign In", and is **never** shown
/// Logout — signing out of an anonymous account would silently destroy their plans.
struct AppDrawer: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var onSelectSettings: (SettingsScreen) -> Void
    var onCreateAccount: () -> Void
    /// A guest who already has an account needs the sign-in form, not the
    /// create-an-account form — signing in is how they get back to their data.
    var onSignIn: () -> Void
    /// Logout and account deletion live behind this rather than in the drawer:
    /// they are the only actions here that end or destroy the account, and keeping
    /// them out also stops the drawer outgrowing its medium detent.
    var onOpenAccount: () -> Void

    private var user: User? { session.user }
    private var isGuest: Bool { session.isGuest }

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    identity

                    VStack(spacing: 2) {
                        if isGuest {
                            MenuRow(
                                title: "Create account",
                                systemImage: "person.crop.circle.badge.plus",
                                tint: Kkb.terracotta600,
                                isEmphasised: true,
                                action: onCreateAccount
                            )
                        }
                        MenuRow(
                            title: "Dietary preferences",
                            systemImage: "leaf",
                            tint: Kkb.sage600
                        ) { open(.dietary) }
                        MenuRow(
                            title: "Meal settings",
                            systemImage: "list.bullet.rectangle",
                            tint: Kkb.terracotta600
                        ) { open(.meals) }
                        MenuRow(
                            title: "Prep reminders",
                            systemImage: "bell.badge",
                            tint: Kkb.marigold600
                        ) { open(.prepReminder) }
                        MenuRow(
                            title: "Language",
                            systemImage: "character.bubble",
                            tint: Kkb.marigold600
                        ) { open(.language) }
                    }

                    Divider().overlay(Kkb.hairline)

                    if isGuest {
                        MenuRow(
                            title: "Already have an account? Sign In",
                            systemImage: "arrow.right.square",
                            tint: Kkb.terracotta600,
                            action: onSignIn
                        )
                    }

                    MenuRow(
                        title: "Account",
                        systemImage: "person.crop.circle",
                        tint: Kkb.terracotta600,
                        action: onOpenAccount
                    )
                }
                .padding(20)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // No tinted circle behind it: the icon carries its own ground.
                AppMarkIcon(size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("khana kya banau")
                        .kkbFont(.displaySmall)
                        .foregroundStyle(Kkb.textPrimary)
                    Text("WEEKLY MEAL PLANNER")
                        .kkbFont(.sectionLabel)
                        .tracking(3)
                        .foregroundStyle(Kkb.accentText)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("SIGNED IN AS")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.textSecondary)
                Text(isGuest ? "Guest" : (user?.name ?? ""))
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                Text(isGuest
                     ? "Create an account to save your plans"
                     : (user?.email ?? ""))
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ screen: SettingsScreen) {
        env.analytics.track(
            AnalyticsEvents.Navigation.preferencesOpen,
            category: AnalyticsEvents.Category.navigation,
            parameters: [AnalyticsProperties.screen: screen.analyticsName]
        )
        onSelectSettings(screen)
    }
}
