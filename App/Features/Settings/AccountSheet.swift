import KhanaKit
import SwiftUI

/// Logout and account deletion, split out of the drawer.
///
/// The drawer is navigation; these two are the only entries that end or destroy
/// the account, and they are the ones that need room to explain themselves.
/// Grouping them also keeps the drawer inside its medium detent — with both rows
/// inline, "Delete account" sat below the fold.
struct AccountSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showingDelete = false

    private var user: User? { session.user }
    private var isGuest: Bool { session.isGuest }

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    identity

                    VStack(spacing: 2) {
                        // A guest is never offered Logout. An anonymous account has
                        // no email to sign back in with, so leaving it would
                        // silently destroy everything they had planned — the same
                        // rule the drawer has always enforced.
                        if !isGuest {
                            MenuRow(
                                title: "Logout",
                                systemImage: "rectangle.portrait.and.arrow.right",
                                tint: Kkb.terracotta600
                            ) {
                                Task { await session.signOut() }
                            }
                        }
                        MenuRow(
                            title: "Delete account",
                            systemImage: "trash",
                            tint: Kkb.terracotta700
                        ) { showingDelete = true }
                    }

                    Text(isGuest
                         ? """
                           Creating an account keeps your plans safe and lets you \
                           sign in from another device.
                           """
                         : """
                           Logging out leaves your account and everything in it \
                           untouched. Deleting does not.
                           """)
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        // Two rows at most, so a full-height sheet would be mostly empty ground.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingDelete) {
            DeleteAccountView()
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SIGNED IN AS")
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.textSecondary)
            Text(isGuest ? "Guest" : (user?.name ?? ""))
                .kkbFont(.displaySmall)
                .foregroundStyle(Kkb.textPrimary)
            Text(isGuest ? "No account yet" : (user?.email ?? ""))
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
