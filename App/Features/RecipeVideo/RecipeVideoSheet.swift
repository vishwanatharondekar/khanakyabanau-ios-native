import KhanaKit
import SwiftUI
import UIKit
import WebKit

/// Find and save a recipe video for a dish.
///
/// Two tabs — search and paste — over a hero showing whatever is already resolved
/// for this dish. Saving stores against the **dish name**, not the slot, so the
/// pick follows the dish into future weeks.
struct RecipeVideoSheet: View {
    @Environment(\.app) private var env
    @Environment(\.dismiss) private var dismiss

    var context: RecipeVideoContext
    var onDismiss: () -> Void

    @State private var tab = 0
    /// The search itself, shared with the meal detail page's inline search.
    @State private var search = RecipeVideoSearchModel()
    @State private var pastedURL = ""
    @State private var pasteError: String?
    @State private var isSaving = false
    @State private var toast: String?
    /// The chip the user tapped, if it is still among the matches.
    @State private var selectedSavedKey: String?
    @State private var isRemoving = false
    @Namespace private var segmentNamespace

    /// Every saved pick whose dish this meal names, most specific first. A plate
    /// can name several dishes the user has saved videos for, which is why this is
    /// a list and the hero is one of a set.
    private var savedMatches: [SavedVideoMatch] {
        RecipeVideoKeys.matchSavedVideos(mealName: context.mealName, videoURLs: env.videos.videoURLs)
    }

    /// The match on show: the chip the user tapped as long as it survived a
    /// removal, otherwise the most specific one.
    private var selectedMatch: SavedVideoMatch? {
        if let selectedSavedKey,
           let match = savedMatches.first(where: { $0.key == selectedSavedKey }) {
            return match
        }
        return savedMatches.first
    }

    /// The user's own saved pick for this meal, resolved by dish — a video filed
    /// under one of a plate's dishes is still their pick for the plate.
    private var savedURL: String? { selectedMatch?.url }

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    savedMatchChips
                    hero

                    SegmentedTabs(
                        options: [
                            .init("Search videos", systemImage: "magnifyingglass"),
                            .init("Paste URL", systemImage: "link"),
                        ],
                        selection: $tab,
                        namespace: segmentNamespace
                    )

                    if tab == 0 { searchPanel } else { pastePanel }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDragIndicator(.visible)
        .kkbToast($toast)
        .task {
            await env.videos.ensureLoaded()
            await search.start(mealName: context.mealName, env: env)
        }
        .onDisappear { onDismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(context.day.displayName) · \(context.mealType.displayName)".eyebrow)
                .kkbFont(.sectionLabel)
                .tracking(4)
                .foregroundStyle(Kkb.accentText)
            Text(context.mealName)
                .kkbFont(.displayLarge)
                .foregroundStyle(Kkb.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One chip per dish of this meal that already has a saved video. Tapping one
    /// moves the hero, the way the web app modal's chips do. Three at most: past
    /// that the row costs more room than the choice is worth.
    @ViewBuilder
    private var savedMatchChips: some View {
        if savedMatches.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(savedMatches.prefix(3), id: \.key) { match in
                        let isSelected = match.key == selectedMatch?.key
                        Button {
                            selectedSavedKey = match.key
                        } label: {
                            Text(match.key)
                                .kkbFont(.labelLarge)
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? Kkb.sageText : Kkb.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(isSelected ? Kkb.sageSurface : Kkb.surfaceSunken)
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        isSelected ? Kkb.sageText.opacity(0.35) : Kkb.hairline,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Drops the pick on show, by the key it is filed under — a dish, which is not
    /// necessarily this meal's name. Naming it is the point: without that, Remove
    /// would be removing something the user cannot see.
    @ViewBuilder
    private var removeSavedRow: some View {
        if let match = selectedMatch {
            HStack(spacing: 10) {
                Text("SAVED · \(match.key)".uppercased())
                    .kkbFont(.sectionLabel)
                    .tracking(2)
                    .foregroundStyle(Kkb.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    Task { await removeSelected(match) }
                } label: {
                    Text(isRemoving ? "Removing…" : "Remove")
                        .kkbFont(.labelLarge)
                        .underline()
                        .foregroundStyle(Kkb.terracotta500)
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let savedURL {
            VStack(alignment: .leading, spacing: 10) {
                heroCard(
                    tag: "YOUR SAVED RECIPE",
                    tagTint: Kkb.sageText,
                    tagFill: Kkb.sageSurface,
                    url: savedURL,
                    caption: "Replace it by saving another result or pasting a new link."
                )
                removeSavedRow
            }
        } else if let slot = context.slotVideoUrl, !slot.isEmpty {
            heroCard(
                tag: "TOP PICK",
                tagTint: Kkb.marigoldText,
                tagFill: Kkb.marigoldSurface,
                url: slot,
                caption: "Preview it below, then save it to keep it for this dish."
            )
        }
    }

    private func heroCard(
        tag: String,
        tagTint: Color,
        tagFill: Color,
        url: String,
        caption: String
    ) -> some View {
        PaperCard(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tag)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(tagTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tagFill))

                if let videoID = RecipeVideos.videoID(from: url) {
                    YouTubePreview(videoID: videoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text(caption)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)

                Button {
                    guard let target = URL(string: url) else { return }
                    env.analytics.track(
                        AnalyticsEvents.Video.play,
                        category: AnalyticsEvents.Category.videoManagement,
                        parameters: [
                            AnalyticsProperties.mealName: context.mealName,
                            AnalyticsProperties.source: "picker_hero",
                            AnalyticsProperties.videoURL: url,
                        ]
                    )
                    UIApplication.shared.open(target)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Watch on YouTube").kkbFont(.labelLarge)
                    }
                    .foregroundStyle(Kkb.cream50)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Kkb.terracotta500))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Search

    private var searchPanel: some View {
        RecipeVideoSearchPanel(
            model: search,
            hiddenVideoIDs: savedVideoIDs,
            isSaving: isSaving,
            onSave: { result in
                Task { await save(url: result.url, source: "search_result") }
            }
        )
    }

    // MARK: - Paste

    private var pastePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste a YouTube link".eyebrow)
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.accentText)

            TextField("https://youtube.com/watch?v=…", text: $pastedURL)
                .kkbFont(.bodyMedium)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Kkb.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Kkb.hairline, lineWidth: 1)
                )

            if let pasteError {
                Text(pasteError)
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.terracotta600)
            }

            KkbPrimaryButton(
                title: "Save video",
                isLoading: isSaving,
                isEnabled: !pastedURL.isEmpty
            ) {
                Task {
                    let trimmed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard RecipeVideos.isValidYouTubeURL(trimmed),
                          RecipeVideos.videoID(from: trimmed) != nil else {
                        pasteError = "Please enter a valid YouTube URL"
                        return
                    }
                    pasteError = nil
                    await save(url: trimmed, source: "manual_url")
                }
            }
        }
    }

    // MARK: - Actions

    /// Video ids this meal already has saved, hero included, so the results list
    /// doesn't offer to save something that is already saved.
    private var savedVideoIDs: Set<String> {
        Set(savedMatches.compactMap { RecipeVideos.videoID(from: $0.url) })
    }

    /// Drops one saved pick by the key it is filed under, not by the meal name.
    /// The repository re-publishes the map, so the hero falls to the next match
    /// on its own.
    private func removeSelected(_ match: SavedVideoMatch) async {
        isRemoving = true
        do {
            try await env.videos.clear(recipeName: match.key)
            selectedSavedKey = nil
            toast = "Removed"
        } catch {
            toast = "Failed to remove the video"
        }
        isRemoving = false
    }

    private func save(url: String, source: String) async {
        isSaving = true
        do {
            try await env.videos.saveForMeal(mealName: context.mealName, videoUrl: url)
            env.analytics.track(
                AnalyticsEvents.Video.addURL,
                category: AnalyticsEvents.Category.videoManagement,
                parameters: [
                    AnalyticsProperties.day: context.day.key,
                    AnalyticsProperties.mealType: context.mealType.key,
                    AnalyticsProperties.mealName: context.mealName,
                    AnalyticsProperties.weekStart: context.weekStartDate,
                    AnalyticsProperties.source: source,
                    AnalyticsProperties.videoURL: url,
                ]
            )
            toast = "Recipe video saved!"
            pastedURL = ""
        } catch {
            toast = "Failed to save recipe video"
        }
        isSaving = false
    }
}

/// An inline YouTube player. `WKWebView` is the only way to embed YouTube on iOS,
/// and it stays scoped to a single expanded card at a time.
///
/// The player is framed from a page of our own origin rather than navigated to
/// directly: a bare navigation to `youtube.com/embed/…` carries no referer, and
/// YouTube answers that with "Error 153 / Video player configuration error"
/// instead of a video. See `RecipeVideos.embedOrigin`.
struct YouTubePreview: UIViewRepresentable {
    var videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Track what was asked for rather than comparing `webView.url`: the loaded
        // page is now the base origin, and the player rewrites its own URL while
        // running, so neither reads back as "this video is already showing".
        guard context.coordinator.loadedVideoID != videoID else { return }
        context.coordinator.loadedVideoID = videoID
        webView.loadHTMLString(
            RecipeVideos.embedHTML(videoID: videoID),
            baseURL: URL(string: RecipeVideos.embedOrigin)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedVideoID: String?
    }
}
