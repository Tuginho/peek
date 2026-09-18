import CoreGraphics
import Testing
@testable import PeekKit

struct WindowKeyTests {
    @Test func picksWindowIDWhenGiven() {
        let key = WindowKey(windowID: 42, pid: 100, title: "Title", frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(key == .windowID(42))
    }

    @Test func fallbackRoundsFrame() {
        let key = WindowKey(
            windowID: nil,
            pid: 100,
            title: "Title",
            frame: CGRect(x: 1.4, y: 2.6, width: 3.5, height: 4.49)
        )
        #expect(key == .fallback(pid: 100, title: "Title", x: 1, y: 3, width: 4, height: 4))
    }

    @Test func equalInputsHashEqual() {
        let a = WindowKey(windowID: nil, pid: 1, title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = WindowKey(windowID: nil, pid: 1, title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func differingTitleDiffers() {
        let a = WindowKey(windowID: nil, pid: 1, title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = WindowKey(windowID: nil, pid: 1, title: "B", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(a != b)
    }
}
