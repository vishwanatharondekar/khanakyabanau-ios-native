import KhanaKit
import SwiftUI

/// The Meals pane of a week: seven day cards, each with a row per enabled
/// course. The week selector, the view tabs and the actions live above it in
/// `PlanView`, shared with Shopping.
struct WeekView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    /// Owned by `HomeView` so it survives tab switches, matching Android's
    /// Activity-scoped view models.
    let model: WeekViewModel
    var onOpenVideo: (RecipeVideoContext) -> Void
    /// Hitting a guest allowance should lead somewhere, so the limit prompt can
    /// open the same account-creation sheet the drawer offers.
    var onRequestAccount: () -> Void
    /// Promoted into the grid only on an empty week; otherwise it lives in the
    /// header's overflow.
    var onGenerate: () -> Void = {}

    var body: some View {
        content(model)
            .task {
                if model.cuisinePreferences.isEmpty {
                    model.cuisinePreferences = session.user?.cuisinePreferences ?? []
                }
                await model.load()
            }
    }

    /// Opens the recipe-video sheet for a slot.
    ///
    /// Two affordances land here — tapping the meal card itself, and the row's
    /// play button — so `trigger` records which one, since the funnel cannot tell
    /// them apart from `source` alone.
    private func openVideo(day: DayOfWeek, type: MealType, trigger: String) {
        let meal = model.plan[day, type]
        env.analytics.track(
            AnalyticsEvents.Video.openModal,
            category: AnalyticsEvents.Category.videoManagement,
            parameters: [
                AnalyticsProperties.mealName: meal.name,
                AnalyticsProperties.source: "week",
                AnalyticsProperties.trigger: trigger,
            ]
        )
        onOpenVideo(RecipeVideoContext(
            day: day,
            mealType: type,
            mealName: meal.name,
            weekStartDate: model.weekStartDate,
            slotVideoUrl: meal.videoUrl,
            source: "week"
        ))
    }

    @ViewBuilder
    private func content(_ model: WeekViewModel) -> some View {
        @Bindable var model = model

        ZStack {
            if model.isLoading {
                ProgressView()
                    .tint(Kkb.terracotta500)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if model.isEmptyWeek {
                            WeekHero(
                                brand: Brand.current,
                                generateLabel: primaryGenerateLabel(
                                    Brand.current, hasEmptySlots: model.hasEmptySlots
                                ),
                                onGenerate: onGenerate
                            )
                        }

                        if let error = model.errorMessage {
                            InlineErrorCard(message: error) {
                                Task { await model.pullToRefresh() }
                            }
                        }

                        ForEach(Array(WeekDates.daysOfWeek(
                            from: PlanDate(iso: model.weekStartDate) ?? WeekDates.currentMonday()
                        ).enumerated()), id: \.element.day) { index, entry in
                            WeekDaySection(
                                day: entry.day,
                                date: entry.date,
                                meals: model.plan.meals(for: entry.day),
                                enabledTypes: model.enabledTypes,
                                isToday: model.todayIndex == index,
                                isTomorrow: model.tomorrowIndex == index,
                                isResolvingImages: model.isResolvingImages,
                                videoURL: { env.videos.url(for: $0) },
                                onTapRow: { type in
                                    // An empty row has no dish to watch, so it
                                    // keeps opening suggestions — the same thing
                                    // its own `+` button does.
                                    if model.plan[entry.day, type].isEmpty {
                                        model.suggesting = SlotTarget(day: entry.day, type: type)
                                    } else {
                                        openVideo(day: entry.day, type: type, trigger: "meal_card")
                                    }
                                },
                                onEdit: { model.editing = SlotTarget(day: entry.day, type: $0) },
                                onSwap: { model.suggesting = SlotTarget(day: entry.day, type: $0) },
                                onVideo: { type in
                                    openVideo(day: entry.day, type: type,
                                              trigger: "video_button")
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.pullToRefresh() }
            }

            // Shopping is not here any more: it renders its own loader inside
            // its pane, because building a list must not block navigation.
            if model.isGenerating {
                FullScreenLoader(message: "Cooking up suggestions")
            }
        }
        .sheet(item: $model.editing) { target in
            EditMealSheet(
                target: target,
                meal: model.plan[target.day, target.type],
                onSave: { name in
                    Task { await model.confirmEdit(target: target, name: name) }
                    model.editing = nil
                },
                onCancel: { model.editing = nil }
            )
        }
        .sheet(item: $model.suggesting) { target in
            MealSuggestionSheet(
                target: target,
                currentName: model.plan[target.day, target.type].name,
                initialSuggestions: model.initialSuggestions(for: target),
                onRefresh: { current in await model.freshSuggestions(for: target, current: current) },
                onPick: { name, imageUrl in
                    Task { await model.applySuggestion(target: target, name: name, imageUrl: imageUrl) }
                    model.suggesting = nil
                },
                onCancel: { model.suggesting = nil }
            )
        }
        .sheet(isPresented: $model.isAIPromptOpen) {
            AIPromptSheet(
                onGenerate: { ingredients, moods, restrictToIngredients in
                    Task {
                        await model.generateWithAI(
                            ingredients: ingredients,
                            moodCuisines: moods,
                            restrictToIngredients: restrictToIngredients
                        )
                    }
                },
                onCancel: { model.isAIPromptOpen = false }
            )
        }
        .alert("Clear all meals", isPresented: $model.isClearConfirmOpen) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await model.clearWeek() } }
        } message: {
            Text("Are you sure you want to clear all meals for this week? This action cannot be undone.")
        }
        .alert(
            "Register to Continue",
            isPresented: Binding(
                get: { model.guestLimitPrompt != nil },
                set: { if !$0 { model.guestLimitPrompt = nil } }
            )
        ) {
            Button("Create free account") {
                model.guestLimitPrompt = nil
                onRequestAccount()
            }
            Button("Not now", role: .cancel) { model.guestLimitPrompt = nil }
        } message: {
            Text(model.guestLimitPrompt ?? "")
        }
        .kkbToast($model.toast)
    }
}
