import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Reads and manipulates windows through the Accessibility API.
@MainActor
public final class WindowManager {
    public init() {}

    /// The single source of truth for "which windows does this app have" — later milestones
    /// (e.g. multi-Space support) extend this rather than adding a second window enumerator.
    public func windows(of pid: pid_t) -> [WindowInfo] {
        let app = AXElement.application(pid: pid)
        return app.windows.compactMap { makeInfo(for: $0, pid: pid) }
    }

    public func focusedWindow(of pid: pid_t) -> WindowInfo? {
        let app = AXElement.application(pid: pid)
        let focused: AXUIElement? = app.attribute(kAXFocusedWindowAttribute)
        guard let raw = focused ?? app.attribute(kAXMainWindowAttribute) else { return nil }
        return makeInfo(for: AXElement(raw: raw), pid: pid)
    }

    @discardableResult
    public func setMinimized(_ window: WindowInfo, _ minimized: Bool) -> Bool {
        setMinimized(element: window.element, minimized)
    }

    @discardableResult
    public func setMinimized(element: AXElement, _ minimized: Bool) -> Bool {
        element.setAttribute(kAXMinimizedAttribute, minimized as CFBoolean)
    }

    @discardableResult
    public func setPosition(element: AXElement, _ point: CGPoint) -> Bool {
        element.setPosition(point)
    }

    @discardableResult
    public func close(_ window: WindowInfo) -> Bool {
        guard let closeButton: AXUIElement = window.element.attribute(kAXCloseButtonAttribute) else { return false }
        return AXElement(raw: closeButton).performAction(kAXPressAction)
    }

    public func raise(_ window: WindowInfo) {
        raise(element: window.element)
    }

    public func raise(element: AXElement) {
        element.performAction(kAXRaiseAction)
        element.setAttribute(kAXMainAttribute, true as CFBoolean)
    }

    public func focus(_ window: WindowInfo) {
        if window.isMinimized {
            setMinimized(window, false)
        }
        raise(window)
        activateApp(pid: window.pid)
    }

    /// Unhides the app if hidden, sets it frontmost via AX, then activates it via AppKit.
    public func activateApp(pid: pid_t) {
        let runningApp = NSRunningApplication(processIdentifier: pid)
        if runningApp?.isHidden == true {
            runningApp?.unhide()
        }

        let app = AXElement.application(pid: pid)
        app.setAttribute(kAXFrontmostAttribute, true as CFBoolean)

        runningApp?.activate()
    }

    func makeInfo(for element: AXElement, pid: pid_t) -> WindowInfo? {
        guard element.role == kAXWindowRole else { return nil }
        guard let subrole = element.subrole,
              subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
        else { return nil }

        let frame = element.frame ?? .zero
        let windowID = element.windowID
        let title = element.title ?? ""
        let key = WindowKey(windowID: windowID, pid: pid, title: title, frame: frame)

        let hasMinimizeButton: AXUIElement? = element.attribute(kAXMinimizeButtonAttribute)
        let canMinimize = hasMinimizeButton != nil && element.isAttributeSettable(kAXMinimizedAttribute)
        let canMove = element.isAttributeSettable(kAXPositionAttribute)

        return WindowInfo(
            key: key,
            pid: pid,
            element: element,
            windowID: windowID,
            title: title,
            frame: frame,
            isMinimized: element.isMinimized,
            isFullScreen: element.isFullScreen,
            canMinimize: canMinimize,
            canMove: canMove
        )
    }
}
