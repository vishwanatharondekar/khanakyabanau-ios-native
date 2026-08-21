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
    var onSignOut: () -> Void
    /// Shown to guests too: a guest account holds real server-side data, and a
    /// reviewer trying the app without signing up must still be able to find this.
    var onDeleteAccount: () -> Void

    private var user: User? { session.user }
    private var isGuest: Bool { session.isGuest }

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    identity

                    VStack(spacing: 2) {
                        if isGuest {
                            DrawerRow(
                                title: "Create account",
                                systemImage: "person.crop.circle.badge.plus",
                                tint: Kkb.terracotta600,
                                isEmphasised: true,
                                action: onCreateAccount
                            )
                        }
                        DrawerRow(
                            title: "Dietary preferences",
                            systemImage: "leaf",
                            tint: Kkb.sage600
                        ) { open(.dietary) }
                        DrawerRow(
                            title: "Meal settings",
                            systemImage: "list.bullet.rectangle",
                            tint: Kkb.terracotta600
                        ) { open(.meals) }
                        DrawerRow(
                            title: "Prep reminders",
                            systemImage: "bell.badge",
                            tint: Kkb.marigold600
                        ) { open(.prepReminder) }
                        DrawerRow(
                            title: "Language",
                            systemImage: "character.bubble",
                            tint: Kkb.marigold600
                        ) { open(.language) }
                    }

                    Divider().overlay(Kkb.hairline)

                    if isGuest {
                        DrawerRow(
                            title: "Already have an account? Sign In",
                            systemImage: "arrow.right.square",
                            tint: Kkb.terracotta600,
                            action: onSignIn
                        )
                    } else {
                        DrawerRow(
                            title: "Logout",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            tint: Kkb.terracotta600,
                            action: onSignOut
                        )
                    }

                    DrawerRow(
                        title: "Delete account",
                        systemImage: "trash",
                        tint: Kkb.terracotta700,
                        action: onDeleteAccount
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
                ZStack {
                    Circle().fill(Kkb.terracottaSurface).frame(width: 44, height: 44)
                    ChefHatIcon(size: 24, color: Kkb.terracotta600)
                }
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

private struct DrawerRow: View {
    var title: String
    var systemImage: String
    var tint: Color
    var isEmphasised: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(title)
                    .kkbFont(.bodyLarge)
                    .fontWeight(isEmphasised ? .semibold : .regular)
                    .foregroundStyle(isEmphasised ? tint : Kkb.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEmphasised ? Kkb.terracottaSurface.opacity(0.6) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
