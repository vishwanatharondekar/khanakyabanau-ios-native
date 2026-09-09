import SwiftUI

/// One tappable row in a menu sheet: an icon, a label, and an optional emphasised
/// treatment for a call to action.
///
/// Shared by the drawer and the account sheet, which are the same visual family —
/// a list of destinations and actions on the app ground.
struct MenuRow: View {
    var title: String
    var systemImage: String
    var tint: Color
    var isEmphasised: Bool = false
    /// A second line under the title. What lets a row explain itself to someone
    /// who cannot use it yet — a guest reading why prep reminders are worth an
    /// account.
    var subtitle: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .kkbFont(.bodyLarge)
                        .fontWeight(isEmphasised ? .semibold : .regular)
                        .foregroundStyle(isEmphasised ? tint : Kkb.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEmphasised ? Kkb.terracottaSurface.opacity(0.6) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
