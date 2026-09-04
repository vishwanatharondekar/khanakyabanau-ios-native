import XCTest
@testable import KhanaKit

/// The store is the only thing on both sides of the process boundary, so these
/// run against a real temporary directory rather than a mock — the failure modes
/// that matter here are filesystem ones.
final class WidgetSnapshotStoreTests: XCTestCase {

    private var container: WidgetContainer!
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = WidgetContainer(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func snapshot(_ name: String = "Poha") -> WidgetSnapshot {
        WidgetSnapshot(
            isAuthenticated: true,
            writtenAt: Date(timeIntervalSince1970: 1_780_000_000),
            days: [
                WidgetDay(day: .friday, date: "2026-09-04", meals: [
                    WidgetMeal(type: .breakfast, name: name, calories: nil,
                               thumbnailKey: nil, prep: nil),
                ]),
            ]
        )
    }

    func testWritesThenReadsBack() throws {
        try WidgetSnapshotStore.write(snapshot(), to: container)
        XCTAssertEqual(WidgetSnapshotStore.read(from: container), snapshot())
    }

    /// A widget that renders an error where it could render an invitation is a
    /// worse widget, so absence is `nil` and never a throw.
    func testReadingWhenNothingIsThereReturnsNil() {
        XCTAssertNil(WidgetSnapshotStore.read(from: container))
    }

    func testReadingGarbageReturnsNilRatherThanThrowing() throws {
        try Data("not json".utf8).write(to: container.snapshotURL)
        XCTAssertNil(WidgetSnapshotStore.read(from: container))
    }

    func testWritingTwiceReplacesRatherThanAppends() throws {
        try WidgetSnapshotStore.write(snapshot("Poha"), to: container)
        try WidgetSnapshotStore.write(snapshot("Upma"), to: container)

        XCTAssertEqual(WidgetSnapshotStore.read(from: container)?.days[0].meals[0].name, "Upma")
    }

    func testThumbnailRoundTrips() throws {
        let key = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/poha.jpg")
        try WidgetSnapshotStore.writeThumbnail(Data([0x01, 0x02]), key: key, to: container)

        XCTAssertEqual(WidgetSnapshotStore.thumbnailData(key: key, in: container), Data([0x01, 0x02]))
    }

    func testThumbnailDataIsNilWhenAbsent() {
        XCTAssertNil(WidgetSnapshotStore.thumbnailData(key: "nope.jpg", in: container))
    }

    /// The key has to be stable — a new key per write would re-download every image
    /// on every refresh and defeat the point of caching them at all.
    func testThumbnailKeyIsStableForTheSameURL() {
        let a = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/a.jpg")
        let b = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/a.jpg")
        XCTAssertEqual(a, b)
    }

    func testThumbnailKeysDifferByURL() {
        XCTAssertNotEqual(
            WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/a.jpg"),
            WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/b.jpg")
        )
    }

    /// The container is shared and never cleaned by the system, so a plan edited
    /// daily would otherwise grow an image cache without bound.
    func testPruningRemovesThumbnailsNotInTheKeepSet() throws {
        let keep = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/keep.jpg")
        let drop = WidgetSnapshotStore.thumbnailKey(forImageURL: "https://example.test/drop.jpg")
        try WidgetSnapshotStore.writeThumbnail(Data([0x01]), key: keep, to: container)
        try WidgetSnapshotStore.writeThumbnail(Data([0x02]), key: drop, to: container)

        WidgetSnapshotStore.pruneThumbnails(keeping: [keep], in: container)

        XCTAssertNotNil(WidgetSnapshotStore.thumbnailData(key: keep, in: container))
        XCTAssertNil(WidgetSnapshotStore.thumbnailData(key: drop, in: container))
    }

    func testPruningAnEmptyDirectoryIsHarmless() {
        WidgetSnapshotStore.pruneThumbnails(keeping: [], in: container)
        XCTAssertNil(WidgetSnapshotStore.thumbnailData(key: "nope.jpg", in: container))
    }
}
