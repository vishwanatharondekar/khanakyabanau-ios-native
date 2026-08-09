import KhanaKit
import SwiftUI

/// "Today's Menu" — one card per enabled course, then a look ahead at tomorrow
/// with whatever has to be started tonight.
struct TodayView: View {
    @Environment(\.app) private var env

    /// Shared with Tomorrow and Meal Detail, and owned by `HomeView`, so moving
    /// between them never refetches.
    let model: TodayViewModel
    var onOpenTomorrow: () -> Void
    var onOpenMeal: (DayOfWeek, MealType) -> Void
    var onOpenVideo: (RecipeVideoContext) -> Void

    var body: some View {
        content(model)
            .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private func content(_ model: TodayViewModel) -> some View {
        @Bindable var model = model

        if model.isLoading {
            ProgressView()
                .tint(Kkb.terracotta500)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error = model.errorMessage {
                        InlineErrorCard(message: error) {
                            Task { await model.refresh(showSpinner: true) }
                        }
                    }

                    header(model)

                    ForEach(model.enabledTypes) { type in
                        TodayMealCard(
                            type: type,
                            meal: model.today.meals[type],
                            showCalories: model.showCalories,
                            isResolvingImages: model.isResolvingImages,
                            hasSavedVideo: env.videos.hasSavedPick(for: model.today.meals[type].name),
                            onTap: {
                                guard !model.today.meals[type].isEmpty else { return }
                                onOpenMeal(model.today.day, type)
                            }
                        )
                    }

                    TomorrowCard(
                        section: model.tomorrow,
                        enabledTypes: model.enabledTypes,
                        prepItems: model.tomorrowPrep,
                        isResolvingImages: model.isResolvingImages,
                        onOpen: onOpenTomorrow,
                        onOpenMeal: { onOpenMeal(model.tomorrow.day, $0) }
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.pullToRefresh() }
            .kkbToast($model.toast)
        }
    }

    private func header(_ model: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                LinearGradient(
                    colors: [Kkb.terracotta500, Kkb.marigold500],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 5, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                Text("On today's card")
                    .kkbFont(.displayMedium)
                    .italic()
                    .foregroundStyle(Kkb.textPrimary)
                Spacer()
            }
            Divider().overlay(Kkb.hairline)
            Text("\(model.today.day.displayName.uppercased()) · \(model.today.date.isoString)")
                .kkbFont(.sectionLabel)
                .tracking(4)
                .foregroundStyle(Kkb.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One course on today's card.
struct TodayMealCard: View {
    var type: MealType
    var meal: Meal
    var showCalories: Bool
    var isResolvingImages: Bool
    var hasSavedVideo: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: type.barColors, startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 5)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(type.emoji).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("COURSE")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(4)
                                .foregroundStyle(Kkb.textSecondary)
                            Text(type.displayName)
                                .kkbFont(.displayMedium)
                                .foregroundStyle(type.chipText)
                        }
                        Spacer()
                        if hasSavedVideo {
                            Text("🎥 RECIPE VIDEO")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Kkb.sageText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Kkb.sageSurface))
                                .rotationEffect(.degrees(-4))
                        }
                    }

                    if meal.isEmpty {
                        KkbEmptyState(
                            script: "— unwritten —",
                            caption: "No dish planned",
                            alignment: .leading
                        )
                        .padding(.vertical, 6)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            MealThumbnail(
                                imageUrl: meal.imageUrl,
                                size: 92,
                                cornerRadius: 18,
                                isResolving: isResolvingImages && meal.imageUrl == nil,
                                emoji: type.emoji
                            )
                            VStack(alignment: .leading, spacing: 8) {
                                Text(meal.name)
                                    .kkbFont(.displaySmall)
                                    .foregroundStyle(Kkb.textPrimary)
                                    .multilineTextAlignment(.leading)
                                if showCalories, let calories = meal.calories {
                                    CalorieBadge(calories: calories)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(meal.isEmpty ? Kkb.surfaceSunken.opacity(0.6) : Kkb.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Kkb.hairline, lineWidth: 1)
            )
            .shadow(
                color: Kkb.ink800.opacity(meal.isEmpty ? 0 : 0.10),
                radius: 8, x: 0, y: 3
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(meal.isEmpty)
        .accessibilityLabel(
            meal.isEmpty
                ? "\(type.displayName), no dish planned"
                : "\(type.displayName), \(meal.name)"
        )
    }
}
