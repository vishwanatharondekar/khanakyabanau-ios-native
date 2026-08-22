import KhanaKit
import SwiftUI

/// The signed-out landing screen. "Get Started" creates an anonymous guest account
/// straight away — no sign-up wall, which is the product's core promise.
struct WelcomeView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    var onSignIn: () -> Void
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                AppMarkIcon(size: 80)

                VStack(spacing: 8) {
                    Text("Khana Kya Banau")
                        .kkbFont(.displayLarge)
                        .foregroundStyle(Kkb.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Your Personal Meal Planning Assistant")
                        .kkbFont(.bodyLarge)
                        .foregroundStyle(Kkb.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let error = session.errorMessage {
                    Text(error)
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.terracotta600)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 16) {
                KkbPrimaryButton(title: "Get Started  →", isLoading: isStarting) {
                    Task {
                        isStarting = true
                        await session.startAsGuest()
                        isStarting = false
                    }
                }

                HStack(spacing: 4) {
                    Text("Already a member?")
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.textSecondary)
                    Button("Sign In", action: onSignIn)
                        .kkbFont(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(Kkb.accentText)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: session.errorMessage)
        .onAppear { env.analytics.trackScreen("/welcome", title: "Welcome") }
    }
}
