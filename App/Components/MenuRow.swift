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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(title)
                    .kkbFont(.bodyLarge)
                    .fontWeight(isEmphasised ? .semibold : .regular)
                    .foregroundStyle(isEmphasised ? tint : Kkb.textPrimary)
                    .multilineTextAlignment(.leading)
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
