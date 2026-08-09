import SwiftUI
import UIKit

/// The type scale from Android's `KkbTypography.kt`, mapped onto iOS system faces.
///
/// Android uses `FontFamily.Serif` / `SansSerif` / `Cursive`; the web app uses
/// Playfair Display / Inter / Caveat. On iOS that is New York (`.serif`), SF Pro
/// (`.default`) and Snell Roundhand — no font files are bundled for the UI, which
/// matches Android (the Noto files in `Resources/Fonts` exist only for PDF export).
struct KkbTextStyle {
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design = .default
    /// Android's letterSpacing in sp, applied as SwiftUI tracking.
    var tracking: CGFloat = 0
    /// Android's lineHeight in sp. Extra leading is derived from it.
    var lineHeight: CGFloat?
    var italic: Bool = false
    /// The text style Dynamic Type scales this against.
    var relativeTo: Font.TextStyle = .body
    /// Handwritten empty states use a script face.
    var script: Bool = false

    // Display — serif, the editorial voice of the product.
    static let displayHero = KkbTextStyle(
        size: 44, weight: .bold, design: .serif, tracking: -0.5,
        lineHeight: 50, relativeTo: .largeTitle
    )
    static let displayLarge = KkbTextStyle(
        size: 32, weight: .bold, design: .serif, tracking: -0.3,
        lineHeight: 38, relativeTo: .title
    )
    static let displayMedium = KkbTextStyle(
        size: 24, weight: .semibold, design: .serif, tracking: -0.2,
        lineHeight: 30, relativeTo: .title2
    )
    static let displaySmall = KkbTextStyle(
        size: 18, weight: .semibold, design: .serif,
        lineHeight: 24, relativeTo: .title3
    )
    /// All-caps eyebrow labels. The wide tracking is the product's signature.
    static let sectionLabel = KkbTextStyle(
        size: 11, weight: .semibold, tracking: 3, relativeTo: .caption
    )
    /// `— unwritten —` and friends.
    static let handwritten = KkbTextStyle(
        size: 22, weight: .medium, lineHeight: 26, italic: true,
        relativeTo: .title3, script: true
    )

    // Body.
    static let titleMedium = KkbTextStyle(size: 16, weight: .semibold, lineHeight: 22, relativeTo: .headline)
    static let bodyLarge = KkbTextStyle(size: 16, weight: .regular, lineHeight: 22, relativeTo: .body)
    static let bodyMedium = KkbTextStyle(size: 14, weight: .regular, lineHeight: 20, relativeTo: .callout)
    static let bodySmall = KkbTextStyle(size: 12, weight: .regular, lineHeight: 16, relativeTo: .footnote)
    static let labelLarge = KkbTextStyle(size: 14, weight: .semibold, tracking: 0.5, relativeTo: .subheadline)
    static let labelSmall = KkbTextStyle(size: 11, weight: .medium, tracking: 0.5, relativeTo: .caption2)

    func scaledSize(for typeSize: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: relativeTo.uiTextStyle)
        // Accessibility sizes can triple a 44pt hero, which breaks every card
        // layout on the week grid. Cap the growth rather than disable scaling.
        let scaled = metrics.scaledValue(for: size)
        return min(scaled, size * 1.6)
        #else
        return size
        #endif
    }

    func font(for typeSize: DynamicTypeSize) -> Font {
        let resolved = scaledSize(for: typeSize)
        if script {
            // Snell Roundhand ships with iOS; if it ever goes missing, `.custom`
            // falls back to the system face at the same size rather than crashing.
            return .custom("SnellRoundhand-Bold", size: resolved * 1.15)
        }
        let base = Font.system(size: resolved, weight: weight, design: design)
        return italic ? base.italic() : base
    }
}

private struct KkbFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let style: KkbTextStyle

    func body(content: Content) -> some View {
        let size = style.scaledSize(for: typeSize)
        return content
            .font(style.font(for: typeSize))
            .tracking(style.tracking)
            .lineSpacing(max(0, (style.lineHeight ?? size) - size) * 0.5)
    }
}

extension View {
    /// Applies a `KkbTextStyle` including its tracking and leading.
    func kkbFont(_ style: KkbTextStyle) -> some View {
        modifier(KkbFontModifier(style: style))
    }
}

#if canImport(UIKit)
private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
#endif

extension String {
    /// Eyebrow labels are upper-cased at the call site on Android; this keeps that
    /// explicit rather than hiding it in a text style.
    var eyebrow: String { uppercased() }
}
