# Swiggy Instamart ordering — iOS

Status: in progress (2026-10-08). A port of the shipped webapp feature and of the Android
implementation built the same day. References:

- Webapp (`weekly-food-planner`): `components/ShoppingListModal.tsx`,
  `components/SwiggyCartReview.tsx`, `components/SwiggyOrderPlaced.tsx`,
  `components/PoweredBySwiggy.tsx`, `lib/swiggy/orders.ts`, `lib/swiggy/address.ts`,
  `lib/shopping-list-scope.ts`, and the "Native clients" section of
  `feature-readmes/SWIGGY_INSTAMART.md` (the server contract).
- Android (`khanakyabanau-android-native`, branch `feat/swiggy-instamart`):
  `docs/superpowers/specs/2026-10-08-swiggy-instamart-design.md`, and the code in
  `core/model/.../InstamartOrders.kt`, `InstamartCart.kt`, `core/data/.../InstamartRepository.kt`,
  `feature/week/.../instamart/`. Behaviour should match it; where the two clients differ
  it should be for a platform reason, written down here.

## What it is

From the Shopping pane, an India user with the feature switched on can turn the scoped,
pruned list into an Instamart cart, review Swiggy's own packs and prices, untick lines and
re-price, and place a cash-on-delivery order. Ordered items then show as "ordered" on the
list until Swiggy reports them delivered, when they move into "already have".

Everything that talks to Swiggy is server-side. The app calls `/api/groceries/*` with its
existing bearer token; it never sees a Swiggy token, a price we computed, or a SKU we chose.

## Constraints carried over (non-negotiable)

- **Orders cannot be cancelled.** The review screen shows Swiggy's numbers only; the
  confirmed total goes to checkout, which refuses if it moved.
- **No prices of ours.** A line Swiggy did not put in the cart shows no price.
- **"Powered by Swiggy"** wherever Instamart ordering is offered (agreement 3.4(ii), 4(iii)).
- **Foreground only.** Delivery status is fetched only while the Shopping pane is visible,
  at most once a minute per order. No background refresh, no BGTask.
- **Never auto-retry** a 429, a checkout, or a cart write.
- **A 2xx from checkout is a placed order, always.** A transport failure during checkout
  (timeout, dropped connection, unreadable 2xx) is *unconfirmed*: tell the user to check
  their Swiggy orders, reload the week's list, never offer "try again".

## Who sees it

`canOrderInstamart(brand, user, country)` in KhanaKit `Logic/Brand.swift` — all of: brand
capability `instamart`; signed-in, non-guest user; `user.features.swiggyInstamart`;
`country == "IN"` (case-insensitive) from `GET api/geo` (null fails closed). The button
then appears only once `GET api/groceries/status` returns 200; a 404 means the server's
gate (deployment switch + per-user flag) says no.

## Connecting — the platform difference

`GET api/groceries/connect?client=ios` → `authorizeUrl`, opened in an
`ASWebAuthenticationSession` with `callbackURLScheme: "khanakyabanau"`. Swiggy redirects
to our server callback (unchanged, allowlisted), which answers an `ios-` state with a
302 to `khanakyabanau://swiggy/connected?status=…`; the session catches that itself and
closes. **No URL scheme registration, no Associated Domains, no `onOpenURL`** — the session
owns the round trip, which is why iOS needs nothing like Android's `SwiggyReturnActivity`.

- `prefersEphemeralWebBrowserSession = true`: no "wants to use … to sign in" system
  alert and no cookies left behind. Swiggy's sign-in is OTP-based and the token lasts five
  days, so a shared Safari session buys little.
- The completion's URL is a hint only. On completion — success, user cancel, or error —
  the view model asks `api/groceries/status`, and builds the cart only if it says connected.
- The session's sheet shows the domain; that is Apple's anti-phishing chrome and stays.

## The flow

`InstamartViewModel` (`@MainActor @Observable`, App target) owns availability and the
ordering flow; the existing shopping-list state keeps owning `haveAlready` and now `orders`.

```
Hidden ──(geo IN + flag + status 200)──▶ Available(connected?)
Available ──tap──▶ [Connecting ──session done──▶] Building ──▶ Review ──▶ Placing ──▶ Placed
                                                   │            │  ▲
                                                   │            └──┘ rebuild (untick/restore)
                                                   └─ error / reconnect / cancel ──▶ Available
```

- **Build:** `POST api/groceries/cart` `{scoped, haveAlready ∪ ordered, isVegetarian}` —
  ordered names ride `haveAlready` so a second cart cannot re-buy what is on its way.
  `scoped` must serialize exactly like the webapp's `ScopedShoppingList`
  (`categorized` in category order, `ingredients`, `weights: {name: {amount, unit}}`).
- **Review:** "Delivering to" (tag chip + detail via `addressLabelFor`, address warning);
  lines with checkbox, thumbnail slot (https only), pack label · description × charged qty,
  Swiggy's line price only when present, low-confidence / repair / not-in-cart /
  quantity-mismatch notes; unserviceable box; misses ("buy these yourself"); "Removed from
  this order" with restore ticks; pinned footer with Swiggy's bill rows and To-pay, then
  Undo / Update cart while selections are pending, else Cancel / "Place COD order · ₹…";
  "Cash on delivery · Swiggy orders can't be cancelled once placed"; Powered by Swiggy.
  Not dismissable while placing.
- **Rebuild:** `POST api/groceries/cart/rebuild {lines, misses}` with kept lines from
  (current plan lines ∪ removed), union by spinId, current first; the rest become `removed`.
- **Checkout:** `POST api/groceries/checkout {expectedTotal, weekStartDate, items}`,
  `items` = in-cart priced lines as `{name: ingredient, display}`. `recorded: true` → the
  server saved it; `false` → the app PATCHes `orders` itself.
- **Placed:** total, order id, "cash on delivery", status label, "On its way (N)", "Still
  to buy yourself (N)" (misses ∪ unserviceable ∪ removed ∪ not-in-cart), "Back to shopping list".

Errors (every call): 409 `reconnect` → disconnected + "Reconnect Swiggy to order.";
409 `repriced`/`expired` → close review, server message; 429 → server message, no retry;
422 / anything else → server message or a per-call fallback.

## On the list

- `ShoppingList.orders` decoded from the existing get-shopping-list response.
- Ordered items are not "to buy" and carry an "Ordered" tag; have still wins. Counts:
  "N to buy · M ordered · K have" (M counted within the current day scope, as Android does).
- A strip above the list while an order is live: "N item(s) arriving from Instamart",
  Powered by Swiggy, and the countdown / status label / "Order placed".
- On showing the pane, live orders due for a refresh get one `GET api/groceries/order/{id}`
  each, sequentially; delivered items merge into `haveAlready`; one PATCH writes both.
- Share and Copy exclude ordered items (Share adds "N items ordered from Instamart").
- With Instamart offered it is the primary footer action; Share and Copy step aside; PDF stays.

## Where things live

| Place | Adds |
|---|---|
| KhanaKit `Models/` | `UserFeatures.swiggyInstamart`; `StoredOrder`, `OrderedItem`, `ShoppingList.orders`; cart wire models (`CartPlanLine`, `PricedCartLine`, `CartPlan`, `BillRow`, `InstamartCart`, `InstamartAddress`, `CartBuild`, `CheckoutResponse`) |
| KhanaKit `Logic/` | `Brand` capability + `canOrderInstamart`; `InstamartOrders` (port of `orders.ts`); `InstamartCartLogic`; `ShoppingScope` `ordered` parameter |
| KhanaKit `Networking/` | `Endpoints` for status/connect/cart/rebuild/checkout/order/geo and the orders PATCH; request DTOs; `InstamartFailure` mapping from status + body |
| App `Services/` | `InstamartRepository` |
| App `Features/Instamart/` | `InstamartViewModel`, the sheet (building / review / placed), `SwiggySignIn` (ASWebAuthenticationSession), `PoweredBySwiggy` |
| App `Features/ShoppingList/` | footer button, ordered rows, live strip, status sync |

## Out of scope

UPI, live tracking beyond one status fetch, any background work.
