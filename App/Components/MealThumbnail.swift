import KhanaKit
import SwiftUI

/// A dish photo, or a placeholder while one is being resolved.
///
/// Three distinct states, matching Android: a resolved image, a `Shimmer` while
/// the name→URL lookup is still in flight, and an emoji tile when the dish simply
/// has no photo in the pool. The emoji case must not shimmer forever — plenty of
/// home-cooked dish names will never match anything.
struct MealThumbnail: View {
    var imageUrl: String?
    var size: CGFloat
    var cornerRadius: CGFloat
    /// True while the batch image lookup for this screen is still running.
    var isResolving: Bool
    var emoji: String = "🍽"

    var body: some View {
        Group {
            if let imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.18))) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Shimmer()
                    @unknown default:
                        placeholder
                    }
                }
            } else if isResolving {
                Shimmer()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Kkb.cream50, lineWidth: 3)
        )
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Kkb.creamWell, Kkb.surfaceSunken],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(Text(emoji).font(.system(size: size * 0.38)))
    }
}
