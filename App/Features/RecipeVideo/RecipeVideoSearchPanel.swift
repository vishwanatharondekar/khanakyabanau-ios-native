import KhanaKit
import SwiftUI

/// The search half of the recipe-video experience: the query row, then whatever
/// the search is currently doing — loading, failing, empty, or a list of results
/// to save.
///
/// One view for both surfaces that search. The picker sheet shows it under its
/// tabs; the meal detail page shows it in place of the old "no video yet" empty
/// state, so a dish with nothing saved lands on results rather than a dead end.
struct RecipeVideoSearchPanel: View {
    @Environment(\.app) private var env

    let model: RecipeVideoSearchModel
    /// Videos already on screen above the list — the saved picks, and the top pick
    /// — which the list must not offer to save a second time.
    var hiddenVideoIDs: Set<String> = []
    var isSaving: Bool
    var onSave: (RecipeVideoResult) -> Void

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Search for cooking videos…", text: $model.query)
                    .kkbFont(.bodyLarge)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.run(reset: true, env: env) } }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Kkb.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Kkb.hairline, lineWidth: 1)
                    )
                Button { Task { await model.run(reset: true, env: env) } } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Kkb.cream50)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Kkb.terracotta500))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }

            if model.isLoadingFirstPage {
                ProgressView().tint(Kkb.terracotta500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if let errorMessage = model.errorMessage {
                InlineErrorCard(message: errorMessage) {
                    Task { await model.run(reset: true, env: env) }
                }
            } else if model.results.isEmpty {
                KkbEmptyState(
                    script: "No videos found",
                    caption: "No videos found for \"\(model.query)\" — try a different search.",
                    alignment: .leading
                )
                .padding(.vertical, 20)
            } else {
                ForEach(model.results.filter { !hiddenVideoIDs.contains($0.id) }) { result in
                    RecipeVideoResultCard(
                        result: result,
                        isExpanded: model.expandedVideoID == result.id,
                        isSaving: isSaving,
                        onTogglePreview: { model.toggleExpanded(result.id) },
                        onSave: { onSave(result) }
                    )
                }

                if model.canLoadMore {
                    Button {
                        Task { await model.run(reset: false, env: env) }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSearching {
                                ProgressView().controlSize(.small).tint(Kkb.accentText)
                            }
                            Text(model.isSearching ? "Loading…" : "Load more")
                        }
                        .kkbFont(.labelLarge)
                        .foregroundStyle(Kkb.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Kkb.terracottaSurface.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSearching)
                }
            }
        }
    }
}

/// One search result: a thumbnail that expands in place into a player, the title
/// and channel, and a Save.
struct RecipeVideoResultCard: View {
    var result: RecipeVideoResult
    var isExpanded: Bool
    var isSaving: Bool
    var onTogglePreview: () -> Void
    var onSave: () -> Void

    var body: some View {
        PaperCard(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onTogglePreview) {
                    ZStack {
                        if isExpanded {
                            YouTubePreview(videoID: result.id)
                        } else if let thumb = result.thumbnailUrl, let url = URL(string: thumb) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Kkb.creamWell
                            }
                            Circle()
                                .fill(.black.opacity(0.55))
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.white)
                                        .font(.system(size: 17))
                                )
                        } else {
                            Kkb.creamWell
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(result.title)")

                Text(result.title)
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(result.channelTitle)
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                        .lineLimit(1)
                    if let duration = result.duration {
                        Text("· \(duration)")
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                    }
                    Spacer()
                    Button(action: onSave) {
                        Text(isSaving ? "Saving…" : "Save")
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(Kkb.cream50)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Kkb.terracotta500))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
        }
    }
}
