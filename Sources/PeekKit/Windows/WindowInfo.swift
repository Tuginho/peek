import CoreGraphics
import Foundation

public enum WindowKey: Hashable {
    case windowID(CGWindowID)
    case fallback(pid: pid_t, title: String, x: Int, y: Int, width: Int, height: Int)

    public init(windowID: CGWindowID?, pid: pid_t, title: String, frame: CGRect) {
        if let windowID {
            self = .windowID(windowID)
        } else {
            self = .fallback(
                pid: pid,
                title: title,
                x: Int(frame.origin.x.rounded()),
                y: Int(frame.origin.y.rounded()),
                width: Int(frame.size.width.rounded()),
                height: Int(frame.size.height.rounded())
            )
        }
    }
}

public struct WindowInfo: Identifiable {
    public var id: WindowKey { key }

    public let key: WindowKey
    public let pid: pid_t
    public let element: AXElement
    public let windowID: CGWindowID?
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let canMinimize: Bool
    public let canMove: Bool

    public init(
        key: WindowKey,
        pid: pid_t,
        element: AXElement,
        windowID: CGWindowID?,
        title: String,
        frame: CGRect,
        isMinimized: Bool,
        isFullScreen: Bool,
        canMinimize: Bool,
        canMove: Bool
    ) {
        self.key = key
        self.pid = pid
        self.element = element
        self.windowID = windowID
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.canMinimize = canMinimize
        self.canMove = canMove
    }
}
