import KhanaKit
import SwiftUI

/// Permanent account deletion, reachable from the drawer.
///
/// App Store guideline 5.1.1(v) and Play's account-deletion policy both require
/// an app that creates accounts to let the user destroy one from inside the app —
/// not by writing in, and not as a deactivation that support can reverse.
///
/// A guest sees no password field, because the server has none to check, but does
/// get the blunter warning: a guest account has no email, so there is nothing to
/// sign back in with once it is gone.
struct DeleteAccountView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var isGuest: Bool { session.isGuest }
    /// A registered account must re-enter its password; the server rejects the
    /// request otherwise, so there is nothing to send until they do.
    private var canSubmit: Bool { isGuest || !password.isEmpty }

    var body: some View {
        SheetScaffold(
            eyebrow: "This cannot be undone",
            title: "Delete your account",
            confirmTitle: "Delete forever",
            isSaving: isDeleting,
            isConfirmEnabled: canSubmit,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onConfirm: submit
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What gets deleted")
                        .kkbFont(.titleMedium)
                        .foregroundStyle(Kkb.textPrimary)
                    consequence("Every week you have planned")
                    consequence("Your shopping lists")
                    consequence("Your dietary and cuisine preferences")
                    consequence("The recipe videos you saved")
                    consequence("Your prep reminder settings")
                }

                Text(isGuest
                     ? """
                       You are signed in as a guest, so there is no email to sign \
                       back in with. Once this is gone it cannot be recovered from \
                       any device.
                       """
                     : """
                       This removes your account everywhere, on every device. To \
                       use the app again you would need to create a new one.
                       """)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGuest {
                    KkbTextField(
                        label: "Confirm your password",
                        placeholder: "Your password",
                        text: $password,
                        isSecure: true,
                        textContentType: .password,
                        autocapitalization: .never,
                        submitLabel: .go
                    ) { submit() }
                }
            }
        }
    }

    private func consequence(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Kkb.terracotta600)
                .font(.system(size: 14))
            Text(text)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
        }
    }

    private func submit() {
        guard canSubmit, !isDeleting else { return }
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await session.deleteAccount(password: isGuest ? nil : password)
                dismiss()
            } catch let error as APIError {
                errorMessage = error.userMessage(
                    fallback: "Could not delete your account. Please try again."
                )
                env.analytics.trackError("delete_account_error", message: errorMessage ?? "")
            } catch {
                errorMessage = "Could not delete your account. Please try again."
            }
            isDeleting = false
        }
    }
}
