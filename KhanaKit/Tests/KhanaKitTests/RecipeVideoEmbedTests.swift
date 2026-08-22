import XCTest
@testable import KhanaKit

/// YouTube refuses to play an embed that arrives without a referer: the page it
/// serves carries `"Error 153"` / `"Video player configuration error"` instead of
/// a player. Navigating a web view straight at `youtube.com/embed/…` sends no
/// referer, so the fix is to load an iframe from a page of our own origin — which
/// is what the web app does, and why it has never hit this.
final class RecipeVideoEmbedTests: XCTestCase {

    func testEmbedHTMLFramesTheVideo() {
        let html = RecipeVideos.embedHTML(videoID: "abc123XYZ_-")

        XCTAssertTrue(html.contains("<iframe"), html)
        XCTAssertTrue(
            html.contains(RecipeVideos.embedURL(videoID: "abc123XYZ_-")),
            "The iframe must point at the embed URL: \(html)"
        )
    }

    /// Without this the player takes over the whole screen on iPhone the moment
    /// it starts, rather than staying in the card it was expanded from.
    func testEmbedHTMLPlaysInline() {
        XCTAssertTrue(RecipeVideos.embedHTML(videoID: "abc123XYZ_-").contains("playsinline=1"))
    }

    /// A percentage height only resolves against a sized ancestor. With `html`
    /// and `body` left at auto height the frame collapsed to its intrinsic size —
    /// 343pt inside a 432pt 16:9 slot — and the player letterboxed itself into
    /// what was left.
    func testEmbedHTMLFillsItsContainer() {
        let html = RecipeVideos.embedHTML(videoID: "abc123XYZ_-")
        let css = html.replacingOccurrences(of: " ", with: "")

        XCTAssertTrue(
            css.contains("html,body{") && css.contains("height:100%"),
            "The page itself has to be full height or the frame cannot be: \(html)"
        )
        XCTAssertTrue(
            css.contains("position:absolute"),
            "The frame should fill the page rather than flow in it: \(html)"
        )
    }

    /// The origin the iframe is framed from. It has to be a real site that embeds
    /// these videos, not youtube.com itself.
    func testEmbedOriginIsTheProductSite() {
        XCTAssertEqual(RecipeVideos.embedOrigin, "https://www.khanakyabanau.in")
    }
}
