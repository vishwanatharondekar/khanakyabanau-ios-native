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
                // Meals only. Every action here acts on the week's dishes —
                // Share exports the meal plan, and the overflow fills,
                // regenerates or clears it. None of them mean anything while a
                // shopping list is on screen, and the list has its own share,
                // copy and PDF actions in its footer.
                if model.pane == .meals {
                    WeekActions(
                        brand: brand,
                        generateLabel: primaryGenerateLabel(
                            brand, hasEmptySlots: model.hasEmptySlots
                        ),
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
                        // Never runs while Brand.capabilities.pdfImport is
                        // false, which is how the entry stays out of the menu.
                        // Building the import screen means flipping that
                        // boolean and filling this in — no other file changes.
                        onImport: {},
                        onShare: { Task { await onShare() } },
                        onClear: { model.isClearConfirmOpen = true },
                        onBrowseEarlier: model.earlierWeek == nil
                            ? nil
                            : { Task { await model.browseEarlier() } },
                        onOverflowOpened: model.trackOverflowOpen
                    )
                }
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
        // Both alerts hang off PlanView rather than the Meals pane. Their
        // triggers are Meals-only again now that the toolbar is, but PlanView
        // is mounted for both panes and the pane is not — keeping them here is
        // what stops an alert being raised against a view that isn't on screen,
        // which is how Clear silently did nothing from the Shopping tab once
        // before.
        //
        // Clear asks exactly once: the overflow entry opens this and does not
        // confirm inline as well.
        .alert("Clear all meals", isPresented: clearConfirmBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await model.clearWeek() } }
        } message: {
            Text("Are you sure you want to clear all meals for this week? This action cannot be undone.")
        }
        .alert("Register to Continue", isPresented: guestLimitBinding) {
            Button("Create free account") {
                model.guestLimitPrompt = nil
                onRequestAccount()
            }
            Button("Not now", role: .cancel) { model.guestLimitPrompt = nil }
        } message: {
            Text(model.guestLimitPrompt ?? "")
        }
    }

    private var clearConfirmBinding: Binding<Bool> {
        Binding(
            get: { model.isClearConfirmOpen },
            set: { model.isClearConfirmOpen = $0 }
        )
    }

    private var guestLimitBinding: Binding<Bool> {
        Binding(
            get: { model.guestLimitPrompt != nil },
            set: { if !$0 { model.guestLimitPrompt = nil } }
        )
    }
}
