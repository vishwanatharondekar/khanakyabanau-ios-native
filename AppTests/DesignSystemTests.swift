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
