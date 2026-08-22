import SwiftUI
import UIKit

/// The two-pill toggle used for Today's Menu / The Week and Sign in / Sign up.
///
/// Deliberately not a `Picker(.segmented)` or a `TabView`: the pill shape, the
/// cream track and the terracotta fill are the product's own, and Android and web
/// both render it this way.
struct SegmentedTabs: View {
    struct Option: Identifiable {
        var title: String
        var systemImage: String?
        var id: String { title }

        init(_ title: String, systemImage: String? = nil) {
            self.title = title
            self.systemImage = systemImage
        }
    }

    var options: [Option]
    @Binding var selection: Int
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    guard selection != index else { return }
                    withAnimation(.snappy(duration: 0.22)) { selection = index }
                } label: {
                    HStack(spacing: 6) {
                        if let systemImage = option.systemImage {
                            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                        }
                        Text(option.title).kkbFont(.labelLarge)
                    }
                    .foregroundStyle(selection == index ? Kkb.cream50 : Kkb.ink700)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selection == index {
                            Capsule()
                                .fill(Kkb.terracotta500)
                                .matchedGeometryEffect(id: "kkb.segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == index ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(6)
        .background(Capsule().fill(Kkb.cream100.opacity(0.7)))
        .overlay(Capsule().stroke(Kkb.terracotta200.opacity(0.6), lineWidth: 1))
    }
}

/// One of the four actions above the week grid: AI · PDF · Shopping · Clear.
/// Each has its own fill, border and foreground, straight from `ActionPill.kt:47`.
struct ActionPill: View {
    enum Variant {
        case ai, pdf, shopping, clear

        var colors: (start: Color, end: Color, border: Color, foreground: Color) {
            switch self {
            case .ai: (Kkb.marigold100, Kkb.marigold200, Kkb.marigold300, Kkb.marigold700)
            case .pdf: (Kkb.sage100, Kkb.sage300.opacity(0.45), Kkb.sage300, Kkb.sage700)
            case .shopping: (Kkb.terracotta100, Kkb.terracotta200.opacity(0.6),
                             Kkb.terracotta300, Kkb.terracotta700)
            case .clear: (Kkb.cream100, Kkb.cream200, Kkb.cream300, Kkb.ink700)
            }
        }
    }

    var variant: Variant
    var systemImage: String
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        let palette = variant.colors
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title).kkbFont(.labelSmall).fontWeight(.semibold)
            }
            .foregroundStyle(palette.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [palette.start, palette.end],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }
}

/// The primary call to action: a terracotta→marigold gradient capsule.
struct KkbPrimaryButton: View {
    var title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .kkbFont(.titleMedium)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(Kkb.cream50)
                }
            }
            .foregroundStyle(Kkb.cream50)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [Kkb.terracotta500, Kkb.marigold500],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            )
            .shadow(color: Kkb.terracotta500.opacity(0.35), radius: 12, x: 0, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

/// A quieter capsule for secondary actions inside sheets.
struct KkbSecondaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).kkbFont(.labelLarge)
            }
            .foregroundStyle(Kkb.accentText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Kkb.terracottaSurface.opacity(0.7)))
            .overlay(Capsule().stroke(Kkb.terracotta200, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Labelled field used across auth and the paste-a-URL rows.
struct KkbTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.eyebrow)
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.accentText)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .kkbFont(.bodyLarge)
            .foregroundStyle(Kkb.textPrimary)
            .keyboardType(keyboard)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Kkb.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Kkb.hairline, lineWidth: 1)
            )
        }
    }
}

/// The menu glyph from lucide-react, the icon set the web app draws everything
/// with. SF Symbols' `line.3.horizontal` is a different family — thinner, squarer
/// caps — and sat oddly next to the lucide chef hat two views away.
///
/// The web app has no drawer of its own, so there is no hamburger to copy from it
/// directly; this is lucide's `Menu` at the version the web app pins (0.294.0),
/// which is the icon it *would* use.
struct MenuIcon: View {
    var size: CGFloat = 22
    /// Semantic, not a raw palette constant. `ink700` is a fixed warm brown, which
    /// on the dark page ground came out at 1.25:1 — painted but not visible.
    var color: Color = Kkb.textPrimary

    var body: some View {
        MenuIconShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2 * (size / 24),
                                              lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// lucide `Menu`: three lines from x=4 to x=20 at y=6, 12 and 18.
struct MenuIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Authored against lucide's 24×24 viewport, then scaled to `rect`.
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        for y in [6.0, 12.0, 18.0] as [CGFloat] {
            path.move(to: p(4, y))
            path.addLine(to: p(20, y))
        }
        return path
    }
}

/// Chef hat from lucide-react, the same mark the web app puts on its Get Started
/// screen. Redrawn as a stroked `Path` so it inherits colour and scales cleanly.
struct ChefHatShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Authored against lucide's 24×24 viewport, then scaled to `rect`.
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        // Toque: crown arcs over the head, sides drop to the brim.
        path.move(to: p(7, 21))
        path.addLine(to: p(7, 14.65))
        path.addCurve(to: p(6.273, 13.609), control1: p(7, 14.193), control2: p(6.684, 13.806))
        path.addCurve(to: p(8.407, 6.021), control1: p(3.2, 12.2), control2: p(4.5, 6.6))
        path.addCurve(to: p(17.593, 6.021), control1: p(9.8, 2.4), control2: p(16.2, 2.4))
        path.addCurve(to: p(19.727, 13.609), control1: p(21.5, 6.6), control2: p(22.8, 12.2))
        path.addCurve(to: p(19, 14.65), control1: p(19.316, 13.806), control2: p(19, 14.193))
        path.addLine(to: p(19, 21))
        path.closeSubpath()
        // Brim divider.
        path.move(to: p(6, 17))
        path.addLine(to: p(18, 17))
        return path
    }
}

struct ChefHatIcon: View {
    var size: CGFloat = 40
    var color: Color = Kkb.terracotta600

    var body: some View {
        ChefHatShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2 * (size / 24),
                                              lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
