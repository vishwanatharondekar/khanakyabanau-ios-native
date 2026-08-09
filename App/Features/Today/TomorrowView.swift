import KhanaKit
import SwiftUI

/// The full Tomorrow screen: everything to start tonight, then tomorrow's menu.
struct TomorrowView: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    let model: TodayViewModel
    var onOpenMeal: (DayOfWeek, MealType) -> Void
    var onOpenVideo: (RecipeVideoContext) -> Void

    var body: some View {
        content(model)
            .background(KkbBackground { Color.clear })
            .navigationBarBackButtonHidden()
            // Always refresh on entry, matching Android's
            // `LaunchedEffect(Unit) { viewModel.refresh() }` — edits made on the
            // meal detail page should be reflected on the way back.
            .task { await model.refresh() }
    }

    @ViewBuilder
    private func content(_ model: TodayViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(model)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let error = model.errorMessage {
                        InlineErrorCard(message: error) {
                            Task { await model.refresh(showSpinner: true) }
                        }
                    }

                    if !model.tomorrowPrep.isEmpty {
                        PrepTonightBox(items: model.tomorrowPrep, isCompact: false)
                        NotificationOptIn()
                    }

                    Text("ON THE MENU")
                        .kkbFont(.sectionLabel)
                        .tracking(4)
                        .foregroundStyle(Kkb.accentText)
                        .padding(.top, 4)

                    PaperCard(cornerRadius: 22, padding: 16) {
                        let planned = model.enabledTypes.filter { !model.tomorrow.meals[$0].isEmpty }
                        if planned.isEmpty {
                            KkbEmptyState(
                                script: "— a blank page awaits —",
                                caption: "No dishes written for tomorrow yet",
                                alignment: .leading
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(planned) { type in
                                    TomorrowMealRow(
                                        type: type,
                                        meal: model.tomorrow.meals[type],
                                        isResolvingImages: model.isResolvingImages,
                                        onTap: { onOpenMeal(model.tomorrow.day, type) }
                                    )
                                    if type != planned.last {
                                        Divider().overlay(Kkb.sageSurface)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func topBar(_ model: TodayViewModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Kkb.ink700)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Kkb.cream100))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("COMING UP")
                    .kkbFont(.sectionLabel)
                    .tracking(5)
                    .foregroundStyle(Kkb.sageText)
                Text("Tomorrow · \(model.tomorrow.day.displayName)")
                    .kkbFont(.displayMedium)
                    .italic()
                    .foregroundStyle(Kkb.textPrimary)
                Text(model.tomorrow.date.isoString)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
