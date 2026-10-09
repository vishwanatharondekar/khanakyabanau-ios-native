import SwiftUI

/// The attribution Swiggy's integration agreement requires on every surface
/// where Instamart ordering is offered (clauses 3.4(ii) and 4(iii)): the
/// shopping footer while the button is up, the live-order strip, and each
/// state of the ordering sheet.
///
/// One view rather than a string repeated per screen — port of the webapp's
/// `PoweredBySwiggy.tsx` and Android's composable of the same name — so that
/// when Swiggy's branding guidelines arrive the form and style change in one
/// place, and so a new Instamart surface has an obvious thing to reach for.
struct PoweredBySwiggy: View {
    var body: some View {
        Text("Powered by Swiggy")
            .kkbFont(.labelSmall)
            .foregroundStyle(Kkb.textSecondary)
    }
}
