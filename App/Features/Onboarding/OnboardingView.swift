import KhanaKit
import SwiftUI

/// Three steps: welcome, cuisines, dietary style. Preferences are written to the
/// server at the end, and completing the last step flips `onboardingCompleted`,
/// which is what moves the root switch to Home.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, cuisine, dietary

        var confirmTitle: String {
            switch self {
            case .welcome: "Get started"
            case .cuisine: "Next: dietary"
            case .dietary: "Complete setup"
            }
        }
    }

    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    let user: User

    @State private var step = Step.welcome
    @State private var cuisines: Set<String> = []
    @State private var dietary = DietaryPreferences()
    @State private var isSaving = false
    @State private var savingMessage: String?
    @State private var errorMessage: String?
    @State private var infoCuisine: String?

    private var canAdvance: Bool {
        switch step {
        case .welcome: true
        case .cuisine: !cuisines.isEmpty
        case .dietary: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .welcome: welcomeStep
                    case .cuisine: cuisineStep
                    case .dietary: dietaryStep
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .animation(.snappy(duration: 0.25), value: step)
        .onAppear {
            cuisines = Set(user.cuisinePreferences)
            if let existing = user.dietaryPreferences { dietary = existing }
            env.analytics.track(
                AnalyticsEvents.Onboarding.start, category: AnalyticsEvents.Category.onboarding
            )
        }
        .alert(
            infoCuisine ?? "",
            isPresented: Binding(get: { infoCuisine != nil }, set: { if !$0 { infoCuisine = nil } })
        ) {
            Button("Got it", role: .cancel) { infoCuisine = nil }
        } message: {
            if let infoCuisine {
                let samples = CuisineData.sampleDishes(for: infoCuisine)
                Text("Sample dishes\n\n" + samples.joined(separator: " · ") + "\n…and more")
            }
        }
    }

    // MARK: - Steps

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if step != .welcome {
                    Button {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                        errorMessage = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Kkb.ink700)
                            .padding(8)
                            .background(Circle().fill(Kkb.cream100))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Text("STEP \(step.rawValue + 1) OF 3")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { candidate in
                    Capsule()
                        .fill(candidate.rawValue <= step.rawValue
                              ? Kkb.terracotta500 : Kkb.cream300)
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of 3")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WELCOME, \(user.name.uppercased())")
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.accentText)
            Text("Let's set up your kitchen")
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("""
            A couple of quick questions and we'll have a whole week of breakfasts, \
            lunches and dinners ready — tuned to the food you actually cook.
            """)
            .kkbFont(.bodyLarge)
            .foregroundStyle(Kkb.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cuisineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PICK YOUR CUISINES")
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.accentText)
            Text("Which cuisines do you cook?")
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick your favourites to get personalised meal suggestions.")
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)

            FlowLayout(spacing: 10) {
                ForEach(CuisineData.cuisines) { cuisine in
                    HStack(spacing: 6) {
                        KkbChip(
                            title: cuisine.name,
                            isSelected: cuisines.contains(cuisine.name)
                        ) {
                            if cuisines.contains(cuisine.name) {
                                cuisines.remove(cuisine.name)
                            } else {
                                cuisines.insert(cuisine.name)
                            }
                        }
                        Button {
                            infoCuisine = cuisine.name
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Kkb.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sample dishes for \(cuisine.name)")
                    }
                }
            }
        }
    }

    private var dietaryStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT YOU EAT")
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.accentText)
            Text("Your dietary style")
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
            DietaryControls(preferences: $dietary)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let savingMessage {
                Text(savingMessage)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.sageText)
            }
            if let errorMessage {
                Text(errorMessage)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.terracotta600)
                    .multilineTextAlignment(.center)
            }
            KkbPrimaryButton(
                title: step.confirmTitle,
                isLoading: isSaving,
                isEnabled: canAdvance,
                action: advance
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func advance() {
        errorMessage = nil
        switch step {
        case .welcome:
            step = .cuisine
        case .cuisine:
            step = .dietary
        case .dietary:
            finish()
        }
    }

    private func finish() {
        guard !isSaving else { return }
        isSaving = true
        savingMessage = "Saving your preferences…"

        Task {
            do {
                // Cuisines carry the onboardingCompleted flag, matching what the
                // web client sends at the end of its own two-step flow.
                try await env.settings.saveCuisines(
                    Array(cuisines).sorted(), onboardingCompleted: true
                )
                try await env.settings.saveDietary(dietary)

                // Phase 2 — the first week, generated from the preferences just
                // saved. Best effort and silent: `onboardingCompleted` is already
                // true server-side, so a failure here must not hold the user on
                // this screen. They land on an empty week and the Week tab's AI
                // button, which does report errors and guest limits.
                // Android sequences it the same way (`OnboardingViewModel.complete`).
                savingMessage = "Cooking up your first week…"
                if let seeded = await env.firstWeek.seedCurrentWeek() {
                    // Detached on purpose: prep is a second slow AI call, and
                    // waiting on it would hold the user here with nothing new to
                    // look at. Unstructured, so completing onboarding below cannot
                    // cancel it.
                    Task { await env.firstWeek.fillPrep(weekStartDate: seeded) }
                }

                env.analytics.track(
                    AnalyticsEvents.Onboarding.complete,
                    category: AnalyticsEvents.Category.onboarding,
                    parameters: [
                        AnalyticsProperties.cuisineCount: cuisines.count,
                        "dietary_preference": dietary.analyticsValue,
                    ]
                )
                savingMessage = nil
                session.completeOnboarding()
            } catch let error as APIError {
                errorMessage = error.userMessage(
                    fallback: "Failed to save preferences. Please try again."
                )
                savingMessage = nil
            } catch {
                errorMessage = "Failed to save preferences. Please try again."
                savingMessage = nil
            }
            isSaving = false
        }
    }
}
