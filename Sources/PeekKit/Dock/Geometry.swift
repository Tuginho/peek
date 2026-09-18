import CoreGraphics
import Foundation

/// Which edge of the screen the Dock sits at. Only these three are possible Dock positions.
public enum DockEdge: Equatable {
    case bottom, left, right
}

/// Pure coordinate-space and layout math shared by the Dock hover preview and the badge
/// overlay. No AppKit state is read here — everything (screen frames, sizes) is passed in, so
/// this is fully unit testable without a display.
public enum Geometry {
    /// AX/CGEvent coordinates are global, top-left origin. AppKit coordinates are global,
    /// bottom-left origin relative to the primary screen. The flip is a single subtraction
    /// against the primary screen's height, valid everywhere including displays above the
    /// primary (which have negative AX y).
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    public static func cocoaPoint(fromAX point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    public static func axPoint(fromCocoa point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// AX frame of a Cocoa screen frame; self-inverse, same formula as `cocoaRect(fromAX:)`.
    public static func axRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Edge of `screenFrame` closest to the item's center (only bottom/left/right are possible
    /// Dock positions).
    public static func dockEdge(itemFrame: CGRect, screenFrame: CGRect) -> DockEdge {
        let center = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        let distanceToBottom = center.y - screenFrame.minY
        let distanceToLeft = center.x - screenFrame.minX
        let distanceToRight = screenFrame.maxX - center.x

        let minDistance = min(distanceToBottom, distanceToLeft, distanceToRight)
        if minDistance == distanceToBottom { return .bottom }
        if minDistance == distanceToLeft { return .left }
        return .right
    }

    /// Panel origin/size in Cocoa coordinates, placed just outside the Dock, then clamped onto
    /// the screen along the axis parallel to the Dock edge.
    public static func panelFrame(
        panelSize: CGSize,
        itemFrame: CGRect,
        edge: DockEdge,
        screenVisibleFrame: CGRect,
        gap: CGFloat
    ) -> CGRect {
        let origin: CGPoint
        switch edge {
        case .bottom:
            let x = itemFrame.midX - panelSize.width / 2
            let y = max(itemFrame.maxY, screenVisibleFrame.minY) + gap
            origin = CGPoint(x: x, y: y)
        case .left:
            let x = max(itemFrame.maxX, screenVisibleFrame.minX) + gap
            let y = itemFrame.midY - panelSize.height / 2
            origin = CGPoint(x: x, y: y)
        case .right:
            let x = min(itemFrame.minX, screenVisibleFrame.maxX) - gap - panelSize.width
            let y = itemFrame.midY - panelSize.height / 2
            origin = CGPoint(x: x, y: y)
        }

        var rect = CGRect(origin: origin, size: panelSize)
        let inset = screenVisibleFrame.insetBy(dx: 8, dy: 8)
        switch edge {
        case .bottom:
            if rect.minX < inset.minX { rect.origin.x = inset.minX }
            if rect.maxX > inset.maxX { rect.origin.x = inset.maxX - rect.width }
        case .left, .right:
            if rect.minY < inset.minY { rect.origin.y = inset.minY }
            if rect.maxY > inset.maxY { rect.origin.y = inset.maxY - rect.height }
        }
        return rect
    }

    /// Region between the screen edge and the panel (spanning the panel's own extent along the
    /// Dock axis), so the pointer can travel from the icon to the panel without leaving the
    /// keep-alive area.
    public static func corridor(panelFrame: CGRect, edge: DockEdge, screenFrame: CGRect) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(
                x: panelFrame.minX,
                y: screenFrame.minY,
                width: panelFrame.width,
                height: max(0, panelFrame.minY - screenFrame.minY)
            )
        case .left:
            return CGRect(
                x: screenFrame.minX,
                y: panelFrame.minY,
                width: max(0, panelFrame.minX - screenFrame.minX),
                height: panelFrame.height
            )
        case .right:
            return CGRect(
                x: panelFrame.maxX,
                y: panelFrame.minY,
                width: max(0, screenFrame.maxX - panelFrame.maxX),
                height: panelFrame.height
            )
        }
    }

    /// Badge overlapping the icon tile's top-left corner (Cocoa coordinates: top = maxY),
    /// mirroring where the system's own badge sits top-right.
    public static func badgeFrame(itemFrame: CGRect, badgeSize: CGSize, edge: DockEdge) -> CGRect {
        let tile = iconTile(itemFrame: itemFrame, edge: edge)
        let centerX = tile.minX + tile.width * 0.2
        let centerY = tile.maxY - tile.height * 0.15
        let origin = CGPoint(
            x: (centerX - badgeSize.width / 2).rounded(),
            y: (centerY - badgeSize.height / 2).rounded()
        )
        return CGRect(origin: origin, size: badgeSize)
    }

    /// A Dock item's AX frame is larger than its icon tile: it carries extra padding on the side
    /// facing the screen center (measured 48×60 pt for a 48 pt tile in a bottom Dock). The tile is
    /// the square anchored to the screen-edge side of the frame.
    public static func iconTile(itemFrame: CGRect, edge: DockEdge) -> CGRect {
        let side = min(itemFrame.width, itemFrame.height)
        switch edge {
        case .bottom:
            return CGRect(x: itemFrame.midX - side / 2, y: itemFrame.minY, width: side, height: side)
        case .left:
            return CGRect(x: itemFrame.minX, y: itemFrame.midY - side / 2, width: side, height: side)
        case .right:
            return CGRect(x: itemFrame.maxX - side, y: itemFrame.midY - side / 2, width: side, height: side)
        }
    }

    /// Screen (by frame) containing the rect's center; falls back to the first.
    public static func screenIndex(containing rect: CGRect, screenFrames: [CGRect]) -> Int {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screenFrames.firstIndex { $0.contains(center) } ?? 0
    }

    // MARK: - Parking (animation-free hide)

    /// Origin (AX coordinates) that leaves 1 pt of the window visible in a screen corner that has
    /// no neighbouring display. Candidates in order: bottom-right then bottom-left corner of each
    /// screen, screens sorted by maxY descending then maxX descending. Falls back to the first
    /// candidate if no corner is free.
    public static func parkingOrigin(windowSize: CGSize, screenFramesAX: [CGRect]) -> CGPoint {
        guard !screenFramesAX.isEmpty else { return .zero }

        let sortedScreens = screenFramesAX.sorted { lhs, rhs in
            if lhs.maxY != rhs.maxY { return lhs.maxY > rhs.maxY }
            return lhs.maxX > rhs.maxX
        }

        var fallback: CGPoint?
        for screen in sortedScreens {
            let bottomRight = CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)
            if fallback == nil { fallback = bottomRight }
            if isBottomRightCornerFree(of: screen, screenFramesAX: screenFramesAX) {
                return bottomRight
            }

            let bottomLeft = CGPoint(x: screen.minX - windowSize.width + 1, y: screen.maxY - 1)
            if isBottomLeftCornerFree(of: screen, screenFramesAX: screenFramesAX) {
                return bottomLeft
            }
        }

        return fallback ?? .zero
    }

    /// A corner is free when none of the three probe points 2 pt outside it (right/left, below,
    /// diagonal) lies inside any screen frame, i.e. no other display sits right there.
    private static func isBottomRightCornerFree(of screen: CGRect, screenFramesAX: [CGRect]) -> Bool {
        let probes = [
            CGPoint(x: screen.maxX + 2, y: screen.maxY - 2), // right
            CGPoint(x: screen.maxX - 2, y: screen.maxY + 2), // below
            CGPoint(x: screen.maxX + 2, y: screen.maxY + 2), // diagonal
        ]
        return !probes.contains { point in screenFramesAX.contains { $0.contains(point) } }
    }

    private static func isBottomLeftCornerFree(of screen: CGRect, screenFramesAX: [CGRect]) -> Bool {
        let probes = [
            CGPoint(x: screen.minX - 2, y: screen.maxY - 2), // left
            CGPoint(x: screen.minX + 2, y: screen.maxY + 2), // below
            CGPoint(x: screen.minX - 2, y: screen.maxY + 2), // diagonal
        ]
        return !probes.contains { point in screenFramesAX.contains { $0.contains(point) } }
    }

    /// True when on every screen the visible part of the rect is at most `tolerance` pt in at
    /// least one dimension, i.e. only a sliver of the window is on-screen.
    public static func isParked(_ frameAX: CGRect, screenFramesAX: [CGRect], tolerance: CGFloat = 20) -> Bool {
        for screen in screenFramesAX {
            let intersection = frameAX.intersection(screen)
            guard !intersection.isNull else { continue }
            // A sliver in ONE dimension is enough: macOS keeps a window's top ~100 pt above the
            // screen bottom (measured on macOS 26: y clamps to ~1594 of 1692), so a parked window
            // is 1 pt wide but ~100 pt tall on screen.
            if intersection.width > tolerance && intersection.height > tolerance {
                return false
            }
        }
        return true
    }

    /// Returns `origin` unchanged if the rect intersects some screen by at least 80×40 pt;
    /// otherwise an origin that centers the rect's top area on `fallbackScreenAX` (used when the
    /// display layout changed while a window was parked).
    public static func restoredOrigin(for frameAX: CGRect, screenFramesAX: [CGRect], fallbackScreenAX: CGRect) -> CGPoint {
        let sufficientlyVisible = screenFramesAX.contains { screen in
            let intersection = frameAX.intersection(screen)
            return !intersection.isNull && intersection.width >= 80 && intersection.height >= 40
        }
        if sufficientlyVisible {
            return frameAX.origin
        }

        return CGPoint(x: fallbackScreenAX.midX - frameAX.width / 2, y: fallbackScreenAX.minY + 40)
    }
}
