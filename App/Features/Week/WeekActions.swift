import KhanaKit
import SwiftUI

/// Share, plus an overflow for everything rarer.
///
/// Four pills of equal weight — AI, PDF, Shopping, Clear — said every action
/// mattered the same. They do not. Shopping is a tab now and has left the row
/// entirely; generate is only urgent on an empty week, where `WeekHero`
/// promotes it, so on a filled week Share is what anyone actually wants.
///
/// The verbs changed with the shapes, and that is the point rather than a
/// detail: Share rather than PDF, because the intent is sending the week to
/// someone; Fill empty days / Regenerate week rather than AI, because the AI is
/// not the point.
///
/// Nothing here is spelled `if brand.id == ...`. Which entries exist is decided
/// entirely by the capability booleans, so a brand whose users receive their
/// plan rather than composing it renders a deliberate, quiet toolbar rather
/// than a row of disabled buttons.
///
/// A SwiftUI `Menu` renders in its own presentation, so it cannot be clipped by
/// its container — the webapp's two clipping bugs have no equivalent here.
struct WeekActions: View {
    var brand: Brand
    var generateLabel: String
    var canGenerate: Bool
    var canImport: Bool
    var canEdit: Bool
    var onGenerate: () -> Void
    var onImport: () -> Void
    var onShare: () -> Void
    var onClear: () -> Void
    /// Step into the weeks already gone. Nil when there is nothing back there to
    /// see, which is also how the entry stays out of the way of everyone who
    /// never wants it.
    var onBrowseEarlier: (() -> Void)?
    var onOverflowOpened: () -> Void

    private var hasOverflow: Bool {
        canGenerate || canImport || canEdit || onBrowseEarlier != nil
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Kkb.ink700)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share this week")

            if hasOverflow {
                Menu {
                    if canGenerate {
                        Button {
                            onGenerate()
                        } label: {
                            Label(generateLabel, systemImage: "sparkles")
                        }
                    }
                    if canImport {
                        Button {
                            onImport()
                        } label: {
                            Label(brand.labels.importPlan, systemImage: "square.and.arrow.down")
                        }
                    }
                    // Rare by nature, so it lives where rare things go rather
                    // than taking permanent space in a header just cut down to
                    // two icons.
                    if let onBrowseEarlier {
                        Button {
                            onBrowseEarlier()
                        } label: {
                            Label("Earlier weeks", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    // Clear is destructive and serves one narrow case: wanting
                    // an empty week to fill by hand. Regenerate already replaces
                    // a full week. It survives, but not at equal weight.
                    //
                    // No confirmation here — onClear opens one. Asking twice for
                    // the same action teaches people to dismiss the question.
                    if canEdit {
                        Button(role: .destructive) {
                            onClear()
                        } label: {
                            Label("Clear week", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Kkb.ink700)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions")
                .simultaneousGesture(TapGesture().onEnded { onOverflowOpened() })
            }
        }
    }
}
