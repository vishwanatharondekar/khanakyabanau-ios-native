import KhanaKit
import SwiftUI
import UIKit

extension Color {
    /// Hex literal, e.g. `Color(hex: 0xD55F24)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The KhanaKyaBanau palette, byte-for-byte from Android's `KkbColors.kt:25-57`
/// (which in turn matches the web app's `tailwind.config.js`).
///
/// Both existing clients are light-only — Android sets `forceDarkAllowed=false`
/// and the web app repeats its light values under `prefers-color-scheme: dark`.
/// iOS adds a dark variant because the platform expects one, but the brand hues
/// are unchanged; only the cream surfaces and ink text swap roles. Anything that
/// reads as "the terracotta button" stays terracotta in both.
enum Kkb {
    // Warm paper surfaces.
    static let cream50 = Color(hex: 0xFEFAF3)
    static let cream100 = Color(hex: 0xFDF5E6)
    static let cream200 = Color(hex: 0xFBECD0)
    static let cream300 = Color(hex: 0xF7DFAE)

    // Primary action.
    static let terracotta100 = Color(hex: 0xFAE4D1)
    static let terracotta200 = Color(hex: 0xF3C49A)
    static let terracotta300 = Color(hex: 0xEB9F65)
    static let terracotta400 = Color(hex: 0xE07A3F)
    static let terracotta500 = Color(hex: 0xD55F24)
    static let terracotta600 = Color(hex: 0xB8481D)
    static let terracotta700 = Color(hex: 0x93371C)

    // Prep, PDF, success.
    static let sage100 = Color(hex: 0xE1ECDF)
    static let sage300 = Color(hex: 0x9ABD92)
    static let sage500 = Color(hex: 0x57855A)
    static let sage600 = Color(hex: 0x436B48)
    static let sage700 = Color(hex: 0x37553B)

    // AI, calories, today.
    static let marigold100 = Color(hex: 0xFEF0C7)
    static let marigold200 = Color(hex: 0xFDDF8A)
    static let marigold300 = Color(hex: 0xFCC84D)
    static let marigold400 = Color(hex: 0xFBB224)
    static let marigold500 = Color(hex: 0xF2930B)
    static let marigold600 = Color(hex: 0xD67105)
    static let marigold700 = Color(hex: 0xB15108)

    // Text.
    static let ink600 = Color(hex: 0x5F4A3A)
    static let ink700 = Color(hex: 0x4A3A2D)
    static let ink800 = Color(hex: 0x3A2C21)
    static let ink900 = Color(hex: 0x2A1F17)

    // MARK: - Semantic, theme-aware

    /// Page background. Dark mode is a neutral gray, not ink-900: at 1.5% luminance
    /// the brown's warmth was invisible and the page just read as black. Capped just
    /// under `surface` (0.0281) so cards stay the lighter of the two — see
    /// `testDarkPageBackgroundIsNeutralAndSitsBelowTheCards`.
    static let background = adaptive(light: cream100, dark: Color(hex: 0x2E2E30))
    /// Cards, sheets, raised surfaces.
    static let surface = adaptive(light: cream50, dark: Color(hex: 0x3A2C21))
    /// A step further back than `surface` — thumbnail wells, inset rows.
    static let surfaceSunken = adaptive(light: cream100, dark: Color(hex: 0x33261C))
    /// Hairlines and card borders.
    static let hairline = adaptive(light: terracotta200.opacity(0.6), dark: Color(hex: 0x5F4A3A))
    static let textPrimary = adaptive(light: ink900, dark: cream100)
    static let textSecondary = adaptive(light: ink600, dark: Color(hex: 0xC7B49F))
    /// Terracotta reads muddy on a dark ground; step up two stops for contrast.
    static let accent = adaptive(light: terracotta500, dark: terracotta300)
    static let accentText = adaptive(light: terracotta600, dark: terracotta300)
    static let sageText = adaptive(light: sage700, dark: sage300)
    static let marigoldText = adaptive(light: marigold700, dark: marigold300)

    // MARK: - Tinted grounds
    //
    // The pale 100-stops are the ground under every tinted chip: calorie badges,
    // prep badges, notice cards, video tags. They cannot be used raw, because the
    // text on them (`marigoldText`, `sageText`, `accentText`) flips to the *light*
    // 300-stop in dark mode — a pale ground plus pale text is the light-on-light
    // merge that made calories and prep badges unreadable. So the ground flips too:
    // deep, desaturated versions of the same hue, keeping the text/ground roles the
    // same way round in both appearances.

    static let marigoldSurface = adaptive(light: marigold100, dark: Color(hex: 0x4A3411))
    static let sageSurface = adaptive(light: sage100, dark: Color(hex: 0x2C3E2E))
    static let terracottaSurface = adaptive(light: terracotta100, dark: Color(hex: 0x4A2718))
    /// Untinted wells: image placeholders, shimmer, inset rows.
    static let creamWell = adaptive(light: cream200, dark: Color(hex: 0x30241A))

    private static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        return light
        #endif
    }
}

extension MealType {
    /// Per-course accent, driving the gradient bar on Today's cards and the
    /// eyebrow text on meal rows. Android keys these off `MealTheme`.
    var barColors: [Color] {
        switch self {
        case .breakfast: [Kkb.marigold400, Kkb.marigold500]
        case .morningSnack: [Kkb.sage300, Kkb.sage500]
        case .lunch: [Kkb.terracotta400, Kkb.terracotta500]
        case .eveningSnack: [Kkb.marigold300, Kkb.terracotta300]
        case .dinner: [Kkb.terracotta500, Kkb.marigold500]
        }
    }

    var chipText: Color {
        switch self {
        case .breakfast: Kkb.marigoldText
        case .morningSnack: Kkb.sageText
        case .lunch: Kkb.accentText
        case .eveningSnack: Kkb.marigoldText
        case .dinner: Kkb.accentText
        }
    }
}
