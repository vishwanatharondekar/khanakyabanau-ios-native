import Foundation
import KhanaKit
import SwiftUI
import UIKit

/// Scoping, pruning and export for the generated shopping list.
///
/// The server returns one full-week list; everything the user does here — narrowing
/// to a few days, ticking off what they already have — is recomposed on device by
/// `ShoppingScope`, so no interaction costs another AI call.
@MainActor
@Observable
final class ShoppingListViewModel {
    private(set) var list: ShoppingList
    let weekStartDate: String

    var selectedDays: Set<DayOfWeek>
    private(set) var haveAlready: Set<String>

    var errorMessage: String?
    var toast: String?
    private(set) var isExportingPDF = false

    private let env: AppEnvironment
    /// Matches the web client's 600 ms debounce; the list is ticked in bursts.
    private var persistTask: Task<Void, Never>?
    /// Closing the sheet should not PATCH a list nobody touched.
    private var hasUnsavedChanges = false

    init(env: AppEnvironment, list: ShoppingList, weekStartDate: String) {
        self.env = env
        self.list = list
        self.weekStartDate = weekStartDate
        // A legacy list without `dayWise` cannot be scoped, so it starts whole.
        self.selectedDays = list.dayWise.isEmpty
            ? Set(DayOfWeek.allCases)
            : Set(ShoppingScope.computeDefaultScopeDays(weekStartDate: weekStartDate))
        self.haveAlready = Set(list.haveAlready.map(ShoppingScope.normalizeIngredientName))
    }

    /// Legacy cached documents have no per-day breakdown; the day chips are hidden
    /// for those and the full-week list is shown as-is.
    var hasDayWise: Bool { !list.dayWise.isEmpty }

    var scoped: ScopedShoppingList {
        ShoppingScope.aggregateScopedList(
            dayWise: list.dayWise,
            selectedDays: selectedDays,
            categorized: list.categorized
        )
    }

    /// Legacy cached lists have no per-day breakdown, so they are always the whole
    /// week — labelling one "Aug 3 – Aug 5" would be a lie, since narrowing does
    /// nothing for them.
    var scopeLabel: String {
        guard hasDayWise else { return "" }
        return ShoppingScope.formatScopeLabel(
            weekStartDate: weekStartDate, selectedDays: selectedDays
        )
    }

    /// Nothing left to buy means nothing worth exporting.
    var canExport: Bool { toBuyCount > 0 }

    var ingredientMeals: [String: [String]] {
        ShoppingScope.buildIngredientMealMap(
            dayWise: list.dayWise, selectedDays: hasDayWise ? selectedDays : nil
        )
    }

    var newItems: Set<String> {
        Set(list.newItems.map(ShoppingScope.normalizeIngredientName))
    }

    var toBuyCount: Int {
        scoped.categorized.reduce(0) { total, section in
            total + section.items.filter { !isHad($0.name) }.count
        }
    }

    var haveCount: Int {
        scoped.categorized.reduce(0) { total, section in
            total + section.items.filter { isHad($0.name) }.count
        }
    }

    func isHad(_ name: String) -> Bool {
        haveAlready.contains(ShoppingScope.normalizeIngredientName(name))
    }

    func isNew(_ name: String) -> Bool {
        newItems.contains(ShoppingScope.normalizeIngredientName(name))
    }

    func meals(for ingredient: String) -> [String] {
        ingredientMeals[ShoppingScope.normalizeIngredientName(ingredient)] ?? []
    }

    // MARK: - Interaction

    func toggleDay(_ day: DayOfWeek) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
        env.analytics.track(
            AnalyticsEvents.Shopping.scopeChange,
            category: AnalyticsEvents.Category.shopping,
            parameters: [
                AnalyticsProperties.weekStart: weekStartDate,
                AnalyticsProperties.dayCount: selectedDays.count,
            ]
        )
    }

    func selectAllDays() {
        selectedDays = Set(DayOfWeek.allCases)
        env.analytics.track(
            AnalyticsEvents.Shopping.scopeChange,
            category: AnalyticsEvents.Category.shopping,
            parameters: [AnalyticsProperties.dayCount: 7]
        )
    }

    func toggleHave(_ name: String) {
        let key = ShoppingScope.normalizeIngredientName(name)
        if haveAlready.contains(key) {
            haveAlready.remove(key)
        } else {
            haveAlready.insert(key)
        }
        env.analytics.track(
            AnalyticsEvents.Shopping.pruneToggle,
            category: AnalyticsEvents.Category.shopping,
            parameters: [AnalyticsProperties.prunedCount: haveAlready.count]
        )
        schedulePersist()
    }

    /// If every item in the category is already ticked, untick them all; otherwise
    /// tick them all.
    func toggleCategory(_ section: CategorySection) {
        let keys = section.items.map { ShoppingScope.normalizeIngredientName($0.name) }
        if keys.allSatisfy(haveAlready.contains) {
            keys.forEach { haveAlready.remove($0) }
        } else {
            keys.forEach { haveAlready.insert($0) }
        }
        schedulePersist()
    }

    /// Debounced so a run of taps produces one request, matching the web client.
    private func schedulePersist() {
        hasUnsavedChanges = true
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    /// Called when the sheet closes, so a pending debounce is never lost.
    func flushPending() async {
        persistTask?.cancel()
        persistTask = nil
        guard hasUnsavedChanges else { return }
        await persist()
    }

    private func persist() async {
        do {
            try await env.ai.updateHaveAlready(
                weekStartDate: weekStartDate, names: Array(haveAlready)
            )
            hasUnsavedChanges = false
        } catch {
            // Silent: the list is still correct on screen and will be retried on
            // the next toggle. Surfacing this would interrupt a rapid-fire task.
        }
    }

    // MARK: - Export

    func share() {
        let text = ShoppingScope.buildShareText(
            scoped: scoped, haveAlready: haveAlready, scopeLabel: scopeLabel
        )
        env.analytics.track(
            AnalyticsEvents.Shopping.listShare,
            category: AnalyticsEvents.Category.shopping,
            parameters: [
                AnalyticsProperties.weekStart: weekStartDate,
                AnalyticsProperties.itemCount: toBuyCount,
                AnalyticsProperties.dayCount: selectedDays.count,
            ]
        )
        SharePresenter.present(items: [text])
    }

    func copyToPasteboard() {
        let text = ShoppingScope.buildCopyText(scoped: scoped, haveAlready: haveAlready)
        UIPasteboard.general.string = text
        env.analytics.track(
            AnalyticsEvents.Shopping.listCopy,
            category: AnalyticsEvents.Category.shopping,
            parameters: [AnalyticsProperties.itemCount: toBuyCount]
        )
        toast = "Copied! Each line becomes its own entry in Reminders."
    }

    func exportPDF() async {
        isExportingPDF = true
        env.analytics.track(
            AnalyticsEvents.PDF.generateShoppingList,
            category: AnalyticsEvents.Category.pdf,
            parameters: [AnalyticsProperties.weekStart: weekStartDate]
        )

        let language = env.settings.language.language
        let names = scoped.categorized.flatMap { section in
            section.items.map(\.name) + [section.name]
        }
        let translations = await env.translations.translations(for: language, texts: names)

        if let url = ShoppingListPDF.render(
            scoped: scoped,
            haveAlready: haveAlready,
            scopeLabel: scopeLabel,
            translations: translations,
            language: language,
            ingredientMeals: ingredientMeals
        ) {
            env.analytics.track(
                AnalyticsEvents.PDF.downloadShoppingList,
                category: AnalyticsEvents.Category.pdf
            )
            SharePresenter.present(items: [url])
        } else {
            errorMessage = "Failed to generate PDF"
        }
        isExportingPDF = false
    }
}
