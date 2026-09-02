import KhanaKit
import SwiftUI
import UIKit
import XCTest
@testable import KhanaKyaBanau

/// The meal-detail page is a single `VStack` inside a vertical `ScrollView`, so
/// the widest thing in it sets the width of the whole page — and a vertical
/// `ScrollView` does not clip horizontally, it centres content that is too wide
/// and lets it hang off both edges. The hero photograph was doing exactly that
/// for some dishes and not others, which is what made it look arbitrary.
@MainActor
final class MealDetailLayoutTests: XCTestCase {

    /// iPhone 15/16/17 portrait — the device the report came from.
    private let screen: CGFloat = 393
    private let heroHeight: CGFloat = 280

    /// The width the layout system settles on when the view is offered `width` and
    /// as much height as it wants: what a vertical `ScrollView` proposes to its
    /// content.
    private func settledWidth<V: View>(_ view: V, offered width: CGFloat) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: 10_000))
            .width
    }

    /// Stands in for a dish photograph of a given pixel size — only its aspect
    /// ratio matters to layout.
    private func photo(_ width: Int, _ height: Int) -> Image {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: bitmap)
    }

    /// The regression, at the size that caused it: `Avocado_ada_pradaman_recipe.jpg`
    /// is 1600×966, and it is what the image pool matches to "Dadpe Pohe with fresh
    /// coconut".
    ///
    /// `scaledToFill` reports the size that *covers* what it was offered, so any
    /// photo wider than `screen / heroHeight` (≈1.4∶1) is scaled to the band's
    /// height instead and hands back `280 × aspect` — 464pt here, 71pt wider than
    /// the phone.
    func testAWidePhotoDoesNotWidenTheHeroBand() {
        let band = KkbFullBleedBand(height: heroHeight) {
            photo(1600, 966).resizable().scaledToFill()
        }
        XCTAssertEqual(
            settledWidth(band, offered: screen), screen, accuracy: 0.5,
            "a 1600×966 dish photo widened the hero band, and with it every section of the page below it"
        )
    }

    /// Squarer and taller photos always fitted — there the fill is width-driven, so
    /// the reported width is the offered width. This is why only some dishes broke,
    /// and it guards against a fix that contains the wide case by breaking the
    /// common one.
    func testTallerAndSquarerPhotosAlsoStayWithinTheBand() {
        for (width, height) in [(1080, 1350), (1200, 1200), (1600, 1200)] {
            let band = KkbFullBleedBand(height: heroHeight) {
                photo(width, height).resizable().scaledToFill()
            }
            XCTAssertEqual(
                settledWidth(band, offered: screen), screen, accuracy: 0.5,
                "\(width)×\(height) did not fit the band"
            )
        }
    }

    /// The other two photo surfaces on this page — the top-pick card and each
    /// search result — hold a `scaledToFill` thumbnail in a `ZStack` under an
    /// explicit `aspectRatio(_:contentMode: .fit)`, which sizes itself from the
    /// proposal and leaves the oversized child to be clipped. They were never part
    /// of the overflow; this is the assertion that says so, so that "wide photo on
    /// the meal-detail page" stays fixed at every one of them.
    func testTheVideoThumbnailsAreContainedByTheirAspectRatio() {
        let card = ZStack {
            photo(1600, 966).resizable().scaledToFill()
            Circle().fill(.black).frame(width: 46, height: 46)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        XCTAssertEqual(settledWidth(card, offered: screen), screen, accuracy: 0.5)
    }

    /// Why the band exists rather than sizing the photograph itself.
    ///
    /// This is the idiom that shipped. A *fixed* `frame(height:)` adopts its child's
    /// width when it is given no width, and `frame(maxWidth: .infinity)` floors at
    /// the child's width rather than clamping down to what was offered — so the
    /// 464pt travelled all the way up to the page. `clipped()` trims the drawing,
    /// never the layout.
    ///
    /// If this one ever fails, SwiftUI changed how a flexible frame sizes an
    /// oversized child and the band is no longer load-bearing.
    func testSizingThePhotographItselfIsWhatOverflowed() {
        let asShipped = photo(1600, 966).resizable().scaledToFill()
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
        XCTAssertEqual(
            settledWidth(asShipped, offered: screen), 464, accuracy: 1,
            "the shipped idiom no longer overflows — the band may be unnecessary"
        )
    }
}
