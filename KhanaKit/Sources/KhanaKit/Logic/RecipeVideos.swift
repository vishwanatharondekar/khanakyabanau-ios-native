import Foundation

/// YouTube URL helpers for recipe videos, ported from the web app's
/// `lib/video-url-utils.ts` so all three clients agree on keys, hosts and fallbacks.
public enum RecipeVideos {

    /// Key into the user's recipe→video map. The server normalizes the same way on
    /// write (`api/auth/video-urls` lowercases and trims), so lookups done here
    /// match entries saved from any client.
    public static func normalizeKey(_ dishName: String) -> String {
        dishName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The video for a meal: the user's dish-keyed pick wins (it's a deliberate
    /// choice and carries across weeks), then whatever the web app's meal-detail
    /// page cached against this slot. Single source of the priority rule — chips,
    /// stamps, detail page and the PDF all resolve through here.
    public static func url(in videoUrls: [String: String]?, for meal: Meal) -> String? {
        if let saved = videoUrls?[normalizeKey(meal.name)], !saved.isEmpty { return saved }
        if let slot = meal.videoUrl, !slot.isEmpty { return slot }
        return nil
    }

    /// Hosts accepted for pasted links, plus `m.youtube.com` because pastes often
    /// come from the YouTube app's share sheet.
    private static let youTubeHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be",
        "www.youtu.be",
    ]

    public static func isValidYouTubeURL(_ url: String) -> Bool {
        guard let components = URLComponents(
            string: url.trimmingCharacters(in: .whitespacesAndNewlines)
        ), let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased()
        else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return youTubeHosts.contains(host)
    }

    /// The web app's extraction regex with `shorts/` added — video ids are 11 chars
    /// across `watch?v=`, `youtu.be`, `/embed/`, `/v/` and `/shorts/`.
    private static let videoIDRegex = try! NSRegularExpression(
        pattern: #"(?:youtube\.com/(?:[^/]+/.+/|(?:v|e(?:mbed)?|shorts)/|.*[?&]v=)|youtu\.be/)([^"&?/\s]{11})"#
    )

    public static func videoID(from url: String) -> String? {
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = videoIDRegex.firstMatch(in: url, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: url)
        else { return nil }
        return String(url[captured])
    }

    public static func embedURL(videoID: String) -> String {
        "https://www.youtube.com/embed/\(videoID)"
    }

    public static func thumbnailURL(videoID: String) -> String {
        "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
    }

    private static let durationRegex = try! NSRegularExpression(
        pattern: #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$"#
    )

    /// ISO-8601 duration from the search API (`"PT4M13S"`) → `"4:13"`. Nil in, nil
    /// out; an all-zero duration is also nil, since YouTube reports live streams
    /// that way and a "0:00" chip would be a lie.
    public static func formatDuration(_ iso: String?) -> String? {
        guard let iso, !iso.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let range = NSRange(iso.startIndex..<iso.endIndex, in: iso)
        guard let match = durationRegex.firstMatch(in: iso, range: range) else { return nil }

        func group(_ index: Int) -> Int {
            guard let r = Range(match.range(at: index), in: iso) else { return 0 }
            return Int(iso[r]) ?? 0
        }
        let hours = group(1), minutes = group(2), seconds = group(3)
        guard hours != 0 || minutes != 0 || seconds != 0 else { return nil }
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
