import KhanaKit
import SwiftUI
import UIKit

/// One dish, full screen: the photo, its recipe video, and what has to be prepped
/// in advance. Only today and tomorrow resolve here — no other day has a route to
/// this screen, matching Android.
struct MealDetailView: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    let model: TodayViewModel
    var day: DayOfWeek
    var mealType: MealType
    var onOpenVideo: (RecipeVideoContext) -> Void
    var onNavigate: (DayOfWeek, MealType) -> Void
    @State private var pastedURL = ""
    @State private var pasteError: String?
    @State private var isSavingPaste = false
    @State private var toast: String?

    var body: some View {
        Group {
            // Only today and tomorrow resolve here; nothing else has a route to
            // this screen. A brief spinner covers the first load.
            if let section = model.section(for: day) {
                content(model: model, section: section, meal: section.meals[mealType])
            } else {
                ProgressView().tint(Kkb.terracotta500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .kkbPageGround()
        .navigationBarBackButtonHidden()
        .kkbToast($toast)
        .task {
            await model.loadIfNeeded()
            await env.videos.ensureLoaded()
        }
    }

    @ViewBuilder
    private func content(model: TodayViewModel, section: DaySection, meal: Meal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero(section: section, meal: meal, showCalories: model.showCalories)

                if meal.isEmpty {
                    KkbEmptyState(
                        script: "Nothing planned here yet",
                        caption: "No \(mealType.displayName.lowercased()) written for this day."
                    )
                    .padding(.top, 40)
                    .padding(.horizontal, 20)
                } else {
                    recipeVideoSection(section: section, meal: meal)
                        .padding(.horizontal, 20)

                    prepPanel(meal: meal)
                        .padding(.horizontal, 20)
                }

                otherMealsNav(model: model, section: section)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero

    private func hero(section: DaySection, meal: Meal, showCalories: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageUrl = meal.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Kkb.creamWell
                    }
                } else {
                    LinearGradient(
                        colors: [Kkb.terracotta300, Kkb.marigold400],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .overlay(
                        Text(mealType.emoji)
                            .font(.system(size: 110))
                            .opacity(0.25)
                    )
                }
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [
                    Kkb.ink900.opacity(0.15),
                    Kkb.ink900.opacity(0.55),
                    Kkb.ink900.opacity(0.88),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("\(section.day.displayName.uppercased()) · \(section.date.isoString) · \(mealType.emoji) \(mealType.displayName.uppercased())")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(.white.opacity(0.85))

                Text(meal.isEmpty ? "Nothing planned" : meal.name)
                    .kkbFont(.displayLarge)
                    .italic()
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if showCalories, let calories = meal.calories {
                    Text("🔥 \(calories) kcal")
                        .kkbFont(.labelSmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }
            .padding(20)
        }
        .frame(height: 280)
        .clipped()
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Kkb.ink900)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 56)
            .accessibilityLabel("Back")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recipe video

    @ViewBuilder
    private func recipeVideoSection(section: DaySection, meal: Meal) -> some View {
        let savedURL = env.videos.hasSavedPick(for: meal.name)
            ? env.videos.url(for: meal) : nil
        let topPick = savedURL == nil ? meal.videoUrl : nil

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recipe video")
                    .kkbFont(.displayMedium)
                    .italic()
                    .foregroundStyle(Kkb.accentText)
                Spacer()
                Button("FIND ANOTHER") { openPicker(section: section, meal: meal) }
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Kkb.terracottaSurface))
            }
            Rectangle().fill(Kkb.terracotta200).frame(height: 2)

            if let savedURL {
                videoTag("YOUR SAVED RECIPE", tint: Kkb.sageText, fill: Kkb.sageSurface)
                videoCard(url: savedURL)
                Button {
                    env.analytics.track(
                        AnalyticsEvents.Video.play,
                        category: AnalyticsEvents.Category.videoManagement,
                        parameters: [
                            AnalyticsProperties.mealName: meal.name,
                            AnalyticsProperties.videoURL: savedURL,
                            AnalyticsProperties.source: "meal_detail",
                        ]
                    )
                    if let url = URL(string: savedURL) { UIApplication.shared.open(url) }
                } label: {
                    actionLabel("Watch on YouTube", systemImage: "play.fill")
                }
                .buttonStyle(.plain)
            } else if let topPick, !topPick.isEmpty {
                videoTag("TOP PICK", tint: Kkb.marigoldText, fill: Kkb.marigoldSurface)
                videoCard(url: topPick)
                Button { openPicker(section: section, meal: meal) } label: {
                    actionLabel("Preview & save", systemImage: "bookmark")
                }
                .buttonStyle(.plain)
            } else {
                KkbEmptyState(
                    script: "No video yet",
                    caption: "Search YouTube, or paste a link below.",
                    alignment: .leading
                )
                Button { openPicker(section: section, meal: meal) } label: {
                    actionLabel("Search recipe videos", systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
            }

            pasteRow(meal: meal)
        }
    }

    private func videoTag(_ text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .kkbFont(.sectionLabel)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
    }

    @ViewBuilder
    private func videoCard(url: String) -> some View {
        if let videoID = RecipeVideos.videoID(from: url),
           let thumbURL = URL(string: RecipeVideos.thumbnailURL(videoID: videoID)) {
            ZStack {
                AsyncImage(url: thumbURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Kkb.creamWell
                }
                Circle()
                    .fill(.black.opacity(0.55))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    )
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title).kkbFont(.labelLarge)
        }
        .foregroundStyle(Kkb.cream50)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Capsule().fill(Kkb.terracotta500))
    }

    private func pasteRow(meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or paste a link".eyebrow)
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.textSecondary)
            HStack(spacing: 10) {
                TextField("https://youtube.com/watch?v=…", text: $pastedURL)
                    .kkbFont(.bodyMedium)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Kkb.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Kkb.hairline, lineWidth: 1)
                    )
                Button {
                    Task { await savePasted(for: meal) }
                } label: {
                    if isSavingPaste {
                        ProgressView().controlSize(.small).tint(Kkb.cream50)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Kkb.terracotta500))
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Kkb.cream50)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Kkb.terracotta500))
                    }
                }
                .buttonStyle(.plain)
                .disabled(pastedURL.isEmpty || isSavingPaste)
                .accessibilityLabel("Save this link")
            }
            if let pasteError {
                Text(pasteError)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.terracotta600)
            }
        }
        .padding(.top, 4)
    }

    private func savePasted(for meal: Meal) async {
        let trimmed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RecipeVideos.isValidYouTubeURL(trimmed), RecipeVideos.videoID(from: trimmed) != nil
        else {
            pasteError = "Please paste a valid YouTube URL"
            return
        }
        pasteError = nil
        isSavingPaste = true
        do {
            try await env.videos.save(recipeName: meal.name, videoUrl: trimmed)
            env.analytics.track(
                AnalyticsEvents.Video.addURL,
                category: AnalyticsEvents.Category.videoManagement,
                parameters: [
                    AnalyticsProperties.mealName: meal.name,
                    AnalyticsProperties.source: "manual_url",
                ]
            )
            pastedURL = ""
            toast = "Recipe video saved!"
        } catch {
            pasteError = "Failed to save recipe video"
        }
        isSavingPaste = false
    }

    private func openPicker(section: DaySection, meal: Meal) {
        env.analytics.track(
            AnalyticsEvents.Video.openModal,
            category: AnalyticsEvents.Category.videoManagement,
            parameters: [
                AnalyticsProperties.mealName: meal.name,
                AnalyticsProperties.source: "meal_detail",
            ]
        )
        onOpenVideo(RecipeVideoContext(
            day: day,
            mealType: mealType,
            mealName: meal.name,
            weekStartDate: section.weekStartDate,
            slotVideoUrl: meal.videoUrl,
            source: "meal_detail"
        ))
    }

    // MARK: - Prep

    /// Three genuinely different states, and conflating them would mislead: no prep
    /// generated yet, generated and nothing needed, or generated with steps.
    @ViewBuilder
    private func prepPanel(meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preparation")
                    .kkbFont(.displayMedium)
                    .italic()
                    .foregroundStyle(Kkb.sageText)
                Spacer()
                if let prep = meal.validPrep, prep.activeMinutes > 0 {
                    Text("~\(prep.activeMinutes) MIN HANDS-ON")
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.textSecondary)
                }
            }
            Rectangle().fill(Kkb.sage300).frame(height: 2)

            if let prep = meal.validPrep {
                if prep.steps.isEmpty {
                    KkbEmptyState(
                        script: "Nothing to prep ahead",
                        caption: "This dish can be cooked start to finish.",
                        alignment: .leading
                    )
                } else {
                    if prep.maxLeadTimeMinutes >= 60 {
                        Text("Start \(formatLeadTime(prep.maxLeadTimeMinutes)) of when you plan to cook.")
                            .kkbFont(.bodyMedium)
                            .foregroundStyle(Kkb.marigoldText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Kkb.marigoldSurface.opacity(0.7))
                            )
                    }
                    MealPrepSection(prep: prep, showsHeading: false)
                }
            } else {
                KkbEmptyState(
                    script: "Prep not worked out yet",
                    caption: "Soaking, marinating and other advance steps will show up here.",
                    alignment: .leading
                )
            }
        }
    }

    // MARK: - Prev / next

    @ViewBuilder
    private func otherMealsNav(model: TodayViewModel, section: DaySection) -> some View {
        let types = model.enabledTypes
        if let index = types.firstIndex(of: mealType) {
            HStack(spacing: 12) {
                if index > 0 {
                    navTile(types[index - 1], section: section, isPrevious: true)
                }
                if index < types.count - 1 {
                    navTile(types[index + 1], section: section, isPrevious: false)
                }
            }
        }
    }

    private func navTile(
        _ type: MealType,
        section: DaySection,
        isPrevious: Bool
    ) -> some View {
        Button { onNavigate(day, type) } label: {
            HStack(spacing: 8) {
                if isPrevious {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                VStack(alignment: isPrevious ? .leading : .trailing, spacing: 1) {
                    Text(isPrevious ? "PREVIOUS" : "NEXT")
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.textSecondary)
                    Text("\(type.emoji) \(type.displayName)")
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.textPrimary)
                        .lineLimit(1)
                }
                if !isPrevious {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(Kkb.textSecondary)
            .frame(maxWidth: .infinity, alignment: isPrevious ? .leading : .trailing)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Kkb.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Kkb.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
