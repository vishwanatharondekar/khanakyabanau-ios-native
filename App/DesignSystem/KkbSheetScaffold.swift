import SwiftUI

/// The shared chrome for every settings sheet: an eyebrow, a highlighted title,
/// the content, and a right-aligned Cancel / Confirm pair with an inline spinner.
///
/// Android does this with `SheetScaffold.kt`; keeping the same structure means the
/// four settings screens stay visually identical across platforms while still
/// arriving as native iOS sheets with a drag indicator and detents.
struct SheetScaffold<Content: View>: View {
    var eyebrow: String
    var title: String
    var confirmTitle: String = "Save"
    var cancelTitle: String = "Cancel"
    var isSaving: Bool = false
    var isConfirmEnabled: Bool = true
    /// Shown in red above the buttons; nil hides the row entirely.
    var errorMessage: String?
    var onCancel: () -> Void
    var onConfirm: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        KkbBackground {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !eyebrow.isEmpty {
                                Text(eyebrow.eyebrow)
                                    .kkbFont(.sectionLabel)
                                    .foregroundStyle(Kkb.accentText)
                            }
                            Text(title)
                                .kkbFont(.displayMedium)
                                .foregroundStyle(Kkb.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .editorialHighlight()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        content
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)

                VStack(spacing: 10) {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .kkbFont(.bodySmall)
                            .foregroundStyle(Kkb.terracotta600)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        Spacer()
                        Button(cancelTitle, action: onCancel)
                            .kkbFont(.labelLarge)
                            .foregroundStyle(Kkb.textSecondary)
                            .disabled(isSaving)

                        Button(action: onConfirm) {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().tint(Kkb.cream50).controlSize(.small)
                                }
                                Text(confirmTitle).kkbFont(.labelLarge)
                            }
                            .foregroundStyle(Kkb.cream50)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Kkb.terracotta500))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isConfirmEnabled || isSaving)
                        .opacity(isConfirmEnabled ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// The scrim + card shown during a long AI call. Android calls this
/// `FullScreenLoader`; the copy is load-bearing because these operations can run
/// for the better part of a minute with no streaming feedback.
struct FullScreenLoader: View {
    var title: String = "ONE MOMENT"
    var message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            PaperCard(cornerRadius: 28) {
                VStack(spacing: 14) {
                    ProgressView().tint(Kkb.terracotta500).controlSize(.large)
                    Text(title)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.accentText)
                    Text(message)
                        .kkbFont(.displaySmall)
                        .foregroundStyle(Kkb.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 300)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// Inline error with a retry affordance. Used wherever a screen has content to
/// keep on screen; a screen with nothing at all uses `KkbEmptyState`.
struct InlineErrorCard: View {
    var message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        PaperCard(cornerRadius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Kkb.terracotta500)
                    Text(message)
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onRetry {
                    KkbSecondaryButton(title: retryTitle, systemImage: "arrow.clockwise", action: onRetry)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The handwritten empty-state voice — `— unwritten —` over a small caps line.
/// The copy is verbatim from the other clients and is part of the brand.
struct KkbEmptyState: View {
    var script: String
    var caption: String
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(script)
                .kkbFont(.handwritten)
                .foregroundStyle(Kkb.textSecondary)
            Text(caption.eyebrow)
                .kkbFont(.sectionLabel)
                .foregroundStyle(Kkb.textSecondary.opacity(0.8))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

/// A small caps section heading with the terracotta rule underneath.
struct SectionHeading: View {
    var eyebrow: String?
    var title: String
    var accent: Color = Kkb.accentText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.eyebrow)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(accent)
            }
            Text(title)
                .kkbFont(.displayMedium)
                .italic()
                .foregroundStyle(Kkb.textPrimary)
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
