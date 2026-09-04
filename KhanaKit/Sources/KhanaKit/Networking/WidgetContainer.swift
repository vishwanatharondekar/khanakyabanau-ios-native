import CryptoKit
import Foundation

/// The shared directory the app writes into and the widget extension reads from.
///
/// Two processes, one App Group. Constructed from an explicit root so the store
/// is testable against a temporary directory — the failure modes worth pinning
/// here are filesystem ones, and mocking a filesystem to test filesystem code
/// tests the mock.
public struct WidgetContainer: Sendable {

    /// Must match the App Group on both the app and the extension targets, and
    /// the entitlements files behind `KKB_ENTITLEMENTS` / `KKB_WIDGET_ENTITLEMENTS`.
    public static let appGroupID = "group.in.khanakyabanau.app"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `nil` when the App Group is not provisioned — which is the normal state on
    /// a free Apple ID, where the entitlement is deliberately absent so the app
    /// still installs. Callers treat it exactly as they treat a missing snapshot.
    public static func shared(
        appGroupID: String = WidgetContainer.appGroupID,
        fileManager: FileManager = .default
    ) -> WidgetContainer? {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return WidgetContainer(root: url)
    }

    public var snapshotURL: URL {
        root.appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }

    public var thumbnailsDirectory: URL {
        root.appendingPathComponent("widget-thumbnails", isDirectory: true)
    }

    public func thumbnailURL(key: String) -> URL {
        thumbnailsDirectory.appendingPathComponent(key, isDirectory: false)
    }
}

/// Reading and writing the snapshot and its images.
///
/// Every read returns an optional rather than throwing. The extension has no
/// useful response to an error: a widget that renders a complaint where it could
/// render an invitation is a worse widget, so absence and corruption both fall
/// through to the same "Tap to set up" shell.
public enum WidgetSnapshotStore {

    public static func write(_ snapshot: WidgetSnapshot, to container: WidgetContainer) throws {
        try FileManager.default.createDirectory(
            at: container.root, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        // Atomic: the extension may be reading while the app writes, and a
        // half-written JSON file is indistinguishable from a corrupt one.
        try data.write(to: container.snapshotURL, options: .atomic)
    }

    public static func read(from container: WidgetContainer) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: container.snapshotURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func writeThumbnail(
        _ data: Data, key: String, to container: WidgetContainer
    ) throws {
        try FileManager.default.createDirectory(
            at: container.thumbnailsDirectory, withIntermediateDirectories: true
        )
        try data.write(to: container.thumbnailURL(key: key), options: .atomic)
    }

    public static func thumbnailData(key: String, in container: WidgetContainer) -> Data? {
        try? Data(contentsOf: container.thumbnailURL(key: key))
    }

    /// Delete cached images no longer referenced by the current snapshot.
    ///
    /// The App Group container is never cleaned by the system, so without this a
    /// plan edited daily grows an image cache without bound.
    public static func pruneThumbnails(keeping keys: Set<String>, in container: WidgetContainer) {
        let manager = FileManager.default
        guard let existing = try? manager.contentsOfDirectory(
            at: container.thumbnailsDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for url in existing where !keys.contains(url.lastPathComponent) {
            try? manager.removeItem(at: url)
        }
    }

    /// A stable file name for a remote image URL.
    ///
    /// Hashed rather than derived from the URL's path: Instamart-style CDN paths
    /// collide on basename, and a key that changed between writes would
    /// re-download every image on every refresh and defeat the cache entirely.
    public static func thumbnailKey(forImageURL url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }
}
