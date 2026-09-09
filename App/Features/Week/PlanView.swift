import KhanaKit
import SwiftUI

/// The Plan destination: one week header, and whichever view of the week is
/// selected below it.
///
/// The header lives here rather than in either pane because Meals and Shopping
/// are siblings under one week. Whichever of them owned the selector, the other
/// would either duplicate it or go without — which is exactly how Shopping
/// first shipped on the webapp with no week selector at all.
struct PlanView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    /// Owned by `HomeView` so it survives tab switches, matching Android's
    /// Activity-scoped view models.
    let model: WeekViewModel
    var onOpenVideo: (RecipeVideoContext) -> Void
    var onRequestAccount: () -> Void

    /// Unlike Android, the ceiling is known before anything is spent — so a
    /// guest at their limit is told rather than shown a 403.
    private var isGuestAtLimit: Bool {
        session.isGuest && (session.user?.remainingShoppingLists ?? 1) <= 0
    }

    private let brand = Brand.current

    /// Share the week as a PDF. Lives here rather than in the Meals pane because
    /// the header owns the action, and Shopping shares the same header.
    private func onShare() async {
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

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                WeekPicker(
                    chips: model.chips,
                    currentWeekStartDate: model.weekStartDate,
                    offRails: isOffRails(model.weekStartDate, in: model.chips),
                    onSelect: { week in Task { await model.selectWeek(week) } }
                )
                Spacer()
                WeekActions(
                    brand: brand,
                    generateLabel: primaryGenerateLabel(brand, hasEmptySlots: model.hasEmptySlots),
                    canGenerate: canGenerate(brand, for: session.user),
                    canImport: canImportPlan(brand, for: session.user),
                    canEdit: canEditPlan(brand),
                    onGenerate: {
                        env.analytics.track(
                            AnalyticsEvents.Mood.open,
                            category: AnalyticsEvents.Category.mood
                        )
                        model.isAIPromptOpen = true
                    },
                    // iOS has no PDF import screen yet, so canImport is false and
                    // this never runs. The seam is what will surface it.
                    onImport: {},
                    onShare: { Task { await onShare() } },
                    onClear: { model.isClearConfirmOpen = true },
                    onBrowseEarlier: model.earlierWeek == nil
                        ? nil
                        : { Task { await model.browseEarlier() } },
                    onOverflowOpened: model.trackOverflowOpen
                )
            }
            .padding(.horizontal, 16)

            WeekSubTabs(active: model.pane, onSelect: model.selectPane)
                .padding(.horizontal, 12)

            if model.viewingPastWeek {
                PastWeekBar(
                    weekStartDate: model.weekStartDate,
                    hasEarlierWeek: model.earlierWeek != nil,
                    onEarlier: { Task { await model.browseEarlier() } },
                    onThisWeek: { Task { await model.backToThisWeek() } }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            switch model.pane {
            case .meals:
                WeekView(
                    model: model,
                    onOpenVideo: onOpenVideo,
                    onRequestAccount: onRequestAccount,
                    onGenerate: {
                        env.analytics.track(
                            AnalyticsEvents.Mood.open,
                            category: AnalyticsEvents.Category.mood
                        )
                        model.isAIPromptOpen = true
                    }
                )
            case .shopping:
                ShoppingPane(
                    state: model.shoppingState,
                    session: model.shoppingSession,
                    onRetry: { Task { await model.retryShopping() } },
                    onCreateAccount: onRequestAccount,
                    onPlanWeek: { model.selectPane(.meals) }
                )
                // Opening the tab is the request. The probe inside is free, so
                // this cannot charge a guest for walking past.
                .task(id: model.weekStartDate) {
                    await model.openShopping(isGuestAtLimit: isGuestAtLimit)
                }
            }
        }
    }
}
