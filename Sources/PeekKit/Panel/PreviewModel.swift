import AppKit
import CoreGraphics
import Foundation

public enum PreviewWindowState: Equatable {
    case visible, peekHidden, minimized, appHidden
}

public struct PreviewWindowItem: Identifiable {
    public var id: WindowKey { window.key }

    public let window: WindowInfo
    public var state: PreviewWindowState
    public var image: CGImage?
    public var displayTitle: String

    public init(window: WindowInfo, state: PreviewWindowState, image: CGImage?, appName: String) {
        self.window = window
        self.state = state
        self.image = image
        self.displayTitle = window.title.isEmpty ? appName : window.title
    }
}

/// Backs the SwiftUI preview panel content. Owned by `PreviewPanelController`, which is the
/// only writer; the view only reads and forwards user actions through the closures.
@MainActor
public final class PreviewModel: ObservableObject {
    @Published public var appName: String
    @Published public var appIcon: NSImage?
    @Published public var items: [PreviewWindowItem]
    @Published public var edge: DockEdge
    @Published public var thumbnailSize: Settings.ThumbnailSize

    public var onSelect: ((PreviewWindowItem) -> Void)?
    public var onHide: ((PreviewWindowItem) -> Void)?
    public var onClose: ((PreviewWindowItem) -> Void)?

    public init(
        appName: String = "",
        appIcon: NSImage? = nil,
        items: [PreviewWindowItem] = [],
        edge: DockEdge = .bottom,
        thumbnailSize: Settings.ThumbnailSize = .medium
    ) {
        self.appName = appName
        self.appIcon = appIcon
        self.items = items
        self.edge = edge
        self.thumbnailSize = thumbnailSize
    }
}

/// Pure, testable panel layout math. Kept separate from `PreviewModel` so it can be unit tested
/// without SwiftUI or AppKit state.
public enum PreviewLayout {
    public static let padding: CGFloat = 12
    public static let spacing: CGFloat = 10
    public static let headerHeight: CGFloat = 26
    public static let titleHeight: CGFloat = 20
    public static let cellInset: CGFloat = 6

    public static func cellSize(thumbnail: CGSize) -> CGSize {
        CGSize(
            width: thumbnail.width + 2 * cellInset,
            height: thumbnail.height + 2 * cellInset + titleHeight
        )
    }

    /// Unclamped content size for `count` cells laid out horizontally (bottom edge) or
    /// vertically (left/right).
    public static func contentSize(count: Int, thumbnail: CGSize, edge: DockEdge) -> CGSize {
        let cell = cellSize(thumbnail: thumbnail)
        guard count > 0 else {
            return CGSize(width: 2 * padding, height: headerHeight + 2 * padding)
        }
        switch edge {
        case .bottom:
            let width = 2 * padding + CGFloat(count) * cell.width + CGFloat(count - 1) * spacing
            let height = 2 * padding + headerHeight + cell.height
            return CGSize(width: width, height: height)
        case .left, .right:
            let width = 2 * padding + cell.width
            let height = 2 * padding + headerHeight + CGFloat(count) * cell.height + CGFloat(count - 1) * spacing
            return CGSize(width: width, height: height)
        }
    }

    /// `contentSize` clamped to `screenVisibleFrame` minus 40 pt along the layout axis (the
    /// view scrolls beyond that).
    public static func panelSize(count: Int, thumbnail: CGSize, edge: DockEdge, screenVisibleFrame: CGRect) -> CGSize {
        let content = contentSize(count: count, thumbnail: thumbnail, edge: edge)
        switch edge {
        case .bottom:
            let maxWidth = max(0, screenVisibleFrame.width - 40)
            return CGSize(width: min(content.width, maxWidth), height: content.height)
        case .left, .right:
            let maxHeight = max(0, screenVisibleFrame.height - 40)
            return CGSize(width: content.width, height: min(content.height, maxHeight))
        }
    }
}
