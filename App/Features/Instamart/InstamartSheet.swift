import KhanaKit
import SwiftUI

extension InstamartPhase {
    /// The phases that are a sheet. Connecting is not: Swiggy's own page is up
    /// in the auth session, and a sheet left behind it would be the first thing
    /// the user saw on coming back, before the status check had said anything.
    var showsSheet: Bool {
        switch self {
        case .building, .review, .placed: true
        case .idle, .connecting: false
        }
    }

    var isPlacing: Bool {
        if case let .review(review) = self { return review.placing }
        return false
    }
}

/// The Instamart ordering sheet: building → review → receipt, one sheet whose
/// body follows `InstamartViewModel.phase`. Port of the webapp's `BuildingCart`
/// (in `ShoppingListModal.tsx`), `SwiggyCartReview` and `SwiggyOrderPlaced`,
/// via Android's `InstamartSheet.kt`; the copy is the webapp's, word for word.
///
/// Present with `.sheet(isPresented:)` bound to `phase.showsSheet`, whose
/// setter calls `model.dismiss()` — that cancels a build, refuses while an
/// order is being placed, and otherwise closes. The presenter also sets
/// `.interactiveDismissDisabled` while placing, so nothing on screen can look
/// closed while the order's outcome is still on its way.
struct InstamartSheet: View {
    @Bindable var model: InstamartViewModel
    /// Items still to buy — the Building state shows them being matched.
    var buildingNames: [String]

    /// The last phase worth drawing. When the model goes idle the sheet starts
    /// its dismissal animation, and drawing `.idle` during it would flash an
    /// empty sheet on the way down.
    @State private var shown: InstamartPhase?

    var body: some View {
        let phase = model.phase.showsSheet ? model.phase : (shown ?? model.phase)
        KkbBackground {
            switch phase {
            case .building:
                InstamartBuildingView(names: buildingNames)
            case let .review(review):
                InstamartReviewView(
                    review: review,
                    onRebuild: { kept in Task { await model.rebuild(keptSpinIds: kept) } },
                    onPlaceOrder: { total in Task { await model.placeOrder(expectedTotal: total) } },
                    onCancel: { model.dismiss() }
                )
            case let .placed(order, stillToBuy):
                InstamartPlacedView(order: order, stillToBuy: stillToBuy, onDone: { model.dismissPlaced() })
            case .idle, .connecting:
                Color.clear
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // A sheet is drawn above the presenter, so the presenter's toast would
        // land underneath it — and a failure that keeps the review open (a
        // 429, a 422) must be read. Shown here only while the sheet is up; the
        // pane's binding is the mirror image, so one message never shows twice.
        .kkbToast(Binding(
            get: { model.phase.showsSheet ? model.message : nil },
            set: { model.message = $0 }
        ))
        .onAppear { if model.phase.showsSheet { shown = model.phase } }
        .onChange(of: model.phase) { _, new in
            if new.showsSheet { shown = new }
        }
    }
}

// MARK: - Building

/// A cart build can take a while and there is no partial progress to report.
/// The ingredients themselves are the honest substitute: seeing "Tomatoes,
/// Onions, Paneer…" being matched says what is happening and why it takes as
/// long as it does, without a paragraph saying so. Port of the webapp's
/// `BuildingCart`.
private struct InstamartBuildingView: View {
    var names: [String]

    /// How many of the ingredients being matched are shown by name.
    private static let chipLimit = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var dimmed = false

    var body: some View {
        let shown = Array(names.prefix(Self.chipLimit))
        let more = names.count - shown.count

        VStack(spacing: 0) {
            // The cart in a soft disc, ringed by the progress arc.
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Kkb.terracottaSurface, Kkb.marigoldSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Circle()
                    .stroke(Kkb.terracottaSurface, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Kkb.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(systemName: "cart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Kkb.accentText)
            }
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)

            Text("Building your cart")
                .kkbFont(.displaySmall)
                .italic()
                .foregroundStyle(Kkb.textPrimary)
                .padding(.top, 16)

            Group {
                if names.isEmpty {
                    Text("Checking Instamart")
                } else {
                    Text("Matching \(Text("\(names.count)").fontWeight(.semibold).foregroundStyle(Kkb.textPrimary)) \(names.count == 1 ? "ingredient" : "ingredients")")
                }
            }
            .kkbFont(.bodyMedium)
            .foregroundStyle(Kkb.textSecondary)
            .padding(.top, 4)

            if !shown.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                        chip(ShoppingScope.titleCaseIngredient(name), ground: Kkb.surface, edge: Kkb.hairline)
                            // Staggered so the row breathes rather than blinking in unison.
                            .opacity(dimmed ? 0.45 : 1)
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.9)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.18),
                                value: dimmed
                            )
                    }
                    if more > 0 {
                        chip("+\(more) more", ground: Kkb.creamWell, edge: .clear)
                    }
                }
                .padding(.top, 16)
                .accessibilityHidden(true)
            }

            Text("Nothing is ordered until you confirm")
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
                .padding(.top, 18)
            PoweredBySwiggy()
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
            dimmed = true
        }
    }

    private func chip(_ text: String, ground: Color, edge: Color) -> some View {
        Text(text)
            .kkbFont(.labelSmall)
            .foregroundStyle(Kkb.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ground, in: Capsule())
            .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
    }
}

// MARK: - Review

/// The last thing a user sees before an order that cannot be cancelled.
///
/// Every number here is Swiggy's. A line Swiggy did not price is a line Swiggy
/// did not put in the cart, and it is shown as that, without a price — the
/// agreement (clause 4(v)) forbids showing prices that differ from Swiggy's.
///
/// The bill and the buttons are pinned below the scrolling list rather than at
/// the end of it: on a twenty-item cart an inline total scrolls out of sight
/// exactly when someone is deciding whether to spend the money.
struct InstamartReviewView: View {
    var review: InstamartReview
    var onRebuild: (Set<String>) -> Void
    var onPlaceOrder: (Double) -> Void
    var onCancel: () -> Void

    // What is in the Swiggy cart right now is exactly `priced`, so selection
    // starts all-on and unticking is a request to rebuild, not a local
    // subtraction. Two sets, one per list, because the lists come from
    // different places — `priced` is Swiggy's answer, `removed` is ours.
    // Keyed by spinId.
    @State private var excluded: Set<String> = []
    @State private var restored: Set<String> = []
    /// Bill breakdown, collapsed until asked for. Survives a rebuild: someone who
    /// opened it to check the fees wants to see them move with the new total.
    @State private var billOpen = false
    /// Delivery address, one line until asked for.
    @State private var addressOpen = false

    private var build: CartBuild { review.build }
    private var lines: [PricedCartLine] { build.priced }
    private var bill: BillBreakdown { build.cart.billBreakdown }

    // Narrowed to lines actually on screen — the webapp's staleness guard. A
    // spinId left behind after its line stopped existing would hold the footer
    // in "Update cart" with nothing to update and no way back to the order
    // button.
    private var pendingExclusions: Set<String> {
        excluded.intersection(lines.map(\.spinId))
    }

    private var pendingRestores: Set<String> {
        restored.intersection(review.removed.map(\.spinId))
    }

    private var isPending: Bool { !pendingExclusions.isEmpty || !pendingRestores.isEmpty }

    private var keptSpinIds: Set<String> {
        Set(lines.map(\.spinId)).subtracting(pendingExclusions).union(pendingRestores)
    }

    var body: some View {
        VStack(spacing: 0) {
            InstamartSheetHeader(
                title: "Review your Instamart order",
                trailing: "\(lines.count) item\(lines.count == 1 ? "" : "s")"
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    addressCard
                    ForEach(lines, id: \.spinId) { line in
                        pricedRow(line)
                    }
                    if !build.cart.unserviceableItems.isEmpty {
                        noteBox(
                            title: "Swiggy can't deliver these to your address:",
                            body: build.cart.unserviceableItems.map(\.itemName).joined(separator: ", "),
                            ground: Kkb.terracottaSurface
                        )
                    }
                    if !build.plan.misses.isEmpty {
                        noteBox(
                            title: "Not on Instamart — buy these yourself:",
                            body: build.plan.misses.joined(separator: ", "),
                            ground: Kkb.creamWell
                        )
                    }
                    if !review.removed.isEmpty {
                        removedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        // A new cart is a new truth, and starts all-ticked. (The narrowing
        // above already ignores stale ids; this also drops ones that happen
        // to reappear in the new cart, which would otherwise render unticked.)
        .onChange(of: review.build) { _, _ in clearSelection() }
        .onChange(of: review.removed) { _, _ in clearSelection() }
    }

    private func clearSelection() {
        excluded = []
        restored = []
    }

    /// The most consequential fact on the screen, so it is first — but as one
    /// line until asked for. The tag ("Home") is what most people check, and a
    /// full three-line address above the cart pushed the cart below the fold.
    /// The address row is the toggle. The warning is the one part that says
    /// something may be wrong, so it never folds away.
    private var addressCard: some View {
        let label = InstamartCartLogic.addressLabelFor(
            addressTag: build.address.addressTag, addressLine: build.address.addressLine
        )
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { addressOpen.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Kkb.accentText)
                    if let tag = label.tag {
                        Text(tag)
                            .kkbFont(.labelSmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(Kkb.marigoldText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Kkb.marigoldSurface))
                            .fixedSize()
                    }
                    Text(label.detail)
                        .kkbFont(.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundStyle(Kkb.textPrimary)
                        .lineLimit(addressOpen ? nil : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Kkb.textSecondary)
                        .rotationEffect(.degrees(addressOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Delivering to \([label.tag, label.detail].compactMap { $0 }.joined(separator: ", "))")
            .accessibilityHint(addressOpen ? "Shows less of the address" : "Shows the full address")
            .accessibilityAddTraits(.isButton)

            if let warning = build.cart.addressWarning,
               !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warningText(warning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Kkb.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Kkb.hairline, lineWidth: 1))
    }

    private func pricedRow(_ line: PricedCartLine) -> some View {
        let included = !pendingExclusions.contains(line.spinId)
        let pack = Self.packLine(line.packLabel, line.packDescription)
            + (line.chargedQuantity > 1 ? " × \(line.chargedQuantity)" : "")
        return HStack(alignment: .top, spacing: 10) {
            checkbox(isOn: included) { excluded.formSymmetricDifference([line.spinId]) }
                .accessibilityLabel(line.display)
                .accessibilityValue(included ? "In this order" : "Removed")
            InstamartThumbnail(imageURL: line.imageUrl, size: 48)
                .opacity(included ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.display)
                    .kkbFont(.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(included ? Kkb.textPrimary : Kkb.textSecondary.opacity(0.7))
                    .strikethrough(!included, color: Kkb.textSecondary)
                if !pack.isEmpty {
                    Text(pack)
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                }
                // A low-confidence match is flagged with an icon, not a sentence:
                // on a twenty-line cart the same sentence under half the lines was
                // the loudest thing on screen and said nothing new after the first.
                // The words survive as the icon's VoiceOver label; the line's first
                // note follows the icon on the same row, or a short statement when
                // it has none.
                if line.isLowConfidence {
                    lowConfidence(firstNote: line.notes.first)
                }
                ForEach(Array(line.notes.enumerated()), id: \.offset) { index, note in
                    if !(line.isLowConfidence && index == 0) {
                        warningText(note)
                    }
                }
                if !line.inCart {
                    warningText("Swiggy didn't add this to the cart, so it won't be delivered.")
                }
                if line.quantityMismatch {
                    warningText("We asked for \(line.quantity); Swiggy has \(line.chargedQuantity).")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Swiggy's price or nothing: no line on this screen carries a number of ours.
            if let price = line.chargedPrice {
                Text(InstamartCartLogic.formatRupees(price))
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    /// Lines the user unticked and rebuilt away. No prices: the moment a line
    /// left the cart its price stopped being Swiggy's answer to anything.
    private var removedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Removed from this order")
            Text("Instamart still sells these. Tick anything you want back, then update the cart.")
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary)
            ForEach(review.removed, id: \.spinId) { line in
                let isBack = pendingRestores.contains(line.spinId)
                HStack(alignment: .top, spacing: 10) {
                    checkbox(isOn: isBack) { restored.formSymmetricDifference([line.spinId]) }
                        .accessibilityLabel(line.display)
                        .accessibilityValue(isBack ? "Coming back" : "Removed")
                    InstamartThumbnail(imageURL: line.imageUrl, size: 40)
                        .opacity(isBack ? 1 : 0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.display)
                            .kkbFont(.bodyMedium)
                            .fontWeight(.medium)
                            .foregroundStyle(isBack ? Kkb.textPrimary : Kkb.textSecondary)
                        let pack = Self.packLine(line.packLabel, line.packDescription)
                        if !pack.isEmpty {
                            Text(pack)
                                .kkbFont(.bodySmall)
                                .foregroundStyle(Kkb.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Kkb.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Kkb.hairline, lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        let total = InstamartCartLogic.parseRupees(bill.toPay.value)
        let keptCount = keptSpinIds.count
        return VStack(spacing: 12) {
            // Swiggy's own breakdown, rendered as it arrives — but folded away
            // until asked for. The total it adds up to is always on screen and
            // already includes every fee, so collapsing it hides arithmetic, not
            // a charge; open, it was four or five rows of pinned footer competing
            // with the cart itself. The total row is the toggle, so the breakdown
            // opens directly above the number it explains.
            if billOpen && !bill.lineItems.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(bill.lineItems.enumerated()), id: \.offset) { _, row in
                        billLine(row.label, row.value, emphasised: false)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                Divider().overlay(Kkb.hairline)
            }
            if bill.lineItems.isEmpty {
                totalLine
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { billOpen.toggle() }
                } label: {
                    totalLine
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(bill.toPay.label.isEmpty ? "To pay" : bill.toPay.label) \(bill.toPay.value)")
                .accessibilityHint(billOpen ? "Hides the bill details" : "Shows the bill details")
            }

            if review.rebuilding {
                // Its own branch, not a label on the Update button. Pressing
                // Update clears the pending sets, so without this the footer
                // would fall through to Cancel and Place order — offering the
                // one action that must not be taken against a cart being
                // rewritten underneath it.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Kkb.textSecondary)
                    Text("Updating cart with selections")
                        .kkbFont(.labelLarge)
                        .foregroundStyle(Kkb.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Kkb.creamWell))
            } else if isPending {
                VStack(alignment: .leading, spacing: 10) {
                    Text(keptCount == 0
                         ? "That removes everything from the cart."
                         : "Update the cart to \(keptCount) item\(keptCount == 1 ? "" : "s") for Swiggy's new total.")
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        InstamartPillButton(title: "Undo", filled: false, isEnabled: !review.busy) {
                            clearSelection()
                        }
                        InstamartPillButton(
                            title: "Update cart", filled: true, isEnabled: !review.busy && keptCount > 0
                        ) {
                            onRebuild(keptSpinIds)
                            // Dispatching the rebuild consumes the pending
                            // edits — what comes back is the new truth. Left in
                            // place they accumulate: a line unticked, rebuilt
                            // away, restored and rebuilt back would land in the
                            // cart still listed as excluded, and render
                            // unticked. If the rebuild fails the cart is
                            // unchanged and all-ticked matches it.
                            clearSelection()
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    InstamartPillButton(title: "Cancel", filled: false, isEnabled: !review.busy, action: onCancel)
                        .fixedSize()
                    KkbPrimaryButton(
                        title: review.placing ? "Placing order…" : "Place COD order · \(bill.toPay.value)",
                        isEnabled: !review.busy && !lines.isEmpty && total > 0
                    ) {
                        onPlaceOrder(total)
                    }
                }
            }

            VStack(spacing: 2) {
                Text("Cash on delivery · Swiggy orders can't be cancelled once placed")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
                    .multilineTextAlignment(.center)
                PoweredBySwiggy()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(Kkb.hairline) }
    }

    /// The total, with the breakdown's open/closed arrow when there is one.
    private var totalLine: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Text(bill.toPay.label.isEmpty ? "To pay" : bill.toPay.label)
                    .kkbFont(.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Kkb.textPrimary)
                if !bill.lineItems.isEmpty {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Kkb.textSecondary)
                        .rotationEffect(.degrees(billOpen ? 180 : 0))
                }
            }
            Spacer(minLength: 16)
            Text(bill.toPay.value.isEmpty ? "—" : bill.toPay.value)
                .kkbFont(.displaySmall)
                .foregroundStyle(Kkb.textPrimary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func billLine(_ label: String, _ value: String, emphasised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .kkbFont(.bodyMedium)
                .fontWeight(emphasised ? .medium : .regular)
                .foregroundStyle(emphasised ? Kkb.textPrimary : Kkb.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .kkbFont(emphasised ? .displaySmall : .bodyMedium)
                .foregroundStyle(Kkb.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: Pieces

    private func checkbox(isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundStyle(isOn ? Kkb.terracotta500 : Kkb.textSecondary.opacity(0.5))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(review.busy)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func noteBox(title: String, body: String, ground: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .kkbFont(.bodyMedium)
                .fontWeight(.medium)
            Text(body)
                .kkbFont(.bodyMedium)
        }
        .foregroundStyle(Kkb.textPrimary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ground))
    }

    /// "500 g · Fresho Tomato" — either half may be missing in Swiggy's payload.
    static func packLine(_ packLabel: String, _ packDescription: String) -> String {
        [packLabel, packDescription]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Placed

/// The receipt, shown once, right after an uncancellable COD order.
///
/// The half that matters is "Still to buy yourself". A cart never covers the
/// whole list, and this is the only moment in the flow where we know the user
/// is looking — leaving it out is the difference between "your groceries are
/// handled" and finding four things missing on Thursday.
struct InstamartPlacedView: View {
    var order: StoredOrder
    var stillToBuy: [String]
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InstamartSheetHeader(title: "Your Instamart order", trailing: nil)
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("Order placed")
                            .kkbFont(.displaySmall)
                            .italic()
                            .foregroundStyle(Kkb.textPrimary)
                        Text(order.total)
                            .kkbFont(.displayMedium)
                            .foregroundStyle(Kkb.textPrimary)
                        Text("Order \(order.orderId) · cash on delivery")
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                            .multilineTextAlignment(.center)
                        if !order.statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(order.statusLabel)
                                .kkbFont(.bodyMedium)
                                .fontWeight(.medium)
                                .foregroundStyle(Kkb.accentText)
                                .padding(.top, 4)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("On its way (\(order.items.count))".eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.textSecondary)
                        Text(order.items.map(\.display).joined(separator: ", "))
                            .kkbFont(.bodyMedium)
                            .foregroundStyle(Kkb.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(card)

                    if !stillToBuy.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Still to buy yourself (\(stillToBuy.count))")
                                .kkbFont(.bodyMedium)
                                .fontWeight(.medium)
                                .foregroundStyle(Kkb.textPrimary)
                            Text(stillToBuy.joined(separator: ", "))
                                .kkbFont(.bodyMedium)
                                .foregroundStyle(Kkb.textPrimary)
                            Text("Instamart couldn't cover these, so they stay on your shopping list.")
                                .kkbFont(.bodySmall)
                                .foregroundStyle(Kkb.textSecondary)
                                .padding(.top, 6)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Kkb.marigoldSurface))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KkbPrimaryButton(title: "Back to shopping list", action: onDone)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Kkb.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Kkb.hairline, lineWidth: 1))
    }
}

// MARK: - Shared pieces

/// Title, the agreement's attribution under it, and an optional right-hand note.
private struct InstamartSheetHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .kkbFont(.displaySmall)
                    .italic()
                    .foregroundStyle(Kkb.textPrimary)
                PoweredBySwiggy()
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }
}

/// The pack shot. Always occupies its slot, image or not, so a cart where
/// Instamart sent art for some lines and not others still reads as a column.
/// https only: the URL comes from a third party's payload, and a cleartext
/// fetch is neither allowed by ATS nor wanted.
private struct InstamartThumbnail: View {
    var imageURL: String?
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            // White in both appearances: pack shots are cut out on white.
            shape.fill(Color.white)
            if let imageURL, imageURL.hasPrefix("https://"), let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(Kkb.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A rounded secondary action: outlined, or solid ink for the one that commits.
private struct InstamartPillButton: View {
    var title: String
    var filled: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .kkbFont(.labelLarge)
                .foregroundStyle(filled ? Kkb.surface : Kkb.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Capsule().fill(filled ? Kkb.textPrimary : Color.clear))
                .overlay(Capsule().stroke(filled ? Color.clear : Kkb.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private func sectionLabel(_ text: String) -> some View {
    Text(text.eyebrow)
        .kkbFont(.sectionLabel)
        .foregroundStyle(Kkb.textSecondary)
}

/// What the low-confidence icon means, for VoiceOver. Same words as the web's tooltip.
private let lowConfidenceLabel = "We weren't confident about this match — check it before ordering."

/// Follows the icon when the line has no note of its own.
private let lowConfidenceShort = "We weren't confident about this match"

private func lowConfidence(firstNote: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
        Image(systemName: "exclamationmark.circle")
            .kkbFont(.bodySmall)
            .foregroundStyle(Kkb.accentText)
            .accessibilityLabel(lowConfidenceLabel)
        // A bare icon reads as something having gone wrong without saying what,
        // so with no note to follow it the icon gets a short statement of its own.
        Text(firstNote ?? lowConfidenceShort)
            .kkbFont(.bodySmall)
            .foregroundStyle(Kkb.accentText)
            .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
    .padding(.top, 2)
}

private func warningText(_ text: String) -> some View {
    Text(text)
        .kkbFont(.bodySmall)
        .foregroundStyle(Kkb.accentText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
}

// MARK: - Previews

#if DEBUG
private enum InstamartPreviewData {
    static let build = CartBuild(
        address: InstamartAddress(id: "a1", addressLine: "Flat 4B, Lake View Apartments, Powai", addressTag: "Home"),
        plan: CartPlan(misses: ["Kasuri methi", "Curry leaves"]),
        cart: InstamartCart(
            billBreakdown: BillBreakdown(
                lineItems: [
                    BillRow(label: "Item total", value: "₹312"),
                    BillRow(label: "Delivery fee", value: "₹30"),
                    BillRow(label: "Handling fee", value: "₹9"),
                ],
                toPay: BillRow(label: "To pay", value: "₹351")
            ),
            unserviceableItems: [UnserviceableItem(itemName: "Paneer 1kg")]
        ),
        priced: [
            PricedCartLine(
                ingredient: "tomato", display: "Tomato", spinId: "s1", packDescription: "Fresho Tomato",
                packLabel: "500 g", quantity: 2, confidence: "high",
                inCart: true, chargedPrice: 58, chargedQuantity: 2
            ),
            PricedCartLine(
                ingredient: "onion", display: "Onion", spinId: "s2", packLabel: "1 kg",
                quantity: 1, confidence: "low", notes: ["Rounded up to the nearest pack."],
                inCart: true, chargedPrice: 45.5, chargedQuantity: 1
            ),
            PricedCartLine(
                ingredient: "ghee", display: "Ghee", spinId: "s3", packLabel: "200 ml",
                quantity: 3, confidence: "high", inCart: true, chargedPrice: 209,
                chargedQuantity: 1, quantityMismatch: true
            ),
            PricedCartLine(
                ingredient: "coriander", display: "Coriander", spinId: "s4", packLabel: "100 g",
                quantity: 1, confidence: "high", inCart: false
            ),
        ]
    )
}

#Preview("Building") {
    InstamartBuildingView(names: [
        "tomato", "onion", "paneer", "green chilli", "ginger", "coriander", "basmati rice", "toor dal", "ghee",
    ])
    .background(Kkb.surface)
}

#Preview("Review") {
    InstamartReviewView(
        review: InstamartReview(
            build: InstamartPreviewData.build,
            removed: [CartPlanLine(ingredient: "rice", display: "Basmati rice", spinId: "s9", packLabel: "1 kg")]
        ),
        onRebuild: { _ in },
        onPlaceOrder: { _ in },
        onCancel: {}
    )
    .background(Kkb.background)
}

#Preview("Placed") {
    InstamartPlacedView(
        order: StoredOrder(
            orderId: "1234567890", total: "₹351", statusLabel: "Order confirmed",
            items: [OrderedItem(name: "tomato", display: "Tomato"), OrderedItem(name: "onion", display: "Onion")]
        ),
        stillToBuy: ["Kasuri methi", "Curry leaves", "Coriander"],
        onDone: {}
    )
    .background(Kkb.background)
}
#endif
