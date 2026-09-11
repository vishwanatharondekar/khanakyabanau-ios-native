import KhanaKit
import SwiftUI

/// Everything that used to hide behind the hamburger, as a destination.
///
/// Reminders comes first on purpose. Prep reminders are the feature people
/// install the app for, they were the third item in the drawer, and the drawer
/// told a guest nothing about them at all. Here a guest sees the row and is
/// told what an account would buy them.
///
/// The settings sheets are reused exactly as the drawer used them. Turning them
/// into their own screens is a later, separate improvement and carries none of
/// this screen's value.
///
/// Two things the webapp's `/me` has and this does not, both deliberate. Saved
/// recipe videos has no standalone screen on iOS — videos are picked per meal
/// through `RecipeVideoSheet`. Ready-made meal plans is a web route with no iOS
/// destination; `readyMadePlans` stays true in the brand record, it simply has
/// nothing to point at on this platform.
struct MeView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    var onSelectSettings: (SettingsScreen) -> Void
    var onCreateAccount: () -> Void
    /// A guest who already has an account needs the sign-in form, not the
    /// create-an-account form — signing in is how they get back to their data.
    var onSignIn: () -> Void
    /// Logout and account deletion live behind this rather than inline: they are
    /// the only actions here that end or destroy the account.
    var onOpenAccount: () -> Void

    private var user: User? { session.user }
    private var isGuest: Bool { session.isGuest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identity

                group("Reminders") {
                    if isGuest {
                        MenuRow(
                            title: "Prep reminders",
                            systemImage: "bell.badge",
                            tint: Kkb.marigold600,
                            subtitle: "Create an account to get soaking and thawing nudges",
                            action: onCreateAccount
                        )
                    } else {
                        MenuRow(
                            title: "Prep reminders",
                            systemImage: "bell.badge",
                            tint: Kkb.marigold600,
                            subtitle: "Evening and midday nudges for advance prep"
                        ) { open(.prepReminder) }
                    }
                }

                group("Plan") {
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
                }

                group("App") {
                    MenuRow(
                        title: "Language",
                        systemImage: "character.bubble",
                        tint: Kkb.marigold600
                    ) { open(.language) }

                    if isGuest {
                        MenuRow(
                            title: "Create account",
                            systemImage: "person.crop.circle.badge.plus",
                            tint: Kkb.terracotta600,
                            isEmphasised: true,
                            subtitle: "Keep your plans across devices",
                            action: onCreateAccount
                        )
                        MenuRow(
                            title: "Already have an account? Sign In",
                            systemImage: "arrow.right.square",
                            tint: Kkb.terracotta600,
                            action: onSignIn
                        )
                    } else {
                        MenuRow(
                            title: "Account",
                            systemImage: "person.crop.circle",
                            tint: Kkb.terracotta600,
                            action: onOpenAccount
                        )
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kkbPageGround()
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isGuest ? "Guest" : (user?.name ?? ""))
                .kkbFont(.displayMedium)
                .foregroundStyle(Kkb.textPrimary)
            Text(isGuest
                 ? "Create an account to save your plans"
                 : (user?.email ?? ""))
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func group(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .kkbFont(.sectionLabel)
                .tracking(3)
                .foregroundStyle(Kkb.textSecondary)
                .padding(.horizontal, 12)
            VStack(spacing: 2) { content() }
        }
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
