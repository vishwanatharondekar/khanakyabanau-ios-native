import KhanaKit
import SwiftUI

/// The app's full-screen ground: warm cream with three soft radial washes.
///
/// Port of Android's `KkbBackground.kt:32` and the web app's fixed body gradient.
/// The washes are what stop large cream areas from reading as flat card stock.
struct KkbBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    /// The washes are pale by design. At full strength on a dark ground they lift
    /// the page toward mid-grey and take contrast away from every piece of text on
    /// it, so in dark mode they are dimmed to a hint of warmth rather than removed.
    private var washStrength: Double { scheme == .dark ? 0.22 : 1 }

    var body: some View {
        ZStack {
            Kkb.background.ignoresSafeArea()
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack {
                    wash(Kkb.cream300.opacity(0.55 * washStrength),
                         center: .init(x: 0, y: 0), radius: w * 0.85)
                    wash(Kkb.terracotta200.opacity(0.40 * washStrength),
                         center: .init(x: w * 0.85, y: h * 0.10), radius: w * 0.65)
                    wash(Kkb.sage300.opacity(0.30 * washStrength),
                         center: .init(x: w * 0.50, y: h * 0.95), radius: w * 0.70)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            content
        }
    }

    /// The gradient has to be centred *within its own frame* and the frame then
    /// positioned — anchoring it to `.topLeading` leaves the fade offset by half
    /// the frame, so the frame's edge cuts the wash off as a visible hard line.
    private func wash(_ color: Color, center: CGPoint, radius: CGFloat) -> some View {
        RadialGradient(
            gradient: Gradient(colors: [color, color.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
        .position(x: center.x, y: center.y)
    }
}

/// The product's signature card: cream stock, a hairline terracotta rule and a
/// soft paper shadow. Everything that looks like a card in this app is one of these.
struct PaperCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Kkb.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Kkb.hairline, lineWidth: 1)
            )
            .shadow(color: Kkb.ink800.opacity(0.10), radius: 12, x: 0, y: 4)
    }
}

/// The marigold highlighter behind a word — the web app's `.editorial-underline`,
/// drawn from 62% to 90% of the text's height so it reads as a felt-tip stroke
/// rather than an underline.
struct EditorialHighlight: ViewModifier {
    var color: Color = Kkb.marigold300.opacity(0.55)

    func body(content: Content) -> some View {
        content.background(alignment: .bottom) {
            GeometryReader { proxy in
                let h = proxy.size.height
                color
                    .frame(height: h * 0.28)
                    .offset(y: h * 0.62)
            }
        }
    }
}

extension View {
    func editorialHighlight(_ color: Color = Kkb.marigold300.opacity(0.55)) -> some View {
        modifier(EditorialHighlight(color: color))
    }
}

/// Diagonal cream sweep shown while a meal thumbnail loads. Deliberately not a
/// spinner: the week grid can have 21 of these at once.
struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            LinearGradient(
                colors: [Kkb.creamWell, Kkb.surface, Kkb.creamWell],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .offset(x: phase * w * 2)
            .background(Kkb.creamWell)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The 3pt gradient rail marking today (terracotta→marigold) and tomorrow
/// (marigold→terracotta, thinner) down the left edge of a day card.
struct Ribbon: View {
    enum Kind { case today, tomorrow }
    var kind: Kind

    var body: some View {
        LinearGradient(
            colors: kind == .today
                ? [Kkb.terracotta500, Kkb.marigold500]
                : [Kkb.marigold400, Kkb.terracotta300],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: kind == .today ? 3 : 2)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// `🔥 480 kcal`. Only shown when the user has calorie tracking switched on and
/// the server actually returned a number.
struct CalorieBadge: View {
    var calories: Int

    var body: some View {
        Text("🔥 \(calories) kcal")
            .kkbFont(.labelSmall)
            .fontWeight(.semibold)
            .foregroundStyle(Kkb.marigoldText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Kkb.marigoldSurface))
            .overlay(Capsule().stroke(Kkb.marigold300.opacity(0.6), lineWidth: 1))
            .accessibilityLabel("\(calories) kilocalories")
    }
}

/// The prep-ahead hint on a week row, e.g. `⏳ prep 8 hours ahead`.
struct PrepAheadBadge: View {
    var leadTimeMinutes: Int

    var body: some View {
        Text("⏳ prep \(formatLeadTime(leadTimeMinutes))")
            .kkbFont(.labelSmall)
            .foregroundStyle(Kkb.sageText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Kkb.sageSurface))
            .accessibilityLabel("Needs prep \(formatLeadTime(leadTimeMinutes))")
    }
}
