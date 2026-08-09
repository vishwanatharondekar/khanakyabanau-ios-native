import KhanaKit
import SwiftUI

/// The market list: pick the days you're shopping for, tick off what you already
/// have, then share, copy or export it.
struct ShoppingListSheet: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    var list: ShoppingList
    var weekStartDate: String
    var onDismiss: () -> Void

    @State private var model: ShoppingListViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().tint(Kkb.terracotta500)
            }
        }
        .task {
            if model == nil {
                model = ShoppingListViewModel(
                    env: env, list: list, weekStartDate: weekStartDate
                )
            }
        }
        .presentationDragIndicator(.visible)
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
        .onDisappear {
            Task { await model.flushPending() }
            onDismiss()
        }
    }

    private func header(_ model: ShoppingListViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Market list".eyebrow)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)
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
            Text("Shopping list")
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
            Text("Shopping for \(model.scopeLabel.isEmpty ? "no days" : model.scopeLabel)")
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
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
        .accessibilityValue(isHad ? "Already have" : "To buy")
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

    private func footer(_ model: ShoppingListViewModel) -> some View {
        VStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.terracotta600)
            }

            Text(model.toBuyCount == 0 && model.haveCount > 0
                 ? "Everything's covered — nothing left to buy"
                 : "\(model.toBuyCount) to buy · \(model.haveCount) have")
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)

            Text("Tip: Copy, then paste into Reminders — each line becomes an item.")
                .kkbFont(.bodySmall)
                .foregroundStyle(Kkb.textSecondary.opacity(0.85))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                footerAction(
                    "Share", systemImage: "square.and.arrow.up", isEnabled: model.canExport
                ) { model.share() }
                footerAction(
                    "Copy", systemImage: "doc.on.doc", isEnabled: model.canExport
                ) { model.copyToPasteboard() }
                footerAction(
                    model.isExportingPDF ? "Generating…" : "PDF",
                    systemImage: "doc.richtext",
                    isBusy: model.isExportingPDF,
                    isEnabled: model.canExport
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

    private func footerAction(
        _ title: String,
        systemImage: String,
        isBusy: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(Kkb.accentText)
                } else {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).kkbFont(.labelSmall)
            }
            .foregroundStyle(Kkb.accentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Kkb.terracottaSurface.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
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
        case "Dairy & Eggs": Kkb.terracotta400
        case "Meat & Seafood": Kkb.terracotta500
        case "Grains & Pulses": Kkb.marigold600
        case "Spices & Herbs": Kkb.terracotta400
        case "Pantry Items": Kkb.ink700
        default: Kkb.ink600
        }
    }
}
