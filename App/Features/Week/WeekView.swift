import KhanaKit
import SwiftUI

/// "The Week" — the planner grid. Seven day cards, each with a row per enabled
/// course, above a row of four actions.
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
                    LazyVStack(spacing: 12) {
                        WeekHeader(
                            label: model.weekRangeLabel,
                            onPrevious: { Task { await model.goToPreviousWeek() } },
                            onNext: { Task { await model.goToNextWeek() } }
                        )

                        actionRow(model)

                        if let error = model.errorMessage {
                            InlineErrorCard(message: error) {
                                Task { await model.pullToRefresh() }
                            }
                        }

                        ForEach(Array(WeekDates.daysOfWeek(
                            from: PlanDate(iso: model.weekStartDate) ?? WeekDates.currentMonday()
                        ).enumerated()), id: \.element.day) { index, entry in
                            DayCard(
                                day: entry.day,
                                date: entry.date,
                                meals: model.plan.meals(for: entry.day),
                                enabledTypes: model.enabledTypes,
                                isToday: model.todayIndex == index,
                                isTomorrow: model.tomorrowIndex == index,
                                isResolvingImages: model.isResolvingImages,
                                showCalories: model.showCalories,
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.pullToRefresh() }
            }

            if model.isGenerating {
                FullScreenLoader(message: "Cooking up suggestions")
            } else if model.isBuildingShoppingList {
                FullScreenLoader(message: "Building shopping list")
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
                onGenerate: { ingredients, moods in
                    Task { await model.generateWithAI(ingredients: ingredients, moodCuisines: moods) }
                },
                onCancel: { model.isAIPromptOpen = false }
            )
        }
        .sheet(item: $model.shoppingSession) { session in
            ShoppingListSheet(
                list: session.list,
                weekStartDate: session.weekStartDate,
                onDismiss: { model.shoppingSession = nil }
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

    private func actionRow(_ model: WeekViewModel) -> some View {
        HStack(spacing: 10) {
            ActionPill(
                variant: .ai,
                systemImage: "sparkles",
                title: "AI"
            ) {
                env.analytics.track(
                    AnalyticsEvents.Mood.open, category: AnalyticsEvents.Category.mood
                )
                model.isAIPromptOpen = true
            }
            ActionPill(variant: .pdf, systemImage: "doc.richtext", title: "PDF") {
                Task { await exportPDF(model) }
            }
            ActionPill(
                variant: .shopping,
                systemImage: "cart",
                title: "Shopping"
            ) {
                Task { await model.buildShoppingList() }
            }
            ActionPill(variant: .clear, systemImage: "trash", title: "Clear") {
                model.isClearConfirmOpen = true
            }
        }
    }

    private func exportPDF(_ model: WeekViewModel) async {
        env.analytics.track(
            AnalyticsEvents.PDF.generateMealPlan,
            category: AnalyticsEvents.Category.pdf,
            parameters: [AnalyticsProperties.weekStart: model.weekStartDate]
        )
        let language = env.settings.language.language
        let translations = await env.translations.translations(
            for: language, texts: model.plan.allDishNames()
        )
        guard let url = MealPlanPDF.render(
            plan: model.plan,
            enabledTypes: model.enabledTypes,
            weekRangeLabel: model.weekRangeLabel,
            translations: translations,
            language: language,
            videoURL: { env.videos.url(for: $0) }
        ) else {
            model.errorMessage = "Failed to generate PDF"
            return
        }
        env.analytics.track(
            AnalyticsEvents.PDF.downloadMealPlan, category: AnalyticsEvents.Category.pdf
        )
        SharePresenter.present(items: [url])
    }
}

/// ← week range → header.
private struct WeekHeader: View {
    var label: String
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        PaperCard(cornerRadius: 28, padding: 16) {
            HStack(spacing: 12) {
                navButton(systemImage: "chevron.left", label: "Previous week", action: onPrevious)
                VStack(spacing: 3) {
                    Text("THE WEEK OF")
                        .kkbFont(.sectionLabel)
                        .tracking(4)
                        .foregroundStyle(Kkb.accentText)
                    Text(label)
                        .kkbFont(.displayMedium)
                        .foregroundStyle(Kkb.textPrimary)
                        .editorialHighlight()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                navButton(systemImage: "chevron.right", label: "Next week", action: onNext)
            }
        }
    }

    private func navButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Kkb.ink700)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Kkb.cream100))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
