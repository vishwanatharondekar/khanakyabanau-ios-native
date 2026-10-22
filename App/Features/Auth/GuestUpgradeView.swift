import KhanaKit
import SwiftUI

/// Converts a guest into a registered account.
///
/// The server mints a **new** user id and copies the guest's meal plans and
/// preferences across, returning a new token — so this is not "sign up", and the
/// copy says so: nothing the user has planned is lost.
struct GuestUpgradeView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var onCompleted: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// What is stopping the form from being sent, worded for the user; nil
    /// once it can go. The button never disables on this: a tap on an
    /// incomplete form names the field to fix rather than doing nothing.
    private var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter your name" }
        if !email.contains("@") { return "Enter a valid email address" }
        if password.count < PasswordRules.minLength {
            return "Password needs at least \(PasswordRules.minLength) characters"
        }
        return nil
    }

    var body: some View {
        SheetScaffold(
            eyebrow: "Free forever",
            title: "Create your account",
            confirmTitle: "Create account",
            isSaving: isSubmitting,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onConfirm: submit
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What you'll get")
                        .kkbFont(.titleMedium)
                        .foregroundStyle(Kkb.textPrimary)
                    benefit("Unlimited AI meal generations")
                    benefit("Unlimited shopping lists")
                    benefit("Your plans saved and synced")
                    benefit("Access from any device")
                }

                Text("Everything you've planned so far comes with you.")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)

                KkbTextField(
                    label: "Full name",
                    placeholder: "Your name",
                    text: $name,
                    textContentType: .name,
                    autocapitalization: .words
                )
                KkbTextField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    keyboard: .emailAddress,
                    textContentType: .emailAddress,
                    autocapitalization: .never
                )
                KkbTextField(
                    label: "Password",
                    placeholder: "At least \(PasswordRules.minLength) characters",
                    text: $password,
                    isSecure: true,
                    textContentType: .newPassword,
                    autocapitalization: .never,
                    submitLabel: .go
                ) { submit() }
            }
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Kkb.sage500)
                .font(.system(size: 14))
            Text(text)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        if let validationError {
            errorMessage = validationError
            return
        }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await env.auth.upgradeGuest(
                    email: email, password: password, name: name
                )
                // Tracked as `register`, matching Android and the web app — an
                // upgrade is a new registered account by any funnel's reckoning.
                env.analytics.track(
                    AnalyticsEvents.Auth.register, category: AnalyticsEvents.Category.auth
                )
                try await session.signedIn()
                onCompleted()
                dismiss()
            } catch let error as APIError {
                errorMessage = error.userMessage(
                    fallback: "Could not create your account. Please try again."
                )
                env.analytics.trackError("guest_upgrade_error", message: errorMessage ?? "")
            } catch {
                errorMessage = "Could not create your account. Please try again."
            }
            isSubmitting = false
        }
    }
}

/// The one password rule the app enforces, shared by sign-up and the guest
/// upgrade. Android uses the same number; the web form and the server set none.
/// Sign-in deliberately does not apply it — an account made on the web can
/// have a shorter password and must still be able to sign in here.
enum PasswordRules {
    static let minLength = 4
}
