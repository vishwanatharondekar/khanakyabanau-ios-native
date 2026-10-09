import KhanaKit
import SwiftUI

/// The market list: pick the days you're shopping for, tick off what you already
/// have, then share, copy or export it.
///
/// A pane rather than a sheet. No title of its own: the week selector and the
/// Shopping tab directly above already say which week this is and what it is,
/// so a "Shopping list" heading inside the pane repeats both of them.
struct ShoppingListContent: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var list: ShoppingList
    var weekStartDate: String
    var week: WeekViewModel
    @Bindable var instamart: InstamartViewModel

    @State private var model: ShoppingListViewModel?
    /// A TabView keeps the Plan tab's views alive while Today or Me is shown,
    /// so a foreground there would still reach `onChange(of: scenePhase)`.
    /// Delivery status is fetched only while this pane is on screen.
    @State private var isVisible = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().tint(Kkb.terracotta500)
            }
        }
        // Keyed on the week so switching weeks rebuilds the model rather than
        // showing last week's ticks against this week's list.
        .task(id: weekStartDate) {
            let week = week
            let weekStart = weekStartDate
            let created = ShoppingListViewModel(
                env: env,
                list: list,
                weekStartDate: weekStart,
                reloadList: { await week.cachedShoppingList(weekStartDate: weekStart) }
            )
            // This model is rebuilt from `list` (the week's ShoppingSession)
            // every time the pane is shown, so every tick and order has to be
            // written back to it — without this, ticking "have", switching to
            // Meals and back showed the list as first loaded.
            created.onStateChange = { have, orders in
                week.adoptShoppingState(weekStartDate: weekStart, haveAlready: have, orders: orders)
            }
            model = created
            // Re-pointed at every new list model, so after a week change a
            // placed order lands on the week it was placed for. Both callbacks
            // buffer on the Instamart side until set, and capture the model
            // strongly on purpose: a weak capture would let an order placed
            // while the pane was away be delivered to nothing — and an
            // unrecorded order's only route to the server is a list taking it.
            instamart.onOrderPlaced = { placed in Task { await created.onOrderPlaced(placed) } }
            instamart.onReloadShopping = { Task { await created.reloadShopping() } }
            // Showing the pane is one of the two moments a delivery status may
            // be fetched (the other is the app returning to it, below).
            await created.syncOrderStatuses()
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isVisible, let model else { return }
            Task { await model.syncOrderStatuses() }
        }
        .sheet(isPresented: instamartSheetBinding) {
            InstamartSheet(model: instamart, buildingNames: model?.toBuyNames ?? [])
                // Swipe-down while an order is being placed would look like a
                // cancel of something that cannot be cancelled.
                .interactiveDismissDisabled(instamart.phase.isPlacing)
        }
        .swiggySignIn(instamart)
        // The sheet shows Instamart's messages while it is up; this shows them
        // otherwise — "Reconnect Swiggy to order.", a repriced cart that closed
        // the review. Exactly one of the two bindings is non-nil at a time.
        .kkbToast(Binding(
            get: { instamart.phase.showsSheet ? nil : instamart.message },
            set: { instamart.message = $0 }
        ))
    }

    /// Any dismissal — swipe, Cancel — goes through `dismiss()`, which cancels
    /// a build and refuses while placing.
    private var instamartSheetBinding: Binding<Bool> {
        Binding(
            get: { instamart.phase.showsSheet },
            set: { if !$0 { instamart.dismiss() } }
        )
    }

    /// The Instamart button: everything the cart needs, captured at the tap.
    private func orderOnInstamart(_ model: ShoppingListViewModel) {
        let request = OrderRequest(
            scoped: model.scoped,
            haveAlready: model.cartHaveAlready,
            isVegetarian: session.user?.dietaryPreferences?.isVegetarian ?? false,
            weekStartDate: model.weekStartDate
        )
        Task { await instamart.order(request) }
    }

    @ViewBuilder
    private func content(_ model: ShoppingListViewModel) -> some View {
        @Bindable var model = model

        KkbBackground {
            VStack(spacing: 0) {
                header(model)

                if model.hasDayWise {
                    dayChips(model)
                }

                Divider().overlay(Kkb.hairline)

                // The whole week's live order, not just the scope's: the strip
                // is about the delivery, which does not shrink when a day chip
                // is unticked.
                if let live = model.orders.first(where: { $0.orderStatus == .live }) {
                    LiveOrderStrip(
                        arrivingCount: model.orderedNames.count,
                        etaAt: live.etaAt,
                        statusLabel: live.statusLabel
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                if model.selectedDays.isEmpty {
                    emptyState(
                        script: "Pick at least one day",
                        caption: "Tap the day chips above to choose what you're shopping for."
                    )
                } else if model.scoped.isEmpty {
                    emptyState(
                        script: "Nothing on the list yet",
                        caption: "No meals planned on the selected days."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(model.scoped.categorized) { section in
                                categorySection(model, section)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }

                footer(model)
            }
        }
        .kkbToast($model.toast)
        // The ticks are debounced 600ms, and as a tab there is no close button
        // to flush on — the user simply navigates away.
        .onDisappear { Task { await model.flushPending() } }
    }

    /// Only the scope line survives from the sheet's header. "Market list" and
    /// "Shopping list" both said what the tab above already says.
    private func header(_ model: ShoppingListViewModel) -> some View {
        HStack {
            Text("Shopping for \(model.scopeLabel.isEmpty ? "no days" : model.scopeLabel)")
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
            Spacer()
            if model.list.cached {
                Text("CACHED")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.sageText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Kkb.sageSurface))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func dayChips(_ model: ShoppingListViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DayOfWeek.allCases) { day in
                    KkbChip(
                        title: String(day.displayName.prefix(3)),
                        isSelected: model.selectedDays.contains(day)
                    ) {
                        model.toggleDay(day)
                    }
                }
                KkbChip(
                    title: "All week",
                    isSelected: model.selectedDays.count == 7
                ) {
                    model.selectAllDays()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func categorySection(
        _ model: ShoppingListViewModel,
        _ section: CategorySection
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Self.categoryAccent(section.name))
                    .frame(width: 8, height: 8)
                Text(section.name)
                    .kkbFont(.titleMedium)
                    .foregroundStyle(Kkb.textPrimary)
                Text("(\(section.items.count) item\(section.items.count == 1 ? "" : "s"))")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
                Spacer()
                Button {
                    model.toggleCategory(section)
                } label: {
                    let allHad = section.items.allSatisfy { model.isHad($0.name) }
                    Text(allHad ? "Need all" : "Have all")
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Kkb.terracottaSurface))
                }
                .buttonStyle(.plain)
            }

            ForEach(section.items, id: \.name) { item in
                ingredientRow(model, item)
            }
        }
    }

    private func ingredientRow(
        _ model: ShoppingListViewModel,
        _ item: Ingredient
    ) -> some View {
        let isHad = model.isHad(item.name)
        // On its way from Instamart. `isOrdered` already excludes a manual
        // "have" tick, so have still wins.
        let isOrdered = model.isOrdered(item.name)
        let meals = model.meals(for: item.name)
        let amount = ShoppingScope.formatAmount(
            IngredientAmount(amount: item.amount, unit: item.unit)
        )

        return Button {
            model.toggleHave(item.name)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isHad ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isHad ? Kkb.sage500 : Kkb.textSecondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ShoppingScope.titleCaseIngredient(item.name))
                            .kkbFont(.bodyLarge)
                            .foregroundStyle(isHad ? Kkb.textSecondary : Kkb.textPrimary)
                            .strikethrough(isHad, color: Kkb.textSecondary)
                        if isOrdered {
                            Text("ORDERED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Kkb.accentText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Kkb.terracottaSurface))
                        }
                        if model.isNew(item.name), !isHad {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Kkb.marigoldText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Kkb.marigoldSurface))
                        }
                    }
                    if !meals.isEmpty {
                        Text(contextLine(meals))
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !amount.isEmpty {
                    Text(amount)
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(isHad ? Kkb.textSecondary : Kkb.textPrimary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(ShoppingScope.titleCaseIngredient(item.name)), \(amount)"
        )
        .accessibilityValue(isHad ? "Already have" : isOrdered ? "Ordered" : "To buy")
        .accessibilityAddTraits(.isButton)
    }

    private func contextLine(_ meals: [String]) -> String {
        let shown = meals.prefix(3).joined(separator: " · ")
        let extra = meals.count - 3
        return extra > 0 ? "for \(shown) +\(extra) more" : "for \(shown)"
    }

    private func emptyState(script: String, caption: String) -> some View {
        VStack {
            Spacer()
            KkbEmptyState(script: script, caption: caption)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    /// Counts, then the actions. When Instamart is offered it is the primary
    /// action and Share / Copy step aside — as on the webapp and Android, a
    /// filled cart beats a pasted list — while PDF stays as the secondary.
    private func footer(_ model: ShoppingListViewModel) -> some View {
        let showInstamart = instamart.offer != .hidden
        return VStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.terracotta600)
            }

            Text(countsLine(model))
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)

            if showInstamart {
                PoweredBySwiggy()
            } else {
                // Names the Copy button, so it goes when Copy does.
                Text("Tip: Copy, then paste into Reminders — each line becomes an item.")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                if showInstamart {
                    instamartAction(model)
                } else {
                    footerAction(
                        "Share", systemImage: "square.and.arrow.up", isEnabled: model.canExport
                    ) { model.share() }
                    footerAction(
                        "Copy", systemImage: "doc.on.doc", isEnabled: model.canExport
                    ) { model.copyToPasteboard() }
                }
                // Beside Instamart, PDF keeps its own width and Instamart takes
                // the rest — the same split Android and the webapp use. Both
                // stretching let the primary's priority squeeze PDF to a sliver.
                footerAction(
                    model.isExportingPDF ? "Generating…" : "PDF",
                    systemImage: "doc.richtext",
                    isBusy: model.isExportingPDF,
                    isEnabled: model.canExport,
                    fills: !showInstamart
                ) {
                    Task { await model.exportPDF() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    /// "N to buy · M ordered · K have", ordered only when there is any. An
    /// empty list keeps the plain counts rather than claiming it is covered.
    private func countsLine(_ model: ShoppingListViewModel) -> String {
        let toBuy = model.toBuyCount
        let ordered = model.orderedCount
        let have = model.haveCount
        if toBuy == 0, ordered == 0, have > 0 {
            return "Everything's covered — nothing left to buy"
        }
        return ["\(toBuy) to buy", ordered > 0 ? "\(ordered) ordered" : nil, "\(have) have"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The webapp's phone labels, in the footer's short-tile form. The same
    /// word whether or not Swiggy is connected: connecting is our plumbing,
    /// not a decision the user is being asked to make.
    private func instamartAction(_ model: ShoppingListViewModel) -> some View {
        let (title, busy): (String, Bool) = switch instamart.phase {
        case .building: ("Building…", true)
        case .connecting: ("Waiting for Swiggy…", true)
        default: ("Instamart", false)
        }
        return footerAction(
            title,
            systemImage: "cart",
            isBusy: busy,
            isEnabled: model.canExport && instamart.phase == .idle,
            isPrimary: true
        ) {
            orderOnInstamart(model)
        }
    }

    private func footerAction(
        _ title: String,
        systemImage: String,
        isBusy: Bool = false,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        /// Stretch to share the row, or keep the label's own width.
        fills: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let tint = isPrimary ? Kkb.cream50 : Kkb.accentText
        return Button(action: action) {
            VStack(spacing: 4) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(tint)
                } else {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).kkbFont(.labelSmall).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: fills ? .infinity : nil)
            .padding(.horizontal, fills ? 0 : 22)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPrimary ? AnyShapeStyle(Kkb.terracotta500) : AnyShapeStyle(Kkb.terracottaSurface.opacity(0.7)))
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !fills, vertical: false)
        .disabled(isBusy || !isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    /// Category dot colours, taken from Android's `categoryAccent()`
    /// (`ShoppingListDialog.kt:692-735`). A user comparing their list against a
    /// partner's Android phone should see the same colour beside the same heading.
    static func categoryAccent(_ category: String) -> Color {
        switch category {
        case "Vegetables": Kkb.sage500
        case "Fruits": Kkb.marigold500
        case "Dairy": Kkb.terracotta400
        case "Meat, Seafood & Eggs": Kkb.terracotta500
        case "Grains & Pulses": Kkb.marigold600
        case "Spices & Herbs": Kkb.terracotta400
        case "Pantry Items": Kkb.ink700
        default: Kkb.ink600
        }
    }
}

/// "N items arriving from Instamart" while an order is live, with Swiggy's
/// countdown or status words. N is every name on its way this week, not just
/// the scope's — as on the webapp and Android.
///
/// `now` ticks every thirty seconds, and only while there is a countdown to
/// move: the strip reads in whole minutes, so a faster tick would redraw for
/// nothing anyone can see, and an order with no estimate has no timer at all.
/// The loop is the view's `.task`, so it stops when the pane goes away.
private struct LiveOrderStrip: View {
    var arrivingCount: Int
    var etaAt: String?
    var statusLabel: String

    @State private var now = Date()

    private var countdown: String? {
        InstamartOrders.formatCountdown(etaAt: etaAt, nowMillis: InstamartOrders.millis(now))
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(arrivingCount) item\(arrivingCount == 1 ? "" : "s") arriving from Instamart")
                    .kkbFont(.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Kkb.textPrimary)
                PoweredBySwiggy()
            }
            Spacer(minLength: 0)
            Text(countdown ?? (statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? "Order placed" : statusLabel))
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Kkb.terracottaSurface))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Kkb.terracotta200.opacity(0.8), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .task(id: etaAt) {
            now = Date()
            while countdown != nil {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
    }
}
