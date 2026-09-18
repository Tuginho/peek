import ApplicationServices
import CoreGraphics
import Foundation

/// A single Dock app icon, snapshotted at the moment it was read. `frame` is not kept fresh —
/// callers that need the current (possibly magnified) frame use `DockObserver.currentFrame(of:)`.
public struct DockItem: Equatable {
    public let element: AXElement
    public let title: String
    public let bundleURL: URL
    public let frame: CGRect
    public let isRunning: Bool

    /// Equality is element identity only: `frame` changes continuously under Dock magnification
    /// and must not affect whether two `DockItem`s are considered "the same icon".
    public static func == (lhs: DockItem, rhs: DockItem) -> Bool {
        lhs.element == rhs.element
    }

    public init?(element: AXElement) {
        guard element.subrole == "AXApplicationDockItem" else { return nil }
        guard let url = element.url?.standardizedFileURL else { return nil }
        guard let frame = element.frame else { return nil }

        self.element = element
        self.title = element.title ?? ""
        self.bundleURL = url
        self.frame = frame
        self.isRunning = element.boolAttribute("AXIsApplicationRunning") ?? false
    }
}
