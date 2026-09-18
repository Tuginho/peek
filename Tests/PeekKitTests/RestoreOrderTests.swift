import Testing
@testable import PeekKit

struct RestoreOrderTests {
    @Test func peekHiddenOnlyReturnsHiddenInHideOrder() {
        let hidden: [WindowKey] = [.windowID(1), .windowID(2), .windowID(3)]
        let order = RestoreOrder.order(peekHidden: hidden, minimized: [], mode: .peekHiddenOnly)
        #expect(order == hidden)
    }

    @Test func allMinimizedPutsNonPeekWindowsFirst() {
        let hidden: [WindowKey] = [.windowID(1), .windowID(2)]
        let minimized: [WindowKey] = [.windowID(3), .windowID(1), .windowID(4), .windowID(2)]
        let order = RestoreOrder.order(peekHidden: hidden, minimized: minimized, mode: .allMinimized)
        #expect(order == [.windowID(3), .windowID(4), .windowID(1), .windowID(2)])
    }

    @Test func mostRecentlyHiddenIsLast() {
        let hidden: [WindowKey] = [.windowID(1), .windowID(2), .windowID(3)]

        let peekOnlyOrder = RestoreOrder.order(peekHidden: hidden, minimized: [], mode: .peekHiddenOnly)
        #expect(peekOnlyOrder.last == .windowID(3))

        let allMinimizedOrder = RestoreOrder.order(peekHidden: hidden, minimized: [.windowID(5)], mode: .allMinimized)
        #expect(allMinimizedOrder.last == .windowID(3))
    }

    @Test func noDuplicates() {
        let hidden: [WindowKey] = [.windowID(1), .windowID(2)]
        let minimized: [WindowKey] = [.windowID(1), .windowID(2), .windowID(3)]
        let order = RestoreOrder.order(peekHidden: hidden, minimized: minimized, mode: .allMinimized)
        #expect(order == [.windowID(3), .windowID(1), .windowID(2)])
        #expect(Set(order).count == order.count)
    }
}
