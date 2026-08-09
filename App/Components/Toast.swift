import SwiftUI

/// A transient confirmation, the iOS stand-in for Android's snackbar.
///
/// Deliberately not an alert: these messages ("AI suggestions added to empty
/// slots") confirm something that already happened and must not need dismissing.
private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval = 2.6

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.cream50)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Kkb.ink800.opacity(0.95))
                        )
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.snappy(duration: 0.25), value: message)
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    message = nil
                }
            }
    }
}

extension View {
    /// Shows `message` as a toast and clears it automatically.
    func kkbToast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
