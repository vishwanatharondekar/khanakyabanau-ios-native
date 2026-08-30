import KhanaKit
import SwiftUI

/// Rename or clear one slot. Clearing is just saving an empty name — there is no
/// separate delete affordance, matching the other clients.
struct EditMealSheet: View {
    @Environment(\.dismiss) private var dismiss

    var target: SlotTarget
    var meal: Meal
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        SheetScaffold(
            eyebrow: "\(target.day.displayName) · \(target.type.displayName)",
            title: "What's cooking?",
            confirmTitle: "Save",
            onCancel: { onCancel(); dismiss() },
            onConfirm: { onSave(name); dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                TextField("write a dish…", text: $name, axis: .vertical)
                    .kkbFont(.bodyLarge)
                    .foregroundStyle(Kkb.textPrimary)
                    .lineLimit(2...5)
                    .focused($isFocused)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Kkb.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Kkb.hairline, lineWidth: 1)
                    )

                if let prep = meal.validPrep, !prep.steps.isEmpty {
                    Divider().overlay(Kkb.hairline)
                    MealPrepSection(prep: prep)
                }
            }
        }
        .onAppear {
            name = meal.name
            isFocused = true
        }
    }
}

/// The prep step list, shared between the edit sheet and the meal detail page.
struct MealPrepSection: View {
    var prep: MealPrep
    /// The meal-detail page draws its own heading and hands-on badge, so it asks
    /// for just the steps rather than rendering "Preparation" twice.
    var showsHeading: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeading {
                HStack {
                    Text("Preparation")
                        .kkbFont(.displaySmall)
                        .italic()
                        .foregroundStyle(Kkb.sageText)
                    Spacer()
                    if prep.activeMinutes > 0 {
                        Text("~\(prep.activeMinutes) MIN HANDS-ON")
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.textSecondary)
                    }
                }
            }

            // Longest lead time first: the thing to start earliest is the thing the
            // user needs to see first.
            ForEach(
                Array(prep.steps.sorted { $0.leadTimeMinutes > $1.leadTimeMinutes }.enumerated()),
                id: \.offset
            ) { _, step in
                HStack(alignment: .top, spacing: 10) {
                    Text(step.category.emoji).font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.text)
                            .kkbFont(.bodyMedium)
                            .foregroundStyle(Kkb.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(formatLeadTime(step.leadTimeMinutes).eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.sageText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Kkb.sageSurface.opacity(0.6))
                )
            }
        }
    }
}

/// Pick a dish for a slot: write your own, or choose from suggestions seeded
/// locally and refreshed from the server-side corpus.
struct MealSuggestionSheet: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    var target: SlotTarget
    var currentName: String
    var initialSuggestions: [String]
    var onRefresh: ([String]) async -> [String]
    var onPick: (String, String?) -> Void
    var onCancel: () -> Void

    @State private var suggestions: [String] = []
    @State private var images: [String: String] = [:]
    /// Names the image lookup has already answered for — including the ones it had
    /// no photo for. Without this, a dish the pool doesn't know shimmers forever.
    @State private var resolvedNames: Set<String> = []
    @State private var written = ""
    @State private var isRefreshing = false
    @FocusState private var isFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Write your own".eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.accentText)
                        HStack(spacing: 10) {
                            TextField("write your own…", text: $written)
                                .kkbFont(.bodyLarge)
                                .focused($isFocused)
                                .submitLabel(.done)
                                .onSubmit(submitWritten)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Kkb.surfaceSunken)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Kkb.hairline, lineWidth: 1)
                                )
                            Button(action: submitWritten) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Kkb.cream50)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(Kkb.terracotta500))
                            }
                            .buttonStyle(.plain)
                            .disabled(written.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(written.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                            .accessibilityLabel("Save this dish")
                        }
                    }

                    Text(suggestions.isEmpty ? "NO SUGGESTIONS YET" : "OR PICK A SUGGESTION")
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.textSecondary)

                    if suggestions.isEmpty {
                        KkbEmptyState(
                            script: "— nothing yet —",
                            caption: "Tap below for fresh ideas.",
                            alignment: .leading
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(suggestions, id: \.self) { name in
                                SuggestionCard(
                                    name: name,
                                    imageUrl: images[name.lowercased()],
                                    isResolving: !resolvedNames.contains(name.lowercased())
                                ) {
                                    onPick(name, images[name.lowercased()])
                                    dismiss()
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            isRefreshing = true
                            suggestions = await onRefresh(suggestions)
                            await loadImages()
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRefreshing {
                                ProgressView().controlSize(.small).tint(Kkb.accentText)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRefreshing ? "Refreshing…" : "Fresh ideas")
                        }
                        .kkbFont(.labelLarge)
                        .foregroundStyle(Kkb.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Kkb.terracottaSurface.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDragIndicator(.visible)
        .task {
            suggestions = initialSuggestions
            await loadImages()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(target.day.displayName) · \(target.type.displayName)".eyebrow)
                .kkbFont(.sectionLabel)
                .tracking(4)
                .foregroundStyle(Kkb.accentText)
            Text(currentName.isEmpty ? "Choose a meal" : "Replace this meal")
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
            if !currentName.isEmpty {
                Text("Currently: \(currentName)")
                    .kkbFont(.bodyMedium)
                    .italic()
                    .foregroundStyle(Kkb.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func submitWritten() {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onPick(trimmed, nil)
        dismiss()
    }

    private func loadImages() async {
        let asked = suggestions
        let resolved = await env.meals.resolveImages(for: asked)
        images.merge(resolved) { _, new in new }
        resolvedNames.formUnion(asked.map { $0.lowercased() })
    }
}

private struct SuggestionCard: View {
    var name: String
    var imageUrl: String?
    var isResolving: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    MealThumbnail(
                        imageUrl: imageUrl,
                        size: proxy.size.width,
                        cornerRadius: 16,
                        isResolving: isResolving
                    )
                }
                .aspectRatio(1, contentMode: .fit)

                Text(name)
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Kkb.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Kkb.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

/// Pantry ingredients and an optional mood, fed into one week generation.
struct AIPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onGenerate: ([String], [String], Bool) -> Void
    var onCancel: () -> Void

    @State private var ingredients = ""
    @State private var moods: Set<String> = []
    @State private var restrictToIngredients = false

    /// Fewest items that can fill a week; keep in step with
    /// MIN_RESTRICTED_INGREDIENTS in the webapp's lib/ingredient-restriction.ts.
    private let minRestrictedIngredients = 3

    private var parsedIngredients: [String] {
        ingredients
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canRestrict: Bool { parsedIngredients.count >= minRestrictedIngredients }

    var body: some View {
        SheetScaffold(
            eyebrow: "AI Kitchen",
            title: "Generate with AI",
            confirmTitle: "Generate",
            onCancel: { onCancel(); dismiss() },
            onConfirm: {
                onGenerate(parsedIngredients, Array(moods).sorted(), canRestrict && restrictToIngredients)
                dismiss()
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's in the pantry?".eyebrow)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.accentText)
                    Text("List what you've already got, comma-separated. We'll weave them in.")
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                    TextField("paneer, palak, dosa batter…", text: $ingredients, axis: .vertical)
                        .kkbFont(.bodyLarge)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Kkb.surfaceSunken)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Kkb.hairline, lineWidth: 1)
                        )

                    Toggle(isOn: Binding(
                        get: { canRestrict && restrictToIngredients },
                        set: { restrictToIngredients = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use only these ingredients")
                                .kkbFont(.bodyLarge)
                                .foregroundStyle(canRestrict ? Kkb.textPrimary : Kkb.textSecondary)
                            Text(canRestrict
                                 ? "Build the whole week from this list alone — nothing else to buy."
                                 : "Add at least 3 ingredients to use this.")
                                .kkbFont(.bodySmall)
                                .foregroundStyle(Kkb.textSecondary)
                        }
                    }
                    .disabled(!canRestrict)
                    .padding(.top, 4)

                    if canRestrict && restrictToIngredients {
                        Text("We'll still assume you have the basics — salt, oil, ghee, everyday spices, onion, garlic and ginger.")
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                    }
                }

                Divider().overlay(Kkb.hairline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("I am in mood for".eyebrow)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.accentText)
                    Text("Pick one or more cuisines to bias the plan (optional).")
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(CuisineData.cuisines) { cuisine in
                            KkbChip(
                                title: cuisine.name,
                                isSelected: moods.contains(cuisine.name)
                            ) {
                                if moods.contains(cuisine.name) {
                                    moods.remove(cuisine.name)
                                } else {
                                    moods.insert(cuisine.name)
                                }
                            }
                        }
                    }
                }

                Text("Suggestions only fill empty slots — nothing you've already planned is replaced.")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
            }
        }
    }
}
