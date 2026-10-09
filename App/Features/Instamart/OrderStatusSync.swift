import Foundation
import KhanaKit

/// One order's fresh status, stamped with when it was read.
struct OrderStatusUpdate: Hashable {
    var read: StatusRead
    var checkedAt: String
}

/// What a sync changed. Write `haveAlready` only when `haveChanged`.
struct OrderSyncResult: Hashable {
    var orders: [StoredOrder]
    var haveAlready: Set<String>
    var haveChanged: Bool
}

/// The foreground delivery-status refresh — port of the webapp's
/// `syncOrderStatuses` via Android's `OrderStatusSync` — split into its I/O
/// half and its pure half so the caller can apply the result to the list *as
/// it is when the reads come back*, not as it was when they started. The user
/// may tick items or place another order while the requests are in flight,
/// and applying to a stale snapshot would undo that.
enum OrderStatusSync {

    /// Live orders whose last check is at least a minute old.
    static func due(_ orders: [StoredOrder], nowMillis: Int64) -> [StoredOrder] {
        orders.filter { InstamartOrders.shouldRefresh($0, nowMillis: nowMillis) }
    }

    /// One status read per order, sequentially — never in parallel, so a week
    /// with several orders cannot burst Swiggy's rate limit. A failed fetch or
    /// an unreadable payload is skipped: the order keeps its old status and its
    /// old checkedAt, so it stays due and the next showing tries again. A
    /// tracking hiccup is not the user's problem and not actionable, so nothing
    /// is shown.
    @MainActor
    static func fetch(
        _ due: [StoredOrder],
        nowMillis: () -> Int64,
        fetchStatus: (String) async throws -> JSONValue
    ) async -> [String: OrderStatusUpdate] {
        var updates: [String: OrderStatusUpdate] = [:]
        for order in due {
            guard !Task.isCancelled else { break }
            guard let raw = try? await fetchStatus(order.orderId) else { continue }
            // Read at receipt time: the ETA is anchored to the moment we heard it.
            let now = nowMillis()
            guard let read = InstamartOrders.readOrderStatus(raw, nowMillis: now) else { continue }
            updates[order.orderId] = OrderStatusUpdate(
                read: read, checkedAt: InstamartOrders.toISOString(epochMillis: now)
            )
        }
        return updates
    }

    /// Apply `updates` to the current `orders` and fold delivered items into
    /// `haveAlready`. Nil when no update matches an order still on the list —
    /// nothing to show, nothing to write.
    static func apply(
        orders: [StoredOrder],
        haveAlready: Set<String>,
        updates: [String: OrderStatusUpdate]
    ) -> OrderSyncResult? {
        guard orders.contains(where: { updates[$0.orderId] != nil }) else { return nil }
        let next = orders.map { order in
            updates[order.orderId].map {
                InstamartOrders.withStatus(order, read: $0.read, nowISO: $0.checkedAt)
            } ?? order
        }
        let merged = InstamartOrders.mergeDeliveredIntoHave(orders: next, haveAlready: haveAlready)
        return OrderSyncResult(orders: next, haveAlready: merged.haveAlready, haveChanged: merged.changed)
    }
}
