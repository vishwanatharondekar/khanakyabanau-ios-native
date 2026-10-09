import Foundation
import KhanaKit
import SwiftUI
import UIKit
import os

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
    /// Swiggy Instamart orders for this week, newest first. Seeded from the
    /// list and then owned here, beside `haveAlready`, which delivery feeds
    /// into: a placed order and a status sync both change it.
    private(set) var orders: [StoredOrder]

    var errorMessage: String?
    var toast: String?
    private(set) var isExportingPDF = false

    private let env: AppEnvironment
    /// Matches the web client's 600 ms debounce; the list is ticked in bursts.
    private var persistTask: Task<Void, Never>?
    /// Closing the sheet should not PATCH a list nobody touched.
    private var hasUnsavedChanges = false

    private let instamart: any InstamartGateway
    /// Re-reads the week's cached list (a free `cachedOnly` probe). Supplied
    /// by the week, which holds the plan the probe needs; nil disables
    /// `reloadShopping()`.
    private let reloadList: (() async -> ShoppingList?)?
    private let now: () -> Date
    /// The in-flight status sync, so a re-show cannot start a second one.
    private var orderSyncTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "in.khanakyabanau.app", category: "instamart")

    /// Hands `haveAlready` and `orders` back to the week after every change.
    ///
    /// This model lives as long as the pane is on screen, but the list it was
    /// seeded from lives on the week (`ShoppingSession`). Without the
    /// write-back, switching to Meals and back rebuilds the model from the
    /// list as first loaded — a just-placed order would vanish from the list
    /// until the next probe. Wire it to `WeekViewModel.adoptShoppingState`.
    var onStateChange: ((_ haveAlready: Set<String>, _ orders: [StoredOrder]) -> Void)?

    init(
        env: AppEnvironment,
        list: ShoppingList,
        weekStartDate: String,
        instamart: (any InstamartGateway)? = nil,
        reloadList: (() async -> ShoppingList?)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.env = env
        self.list = list
        self.weekStartDate = weekStartDate
        self.instamart = instamart ?? env.instamart
        self.reloadList = reloadList
        self.now = now
        self.orders = list.orders
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

    /// Neither had nor on its way. An ordered item is not "to buy" — that is
    /// the point of ordering it — but a manual "have" tick still beats it.
    var toBuyCount: Int { toBuyNames.count }

    /// The to-buy items themselves, in list order — what an Instamart build
    /// matches, and what its Building state shows.
    var toBuyNames: [String] {
        scoped.categorized.flatMap { section in
            section.items.filter { !isHad($0.name) && !isOrdered($0.name) }.map(\.name)
        }
    }

    /// Ordered items within the current day scope ("M ordered"), as Android
    /// counts them.
    var orderedCount: Int {
        scoped.categorized.reduce(0) { total, section in
            total + section.items.filter { !isHad($0.name) && isOrdered($0.name) }.count
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

    /// On its way in a live order, and not ticked by hand.
    func isOrdered(_ name: String) -> Bool {
        orderedNames.contains(ShoppingScope.normalizeIngredientName(name))
    }

    /// `ingredients` (display names, typically the scoped list's) split into
    /// ordered and still-to-buy. A manual "already have" tick beats an order.
    func itemStates(_ ingredients: [String]) -> ItemStates {
        InstamartOrders.deriveItemStates(ingredients: ingredients, haveAlready: haveAlready, orders: orders)
    }

    /// Normalized names on their way in a live order — Share/Copy's `ordered`.
    var orderedNames: Set<String> { itemStates([]).ordered }

    /// What a cart build is told the user already has: `haveAlready ∪
    /// ordered`, so a second cart in a week cannot re-buy what is on its way.
    /// Sorted only so the request body is deterministic.
    var cartHaveAlready: [String] { haveAlready.union(orderedNames).sorted() }

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
        notifyStateChange()
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
        notifyStateChange()
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

    private func notifyStateChange() {
        onStateChange?(haveAlready, orders)
    }

    // MARK: - Instamart orders
    //
    // The ordering flow lives in InstamartViewModel; what it leaves behind —
    // the week's orders and the items they move into haveAlready — is the
    // list's, and lives here with the rest of the list.

    /// A checkout succeeded (`InstamartViewModel.onOrderPlaced`). Shown at
    /// once; saved here only when the server could not record it itself —
    /// fire-and-forget, because a failed write must not swallow the receipt
    /// the user is owed. Then one status read right away so the strip can show
    /// an ETA, forced: the order was stamped checked just now, so the throttle
    /// would skip it.
    func onOrderPlaced(_ placed: PlacedOrder) async {
        guard placed.weekStartDate == weekStartDate else {
            // The review sheet is modal over this week's pane, so the list
            // cannot have moved on; if it somehow did, writing this order
            // alone would replace that week's stored orders with one.
            Self.log.warning("onOrderPlaced: no list for \(placed.weekStartDate, privacy: .public)")
            return
        }
        orders = InstamartOrders.prependOrder(orders, placed.order)
        notifyStateChange()
        if !placed.recorded {
            let week = weekStartDate
            let snapshot = orders
            let instamart = instamart
            Task {
                do {
                    try await instamart.updateOrders(weekStartDate: week, orders: snapshot, haveAlready: nil)
                } catch {
                    Self.log.warning("updateOrders failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        await syncOrderStatuses(force: [placed.order.orderId])
    }

    /// A checkout ended without a confirmed outcome; the server may have
    /// recorded the order (`InstamartViewModel.onReloadShopping`). Re-reads
    /// the cached list and takes only its orders: pending ticks are flushed
    /// first and the local marks and day scope kept, so the reload cannot
    /// undo anything the user just did.
    func reloadShopping() async {
        guard let reloadList else { return }
        await flushPending()
        guard let probe = await reloadList(), !probe.absent else { return }
        orders = probe.orders
        notifyStateChange()
        await syncOrderStatuses()
    }

    /// Foreground delivery-status refresh — port of the webapp's
    /// `syncOrderStatuses`. Call when the list becomes ready and whenever the
    /// pane is shown again (including the app returning to the foreground on
    /// it); never from the background, by agreement with Swiggy.
    ///
    /// Live orders unchecked for a minute (plus `force`) get one status read
    /// each, sequentially; delivered items move into haveAlready; ONE PATCH
    /// writes both fields, so an order and the items it delivered cannot
    /// disagree after a half-failed update. Failures are silent. A sync
    /// already running makes this a no-op rather than a second burst.
    func syncOrderStatuses(force: Set<String> = []) async {
        guard orderSyncTask == nil else { return }
        let nowMillis = InstamartOrders.millis(now())
        let due = OrderStatusSync.due(orders, nowMillis: nowMillis)
            + orders.filter { force.contains($0.orderId) && !InstamartOrders.shouldRefresh($0, nowMillis: nowMillis) }
        guard !due.isEmpty else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            let instamart = self.instamart
            let updates = await OrderStatusSync.fetch(
                due,
                nowMillis: { InstamartOrders.millis(self.now()) },
                fetchStatus: { try await instamart.orderStatus(orderId: $0) }
            )
            guard !updates.isEmpty else { return }
            // Applied to the list as it is now, not as it was when the reads
            // started: ticks and orders may have changed meanwhile.
            guard let result = OrderStatusSync.apply(
                orders: self.orders, haveAlready: self.haveAlready, updates: updates
            ) else { return }
            self.orders = result.orders
            self.haveAlready = result.haveAlready
            self.notifyStateChange()
            await self.writeSyncResult(result)
        }
        orderSyncTask = task
        await task.value
        orderSyncTask = nil
    }

    /// The sync's one write. A pending tick debounce is folded into it rather
    /// than left to race it: two PATCHes carrying different haveAlready sets
    /// can land in either order, and the older one would win half the time.
    /// So the debounce is cancelled and, if anything was unsaved, haveAlready
    /// rides along even when delivery did not change it.
    private func writeSyncResult(_ result: OrderSyncResult) async {
        persistTask?.cancel()
        persistTask = nil
        let sendHave = result.haveChanged || hasUnsavedChanges
        let sentHave = haveAlready
        do {
            try await instamart.updateOrders(
                weekStartDate: weekStartDate,
                orders: result.orders,
                haveAlready: sendHave ? Array(sentHave) : nil
            )
            // Only if nothing was ticked while the write was out; a newer
            // tick has its own debounce running and stays unsaved.
            if sendHave, haveAlready == sentHave { hasUnsavedChanges = false }
        } catch {
            // Delivered items now ticked locally but not on the server: leave
            // them unsaved so the next toggle or the pane closing retries.
            if sendHave { hasUnsavedChanges = true }
            Self.log.warning("syncOrderStatuses write failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Export

    func share() {
        let text = ShoppingScope.buildShareText(
            scoped: scoped, haveAlready: haveAlready, scopeLabel: scopeLabel, ordered: orderedNames
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
        let text = ShoppingScope.buildCopyText(
            scoped: scoped, haveAlready: haveAlready, ordered: orderedNames
        )
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
