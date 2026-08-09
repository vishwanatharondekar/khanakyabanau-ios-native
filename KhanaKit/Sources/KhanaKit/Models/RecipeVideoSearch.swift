import Foundation

/// One YouTube result, already ranked server-side by
/// `lib/youtube-recipe-search.ts` (duration, engagement, title match, recency).
public struct RecipeVideoResult: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var channelTitle: String
    /// Pre-formatted "4:13", derived from the API's ISO-8601 duration.
    public var duration: String?
    public var thumbnailUrl: String?
    public var url: String

    public init(
        id: String,
        title: String,
        channelTitle: String,
        duration: String? = nil,
        thumbnailUrl: String? = nil,
        url: String
    ) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.duration = duration
        self.thumbnailUrl = thumbnailUrl
        self.url = url
    }
}

public struct RecipeVideoSearchPage: Hashable, Sendable {
    public var items: [RecipeVideoResult]
    public var nextPageToken: String?

    public init(items: [RecipeVideoResult] = [], nextPageToken: String? = nil) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
}

/// Which slot the video picker was opened for. `source` is carried straight into
/// analytics so we can tell a pick made from the week grid from one made on the
/// meal detail page.
public struct RecipeVideoContext: Hashable, Sendable, Identifiable {
    public var day: DayOfWeek
    public var mealType: MealType
    public var mealName: String
    public var weekStartDate: String
    /// The video already cached against this slot by the web app, if any.
    public var slotVideoUrl: String?
    /// `"week"` or `"meal_detail"`.
    public var source: String

    public var id: String { "\(weekStartDate)-\(day.key)-\(mealType.key)" }

    public init(
        day: DayOfWeek,
        mealType: MealType,
        mealName: String,
        weekStartDate: String,
        slotVideoUrl: String? = nil,
        source: String
    ) {
        self.day = day
        self.mealType = mealType
        self.mealName = mealName
        self.weekStartDate = weekStartDate
        self.slotVideoUrl = slotVideoUrl
        self.source = source
    }
}
