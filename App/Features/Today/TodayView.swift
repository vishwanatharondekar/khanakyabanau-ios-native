import KhanaKit
import SwiftUI

/// "Today's Menu" — one card per enabled course, then a look ahead at tomorrow
/// with whatever has to be started tonight.
struct TodayView: View {
    /// Shared with Tomorrow and Meal Detail, and owned by `HomeView`, so moving
    /// between them never refetches.
    let model: TodayViewModel
    var onOpenTomorrow: () -> Void
    var onOpenMeal: (DayOfWeek, MealType) -> Void
    var onOpenVideo: (RecipeVideoContext) -> Void
    var userName: String?
    var onPlanWeek: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    /// Re-read when the screen comes back rather than on a ticker. A phone put
    /// down before lunch and picked up after it is the case that matters; a
    /// screen watched across the boundary is not worth a running timer.
    @State private var now = Date()
    @State private var isEarlierExpanded = false

    var body: some View {
        content(model)
            .task { await model.loadIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
    }

    @ViewBuilder
    private func mealCard(
        _ model: TodayViewModel,
        _ type: MealType,
        isUpNext: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isUpNext {
                Text("UP NEXT")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)
                    .padding(.leading, 4)
            }
            TodayMealCard(
                type: type,
                meal: model.today.meals[type],
                showCalories: model.showCalories,
                isResolvingImages: model.isResolvingImages,
                onTap: {
                    guard !model.today.meals[type].isEmpty else { return }
                    onOpenMeal(model.today.day, type)
                }
            )
        }
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

                    GreetingHeader(name: userName)

                    // An empty Today is a designed state, not something to route
                    // around — the app opens here either way.
                    if model.enabledTypes.allSatisfy({ model.today.meals[$0].isEmpty }) {
                        EmptyToday(onPlanWeek: onPlanWeek)
                    } else {
                        let agenda = todayAgenda(enabledTypes: model.enabledTypes, at: now)

                        // Meals whose hour has gone: one line, not five cards.
                        // They still open — "what did I plan for breakfast?" is
                        // fair at ten in the morning — they just stop being the
                        // first thing the screen offers.
                        if !agenda.earlier.isEmpty {
                            EarlierTodayToggle(
                                count: agenda.earlier.count,
                                isExpanded: $isEarlierExpanded
                            )
                            if isEarlierExpanded {
                                ForEach(agenda.earlier) { type in
                                    mealCard(model, type, isUpNext: false)
                                }
                            }
                        }

                        ForEach(agenda.upcoming) { type in
                            mealCard(model, type, isUpNext: type == agenda.upNext)
                        }
                    }

                    if !model.afternoonPrep.isEmpty {
                        PrepTonightBox(
                            items: model.afternoonPrep,
                            isCompact: true,
                            heading: "PREP THIS AFTERNOON",
                            timePhrase: "this afternoon"
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
}

/// One course on today's card.
struct TodayMealCard: View {
    var type: MealType
    var meal: Meal
    var showCalories: Bool
    var isResolvingImages: Bool
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

/// One line standing in for the meals whose hour has passed.
///
/// The same answer the week grid gives for days already gone: demoted, still
/// reachable, and no longer asking to be the first thing you read.
private struct EarlierTodayToggle: View {
    var count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                Text(count == 1 ? "1 earlier today" : "\(count) earlier today")
                    .kkbFont(.bodyMedium)
                Spacer()
            }
            .foregroundStyle(Kkb.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
