import Foundation

/// Dish photography lives on CloudFront; `POST /api/image-mapping` returns either
/// an absolute URL or a bare file name, so every value has to go through here
/// before it reaches an image view.
public enum MealImageURLs {
    public static let base = "https://d3rj590miwbz96.cloudfront.net/meals-data/images/"

    /// Absolute URLs pass through untouched; anything else is treated as a path
    /// relative to `base`. Mirrors `resolveMealImageSrc` on web and
    /// `MealImageUrls.absolutize` on Android.
    public static func absolutize(_ relative: String?) -> String? {
        guard let relative, !relative.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        if relative.hasPrefix("http://") || relative.hasPrefix("https://") { return relative }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let trimmedPath = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        return "\(trimmedBase)/\(trimmedPath)"
    }
}

/// Generates the anonymous device id used to create and re-find a guest account.
///
/// The format matters: the server's `isGuestUser` check is
/// `userId.startsWith('guest_')`, and the Firestore document id *is* this string.
public enum GuestDeviceID {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// `guest_{millisBase36}_{9 random alphanumerics}` — same shape the web client
    /// and Android produce.
    public static func generate(now: Date = Date()) -> String {
        let millis = Int(now.timeIntervalSince1970 * 1000)
        let timestamp = String(millis, radix: 36)
        var suffix = ""
        for _ in 0..<9 { suffix.append(alphabet.randomElement()!) }
        return "guest_\(timestamp)_\(suffix)"
    }

    public static func isGuest(_ userId: String) -> Bool { userId.hasPrefix("guest_") }
}
