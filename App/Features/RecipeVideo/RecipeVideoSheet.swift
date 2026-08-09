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
    @State private var query = ""
    @State private var results: [RecipeVideoResult] = []
    @State private var nextPageToken: String?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var expandedVideoID: String?
    @State private var pastedURL = ""
    @State private var pasteError: String?
    @State private var isSaving = false
    @State private var toast: String?
    @Namespace private var segmentNamespace

    private var savedURL: String? {
        env.videos.hasSavedPick(for: context.mealName)
            ? env.videos.videoURLs?[RecipeVideos.normalizeKey(context.mealName)]
            : nil
    }

    var body: some View {
        KkbBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
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
            if query.isEmpty {
                query = context.mealName
                await runSearch(reset: true)
            }
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

    @ViewBuilder
    private var hero: some View {
        if let savedURL {
            heroCard(
                tag: "YOUR SAVED RECIPE",
                tagTint: Kkb.sageText,
                tagFill: Kkb.sageSurface,
                url: savedURL,
                caption: "Replace it by saving another result or pasting a new link."
            )
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Search for cooking videos…", text: $query)
                    .kkbFont(.bodyLarge)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch(reset: true) } }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Kkb.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Kkb.hairline, lineWidth: 1)
                    )
                Button { Task { await runSearch(reset: true) } } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Kkb.cream50)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Kkb.terracotta500))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }

            if isSearching, results.isEmpty {
                ProgressView().tint(Kkb.terracotta500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if let searchError {
                InlineErrorCard(message: searchError) {
                    Task { await runSearch(reset: true) }
                }
            } else if results.isEmpty {
                KkbEmptyState(
                    script: "No videos found",
                    caption: "No videos found for \"\(query)\" — try a different search.",
                    alignment: .leading
                )
                .padding(.vertical, 20)
            } else {
                ForEach(results) { result in
                    resultCard(result)
                }

                if nextPageToken != nil {
                    Button {
                        Task { await runSearch(reset: false) }
                    } label: {
                        HStack(spacing: 8) {
                            if isSearching {
                                ProgressView().controlSize(.small).tint(Kkb.accentText)
                            }
                            Text(isSearching ? "Loading…" : "Load more")
                        }
                        .kkbFont(.labelLarge)
                        .foregroundStyle(Kkb.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Kkb.terracottaSurface.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearching)
                }
            }
        }
    }

    private func resultCard(_ result: RecipeVideoResult) -> some View {
        PaperCard(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    // Only one preview is live at a time — several WKWebViews on
                    // screen together is a real memory and battery cost.
                    expandedVideoID = expandedVideoID == result.id ? nil : result.id
                } label: {
                    ZStack {
                        if expandedVideoID == result.id {
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
                    Button {
                        Task { await save(url: result.url, source: "search_result") }
                    } label: {
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

    private func runSearch(reset: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        if reset {
            results = []
            nextPageToken = nil
            expandedVideoID = nil
        }
        do {
            let page = try await env.videos.search(
                query: trimmed, pageToken: reset ? nil : nextPageToken
            )
            results.append(contentsOf: page.items)
            nextPageToken = page.nextPageToken
        } catch let error as APIError {
            searchError = error.userMessage(fallback: "Could not search for videos right now.")
        } catch {
            searchError = "Could not search for videos right now."
        }
        isSearching = false
    }

    private func save(url: String, source: String) async {
        isSaving = true
        do {
            try await env.videos.save(recipeName: context.mealName, videoUrl: url)
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
        guard let url = URL(string: RecipeVideos.embedURL(videoID: videoID)),
              webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
