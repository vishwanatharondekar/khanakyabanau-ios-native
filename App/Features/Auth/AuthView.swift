import KhanaKit
import SwiftUI

/// Sign in / Sign up. One form, toggled by the same segmented pill the rest of the
/// app uses. There is no social sign-in anywhere in this product — the backend has
/// no OAuth path at all — so email and password is the whole surface.
struct AuthView: View {
    private enum Mode: Int { case signIn, signUp }
    private enum Field: Hashable { case name, email, password }

    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    var onBack: () -> Void

    @State private var mode = Mode.signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?
    @Namespace private var segmentNamespace

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        return mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                PaperCard(cornerRadius: 28, padding: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        SegmentedTabs(
                            options: [.init("Sign in"), .init("Sign up")],
                            selection: Binding(
                                get: { mode.rawValue },
                                set: { mode = Mode(rawValue: $0) ?? .signIn; errorMessage = nil }
                            ),
                            namespace: segmentNamespace
                        )

                        if mode == .signUp {
                            KkbTextField(
                                label: "Full name",
                                placeholder: "Your name",
                                text: $name,
                                textContentType: .name,
                                autocapitalization: .words
                            ) { focused = .email }
                            .focused($focused, equals: .name)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        KkbTextField(
                            label: "Email",
                            placeholder: "you@example.com",
                            text: $email,
                            keyboard: .emailAddress,
                            textContentType: .emailAddress,
                            autocapitalization: .never
                        ) { focused = .password }
                        .focused($focused, equals: .email)

                        KkbTextField(
                            label: "Password",
                            placeholder: "At least 6 characters",
                            text: $password,
                            isSecure: true,
                            textContentType: mode == .signIn ? .password : .newPassword,
                            autocapitalization: .never,
                            submitLabel: .go
                        ) { submit() }
                        .focused($focused, equals: .password)

                        if let errorMessage {
                            Text(errorMessage)
                                .kkbFont(.bodySmall)
                                .foregroundStyle(Kkb.terracotta600)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        KkbPrimaryButton(
                            title: mode == .signIn ? "Sign in" : "Create account",
                            isLoading: isSubmitting,
                            isEnabled: canSubmit,
                            action: submit
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.2), value: mode)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Kkb.ink700)
                    .padding(10)
                    .background(Circle().fill(Kkb.cream100))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .accessibilityLabel("Back")
        }
        .onAppear { env.analytics.trackScreen("/signin", title: "Sign in") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAN, COOK, EAT")
                .kkbFont(.sectionLabel)
                .tracking(5)
                .foregroundStyle(Kkb.accentText)

            Text("khana kya banau")
                .kkbFont(.displayHero)
                .foregroundStyle(Kkb.textPrimary)
                .editorialHighlight()
                .fixedSize(horizontal: false, vertical: true)

            Text("Weekly meal planning, simplified.")
                .kkbFont(.bodyLarge)
                .foregroundStyle(Kkb.textSecondary)
        }
        .padding(.top, 44)
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        focused = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                if mode == .signIn {
                    _ = try await env.auth.login(email: email, password: password)
                    env.analytics.track(
                        AnalyticsEvents.Auth.login, category: AnalyticsEvents.Category.auth
                    )
                } else {
                    _ = try await env.auth.register(
                        email: email, password: password, name: name
                    )
                    env.analytics.track(
                        AnalyticsEvents.Auth.register, category: AnalyticsEvents.Category.auth
                    )
                }
                try await session.signedIn()
            } catch let error as APIError {
                errorMessage = error.userMessage(
                    fallback: mode == .signIn
                        ? "Could not sign you in. Please try again."
                        : "Could not create your account. Please try again."
                )
                env.analytics.trackError(
                    mode == .signIn ? "auth_login_error" : "auth_register_error",
                    message: errorMessage ?? ""
                )
            } catch {
                errorMessage = "Something went wrong. Please try again."
            }
            isSubmitting = false
        }
    }
}
