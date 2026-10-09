import AuthenticationServices
import SwiftUI

/// Presents Swiggy's consent page whenever `InstamartViewModel.pendingSignInURL`
/// asks for it — the iOS half of "Connecting" in the spec.
///
/// An `ASWebAuthenticationSession`, through SwiftUI's
/// `\.webAuthenticationSession` (iOS 16.4+), which supplies the presentation
/// anchor itself. The session owns the whole round trip: Swiggy redirects to
/// our server's callback, which answers an `ios-` state with a 302 to
/// `khanakyabanau://swiggy/connected?…`, and the session catches that scheme and
/// closes. So, unlike Android's Custom Tab + `SwiggyReturnActivity`, there is no
/// URL-scheme registration, no Associated Domains and no `onOpenURL` anywhere.
///
/// Ephemeral: no "wants to use … to sign in" system alert, and no Swiggy
/// cookies left in Safari. Swiggy signs in by OTP and its grant lasts five
/// days, so a shared browser session would buy almost nothing.
///
/// The callback URL is deliberately ignored. It carries no secret — anyone can
/// open `khanakyabanau://swiggy/connected?status=ok` — and a user can cancel the
/// sheet after consent has already completed server-side. The server is the
/// source of truth, so whatever ended the session (callback, cancel, an error,
/// or failing to start at all) the model re-asks `api/groceries/status` in
/// `signInFinished()` and builds only if that says connected.
///
/// The domain shown in the session's chrome is Apple's anti-phishing UI — the
/// user can see they are typing their Swiggy number into Swiggy — and stays.
private struct SwiggySignInModifier: ViewModifier {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let model: InstamartViewModel

    func body(content: Content) -> some View {
        content
            // Keyed on the URL: a new connect attempt is a new id, and the
            // model's own reset to nil (in signInFinished or dismiss) cancels
            // this task harmlessly — signInFinished runs its work in a task of
            // its own, which this cancellation does not reach.
            .task(id: model.pendingSignInURL) {
                guard let url = model.pendingSignInURL else { return }
                do {
                    _ = try await webAuthenticationSession.authenticate(
                        using: url,
                        callbackURLScheme: "khanakyabanau",
                        preferredBrowserSession: .ephemeral
                    )
                } catch {
                    // Cancelled by the user, or the session could not start.
                    // Same next step either way: ask the server.
                }
                await model.signInFinished()
            }
    }
}

extension View {
    /// Runs Swiggy's sign-in for `model` whenever it wants one. Attach once,
    /// to a view that is on screen while the Instamart button is.
    func swiggySignIn(_ model: InstamartViewModel) -> some View {
        modifier(SwiggySignInModifier(model: model))
    }
}
