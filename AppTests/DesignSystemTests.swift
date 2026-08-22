import KhanaKit
import SwiftUI
import UIKit
import XCTest
@testable import KhanaKyaBanau

/// Dark mode is an iOS-only addition — neither Android nor the web app has one —
/// so nothing upstream proves it works. These resolve the semantic colours against
/// real trait collections, which is the claim itself rather than a proxy for it.
@MainActor
final class DesignSystemTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func rgba(_ color: Color, _ traits: UITraitCollection) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func luminance(_ color: Color, _ traits: UITraitCollection) -> CGFloat {
        let (r, g, b, _) = rgba(color, traits)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func assertAdapts(
        _ color: Color,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let l = rgba(color, light)
        let d = rgba(color, dark)
        XCTAssertFalse(
            l == d,
            "\(name) resolves identically in light and dark — it is not adaptive",
            file: file, line: line
        )
    }

    /// WCAG relative luminance. The weighted average above answers "did this get
    /// darker"; a contrast *ratio* needs the gamma-expanded channels or it flatters
    /// mid-tones badly, which is exactly where the merged text was.
    private func relativeLuminance(_ color: Color, _ traits: UITraitCollection) -> CGFloat {
        let (r, g, b, _) = rgba(color, traits)
        func expand(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * expand(r) + 0.7152 * expand(g) + 0.0722 * expand(b)
    }

    private func contrast(_ text: Color, on ground: Color, _ traits: UITraitCollection) -> CGFloat {
        let a = relativeLuminance(text, traits)
        let b = relativeLuminance(ground, traits)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testSemanticColoursAdaptBetweenAppearances() {
        assertAdapts(Kkb.background, "background")
        assertAdapts(Kkb.surface, "surface")
        assertAdapts(Kkb.surfaceSunken, "surfaceSunken")
        assertAdapts(Kkb.textPrimary, "textPrimary")
        assertAdapts(Kkb.textSecondary, "textSecondary")
        assertAdapts(Kkb.hairline, "hairline")
        assertAdapts(Kkb.accent, "accent")
        assertAdapts(Kkb.marigoldSurface, "marigoldSurface")
        assertAdapts(Kkb.sageSurface, "sageSurface")
        assertAdapts(Kkb.terracottaSurface, "terracottaSurface")
        assertAdapts(Kkb.creamWell, "creamWell")
    }

    /// The regression that prompted these: tinted chips paired a *fixed* pale
    /// ground with text that flips to a pale hue in dark mode, so calorie badges,
    /// prep badges and notice cards came out light-on-light. Both halves of every
    /// pair have to move together.
    ///
    /// The floor is 4.0 rather than WCAG AA's 4.5 because the light values are
    /// inherited byte-for-byte from Android and the web app — terracotta600 on
    /// terracotta100 lands at 4.3, and changing it would fork the brand across
    /// three clients to fix an appearance neither of the others has.
    func testTintedChipsKeepTheirTextLegible() {
        let pairs: [(text: Color, ground: Color, name: String)] = [
            (Kkb.marigoldText, Kkb.marigoldSurface, "calorie badge / prep notice"),
            (Kkb.sageText, Kkb.sageSurface, "prep-ahead badge"),
            (Kkb.accentText, Kkb.terracottaSurface, "terracotta chip"),
            (Kkb.textPrimary, Kkb.surface, "body text on a card"),
            (Kkb.textSecondary, Kkb.surface, "secondary text on a card"),
            (Kkb.textPrimary, Kkb.background, "body text on the page"),
            (Kkb.textSecondary, Kkb.creamWell, "text over a well"),
        ]

        for (traits, appearance) in [(light, "light"), (dark, "dark")] {
            for pair in pairs {
                let ratio = contrast(pair.text, on: pair.ground, traits)
                XCTAssertGreaterThan(
                    ratio, 4.0,
                    "\(pair.name) has \(String(format: "%.2f", ratio)):1 in \(appearance) mode"
                )
            }
        }
    }

    /// The menu button is drawn straight onto the page ground with no card or chip
    /// behind it, so its tint has to clear the ground in both appearances on its
    /// own. It was a fixed ink brown, which put it at roughly 1.3:1 against the
    /// dark ground — technically painted, effectively invisible.
    ///
    /// 3.0 is WCAG's floor for a non-text UI component, which is what this is.
    func testTheMenuButtonStaysVisibleOnThePageGround() {
        let tint = MenuIcon().color

        for (traits, appearance) in [(light, "light"), (dark, "dark")] {
            let ratio = contrast(tint, on: Kkb.background, traits)
            XCTAssertGreaterThan(
                ratio, 3.0,
                "the menu button has \(String(format: "%.2f", ratio)):1 against the "
                + "page ground in \(appearance) mode"
            )
        }
    }

    /// A tinted ground must sit *behind* its text, not in front of it: darker than
    /// the text in dark mode, lighter in light mode. This is the direction check the
    /// ratio alone can't make — 5:1 is 5:1 whichever way round the two are.
    func testTintedGroundsStayOnTheCorrectSideOfTheirText() {
        for (text, ground, name) in [
            (Kkb.marigoldText, Kkb.marigoldSurface, "marigold"),
            (Kkb.sageText, Kkb.sageSurface, "sage"),
            (Kkb.accentText, Kkb.terracottaSurface, "terracotta"),
        ] {
            XCTAssertGreaterThan(
                relativeLuminance(ground, light), relativeLuminance(text, light),
                "\(name) chip: the ground must be the lighter of the two in light mode"
            )
            XCTAssertLessThan(
                relativeLuminance(ground, dark), relativeLuminance(text, dark),
                "\(name) chip: the ground must be the darker of the two in dark mode"
            )
        }
    }

    /// The dark page ground must be neutral, and must stay below the cards.
    ///
    /// It used to be ink-900 — a warm brown at 1.5% relative luminance. At that
    /// darkness the warmth is invisible on device and only the blackness reads, so
    /// the page came across as plain black. The brand warmth is carried by the cream
    /// text and the tinted chips sitting on the ground, not by the ground itself.
    ///
    /// The second assertion is the ceiling: `surface` is unchanged warm brown at
    /// 0.0281, so lifting the page past it would flip cards from raised paper stock
    /// to inset panels while `PaperCard`'s drop shadow still says "raised". Anyone
    /// lightening the page further has to lift the cards in the same commit.
    func testDarkPageBackgroundIsNeutralAndSitsBelowTheCards() {
        let (r, g, b, _) = rgba(Kkb.background, dark)
        XCTAssertLessThan(
            max(r, g, b) - min(r, g, b), 0.02,
            "the dark page ground has a \(String(format: "%.3f", max(r, g, b) - min(r, g, b))) channel spread — it is tinted, not neutral"
        )
        XCTAssertLessThan(
            relativeLuminance(Kkb.background, dark), relativeLuminance(Kkb.surface, dark),
            "the page has risen above the cards — they will read as inset, not raised"
        )
    }

    /// Surfaces must actually get darker, and text lighter — an "adaptive" colour
    /// that moved the wrong way would still pass the inequality check above.
    func testDarkModeInvertsSurfaceAndTextLuminance() {
        XCTAssertLessThan(
            luminance(Kkb.background, dark), luminance(Kkb.background, light),
            "The page background must be darker in dark mode"
        )
        XCTAssertLessThan(
            luminance(Kkb.surface, dark), luminance(Kkb.surface, light),
            "Cards must be darker in dark mode"
        )
        XCTAssertGreaterThan(
            luminance(Kkb.textPrimary, dark), luminance(Kkb.textPrimary, light),
            "Primary text must be lighter in dark mode"
        )
    }

    /// Text has to stay readable on the surface it sits on, in both appearances.
    func testTextRemainsLegibleAgainstItsSurface() {
        for (traits, name) in [(light, "light"), (dark, "dark")] {
            let text = luminance(Kkb.textPrimary, traits)
            let surface = luminance(Kkb.surface, traits)
            XCTAssertGreaterThan(
                abs(text - surface), 0.4,
                "textPrimary on surface has too little contrast in \(name) mode"
            )
        }
    }

    /// The brand hues are fixed values shared with Android and the web app; they
    /// must not drift with appearance.
    func testBrandHuesAreAppearanceIndependent() {
        for (color, name) in [
            (Kkb.terracotta500, "terracotta500"),
            (Kkb.sage500, "sage500"),
            (Kkb.marigold500, "marigold500"),
            (Kkb.cream50, "cream50"),
            (Kkb.ink900, "ink900"),
        ] {
            XCTAssertTrue(
                rgba(color, light) == rgba(color, dark),
                "\(name) is a fixed brand colour and must not adapt"
            )
        }
    }

    /// Spot-check the palette against Android's `KkbColors.kt` values.
    func testPaletteMatchesAndroidHexValues() {
        let expectations: [(Color, UInt32, String)] = [
            (Kkb.cream50, 0xFEFAF3, "cream50"),
            (Kkb.cream100, 0xFDF5E6, "cream100"),
            (Kkb.terracotta500, 0xD55F24, "terracotta500"),
            (Kkb.terracotta600, 0xB8481D, "terracotta600"),
            (Kkb.sage500, 0x57855A, "sage500"),
            (Kkb.marigold500, 0xF2930B, "marigold500"),
            (Kkb.ink900, 0x2A1F17, "ink900"),
        ]
        for (color, hex, name) in expectations {
            let (r, g, b, _) = rgba(color, light)
            let expected = (
                CGFloat((hex >> 16) & 0xFF) / 255,
                CGFloat((hex >> 8) & 0xFF) / 255,
                CGFloat(hex & 0xFF) / 255
            )
            XCTAssertEqual(r, expected.0, accuracy: 0.01, "\(name) red")
            XCTAssertEqual(g, expected.1, accuracy: 0.01, "\(name) green")
            XCTAssertEqual(b, expected.2, accuracy: 0.01, "\(name) blue")
        }
    }

    // MARK: - What actually reaches the screen
    //
    // Everything above resolves colours in isolation. It cannot catch the failure
    // mode where the palette is right and something else is painted over it, which
    // is what happened: `HomeView` wraps the shell in a `NavigationStack`, that
    // container paints an opaque `systemBackground`, and in dark mode
    // `systemBackground` is pure black. `Kkb.background` and all three washes were
    // covered on every signed-in screen. Light mode hid it, because there
    // `systemBackground` is white and the page is nearly-white cream anyway.

    /// Renders a view for real and reads one pixel back out.
    private func renderedPixels<V: View>(
        _ view: V,
        _ style: UIUserInterfaceStyle,
        at points: [CGPoint],
        size: CGSize = CGSize(width: 320, height: 640)
    ) -> [(UInt8, UInt8, UInt8)] {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        return points.map { point in
            var data = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.translateBy(x: -point.x, y: -point.y)
            ctx.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
            return (data[0], data[1], data[2])
        }
    }

    /// Dead centre: all three washes fall off before reaching it, so the pixel there
    /// is the flat ground colour with nothing added on top.
    private func centrePixel<V: View>(
        _ view: V,
        _ style: UIUserInterfaceStyle,
        size: CGSize = CGSize(width: 320, height: 640)
    ) -> (UInt8, UInt8, UInt8) {
        renderedPixels(view, style, at: [CGPoint(x: size.width / 2, y: size.height / 2)], size: size)[0]
    }

    private func assertGround(
        _ pixel: (UInt8, UInt8, UInt8),
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (r, g, b, _) = rgba(Kkb.background, dark)
        let want = (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
        let off = max(abs(Int(pixel.0) - Int(want.0)), abs(Int(pixel.1) - Int(want.1)), abs(Int(pixel.2) - Int(want.2)))
        XCTAssertLessThan(
            off, 6,
            """
            \(what) rendered #\(String(format: "%02X%02X%02X", pixel.0, pixel.1, pixel.2)) \
            but Kkb.background in dark mode is #\(String(format: "%02X%02X%02X", want.0, want.1, want.2)) \
            — something opaque is covering the page
            """,
            file: file, line: line
        )
    }

    /// Control: the background on its own paints what the token says.
    func testKkbBackgroundPaintsTheTokenWhenNothingCoversIt() {
        assertGround(centrePixel(KkbBackground { Color.clear }, .dark), "KkbBackground alone")
    }

    /// The regression, and the shape `HomeView` actually uses.
    ///
    /// Without `kkbPageGround()` the centre of this renders #000000: the stack's
    /// own `systemBackground` covers the ground that `KkbBackground` painted
    /// underneath it. That is what shipped, and what made dark mode look black
    /// however many times the palette was edited.
    func testNavigationStackShellShowsThePageGround() {
        let shell = KkbBackground {
            NavigationStack {
                VStack { Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .kkbPageGround()
            }
        }
        assertGround(centrePixel(shell, .dark), "the HomeView shell")

        // A background pinned to a container that does not fill the screen leaves
        // black margins, which one centre sample would miss entirely.
        let size = CGSize(width: 320, height: 640)
        let probes = [
            CGPoint(x: 4, y: 4), CGPoint(x: size.width - 4, y: 4),
            CGPoint(x: 4, y: size.height - 4), CGPoint(x: size.width - 4, y: size.height - 4),
            CGPoint(x: size.width / 2, y: 8), CGPoint(x: size.width / 2, y: size.height - 8),
        ]
        for (pixel, point) in zip(renderedPixels(shell, .dark, at: probes, size: size), probes) {
            XCTAssertFalse(
                pixel == (0, 0, 0),
                "(\(Int(point.x)), \(Int(point.y))) is pure black — the ground does not reach the screen edge"
            )
        }
    }

    /// Every course needs a distinct accent, or the week grid stops being scannable.
    func testEveryMealTypeHasDistinctBarColours() {
        let firsts = MealType.allCases.map { rgba($0.barColors[0], light) }
        for (index, colour) in firsts.enumerated() {
            for other in firsts.dropFirst(index + 1) {
                XCTAssertFalse(colour == other, "Two courses share a bar colour")
            }
        }
        for type in MealType.allCases {
            XCTAssertEqual(type.barColors.count, 2, "\(type.key) needs a gradient pair")
        }
    }
}
