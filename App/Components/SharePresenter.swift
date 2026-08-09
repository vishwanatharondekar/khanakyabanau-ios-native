import UIKit

/// Presents the system share sheet.
///
/// Android has a bespoke `ShareSheet` with a WhatsApp tile because the platform
/// gives it no equivalent; on iOS `UIActivityViewController` already surfaces
/// WhatsApp, Messages and everything else the user has installed, so the native
/// sheet is the right adaptation rather than a reimplementation.
enum SharePresenter {
    @MainActor
    static func present(items: [Any], sourceRect: CGRect? = nil) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return }

        // Present from the top-most controller, otherwise a sheet already on screen
        // swallows the presentation.
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }

        let controller = UIActivityViewController(
            activityItems: items, applicationActivities: nil
        )
        // iPad requires an anchor or it crashes.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = sourceRect
                ?? CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 60,
                          width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}
