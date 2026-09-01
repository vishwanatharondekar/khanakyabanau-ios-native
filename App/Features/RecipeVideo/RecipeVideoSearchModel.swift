import KhanaKit
import SwiftUI

/// A recipe-video search in progress: the query, its results, and the paging
/// around them.
///
/// Shared by the picker sheet and the meal detail page so both find videos the
/// same way — including the main-dish lookup, which has to happen before the first
/// query and so cannot live in either view. Sharing the model also shares
/// `RecipeVideoRepository`'s per-query cache, which matters: the endpoint allows
/// only ~99 uncached searches a day across every user of the product, so two
/// screens searching the same dish must not cost two queries.
@MainActor
@Observable
final class RecipeVideoSearchModel {
    var query = ""
    private(set) var results: [RecipeVideoResult] = []
    private(set) var nextPageToken: String?
    private(set) var isSearching = false
    /// A main-dish lookup is in flight; the search waits for it rather than
    /// spending a query on the whole plate.
    private(set) var isIdentifying = false
    private(set) var errorMessage: String?
    /// Only one preview is live at a time — several WKWebViews on screen together
    /// is a real memory and battery cost.
    var expandedVideoID: String?

    /// The meal the opening search was run for. A screen that redraws, or is
    /// re-entered, must not spend a second query on the same dish.
    private var startedFor: String?

    /// Something is on its way and there is nothing to show yet.
    var isLoadingFirstPage: Bool { (isIdentifying || isSearching) && results.isEmpty }

    var canLoadMore: Bool { nextPageToken != nil }

    /// The opening search for a meal.
    ///
    /// Narrowed before anything is searched for: this is the search the user judges
    /// the feature by, and "Gujarati dal, steamed rice, bhindi nu shaak and phulka"
    /// returns thali compilations rather than a dal recipe. Short names are already
    /// a dish, and a lookup that finds nothing to narrow falls back to the name as
    /// written.
    func start(mealName: String, env: AppEnvironment) async {
        guard startedFor != mealName else { return }
        startedFor = mealName

        if RecipeVideoKeys.needsMainDishLookup(mealName) {
            isIdentifying = true
            let dish = await env.ai.mainDish(for: mealName)
            isIdentifying = false
            // The user may have started typing while the lookup was in flight;
            // their query wins.
            if query.isEmpty { query = dish ?? mealName }
        } else if query.isEmpty {
            query = mealName
        }
        await run(reset: true, env: env)
    }

    func run(reset: Bool, env: AppEnvironment) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
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
            errorMessage = error.userMessage(fallback: "Could not search for videos right now.")
        } catch {
            errorMessage = "Could not search for videos right now."
        }
        isSearching = false
    }

    func toggleExpanded(_ videoID: String) {
        expandedVideoID = expandedVideoID == videoID ? nil : videoID
    }
}
