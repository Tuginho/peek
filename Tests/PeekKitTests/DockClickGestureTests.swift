import Testing
@testable import PeekKit

struct DockClickGestureTests {
    @Test func sameItemWithinDurationClicks() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: 1, hasModifiers: false, at: 0)
        let result = gesture.mouseUp(item: 1, at: 0.3)
        #expect(result == 1)
    }

    @Test func differentItemDoesNotClick() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: 1, hasModifiers: false, at: 0)
        let result = gesture.mouseUp(item: 2, at: 0.3)
        #expect(result == nil)
    }

    @Test func timeoutDoesNotClick() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: 1, hasModifiers: false, at: 0)
        let result = gesture.mouseUp(item: 1, at: 0.7)
        #expect(result == nil)
    }

    @Test func modifiersDoNotClick() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: 1, hasModifiers: true, at: 0)
        let result = gesture.mouseUp(item: 1, at: 0.1)
        #expect(result == nil)
    }

    @Test func nilItemDoesNotClick() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: nil, hasModifiers: false, at: 0)
        let result = gesture.mouseUp(item: 1, at: 0.1)
        #expect(result == nil)
    }

    @Test func mouseUpAlwaysClearsPendingState() {
        var gesture = DockClickGesture<Int>(maxDuration: 0.6)
        gesture.mouseDown(item: 1, hasModifiers: false, at: 0)
        _ = gesture.mouseUp(item: 1, at: 0.1) // consumes the pending mouseDown
        let result = gesture.mouseUp(item: 1, at: 0.2) // no mouseDown recorded since
        #expect(result == nil)
    }
}
