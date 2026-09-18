import Foundation

/// Recognizes a plain click (down + up on the same item, within a time window, no modifiers)
/// from the raw mouse-down/mouse-up events the event tap reports. Pure and side-effect free.
public struct DockClickGesture<ItemID: Equatable> {
    private let maxDuration: TimeInterval
    private var pendingDown: (item: ItemID, time: TimeInterval)?

    public init(maxDuration: TimeInterval = 0.6) {
        self.maxDuration = maxDuration
    }

    public mutating func mouseDown(item: ItemID?, hasModifiers: Bool, at time: TimeInterval) {
        guard let item, !hasModifiers else {
            pendingDown = nil
            return
        }
        pendingDown = (item, time)
    }

    /// Returns the clicked item when down and up hit the same item within `maxDuration` and
    /// without modifiers. A mouseUp always clears the pending state.
    public mutating func mouseUp(item: ItemID?, at time: TimeInterval) -> ItemID? {
        defer { pendingDown = nil }

        guard let pendingDown, let item, pendingDown.item == item else { return nil }
        guard time - pendingDown.time <= maxDuration else { return nil }
        return item
    }
}
