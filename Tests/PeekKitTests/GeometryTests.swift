import CoreGraphics
import Foundation
import Testing
@testable import PeekKit

struct GeometryTests {
    @Test func cocoaRectFromAXFlipsAroundPrimaryHeight() {
        let axRect = CGRect(x: 100, y: 50, width: 200, height: 80)
        let cocoa = Geometry.cocoaRect(fromAX: axRect, primaryScreenHeight: 1080)
        #expect(cocoa == CGRect(x: 100, y: 1080 - 50 - 80, width: 200, height: 80))
    }

    @Test func cocoaRectHandlesDisplayAbovePrimary() {
        // Secondary display sits above the primary: AX y is negative there.
        let axRect = CGRect(x: 100, y: -200, width: 500, height: 300)
        let cocoa = Geometry.cocoaRect(fromAX: axRect, primaryScreenHeight: 1080)
        #expect(cocoa == CGRect(x: 100, y: 980, width: 500, height: 300))
        #expect(cocoa.maxY > 1080) // extends above the primary screen's top edge
    }

    @Test func pointRoundTripsThroughAXAndCocoa() {
        let points: [CGPoint] = [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 0, y: 0),
            CGPoint(x: -300, y: -150), // on a secondary display above the primary
            CGPoint(x: 1200, y: 900),
        ]
        for original in points {
            let cocoa = Geometry.cocoaPoint(fromAX: original, primaryScreenHeight: 1080)
            let backToAX = Geometry.axPoint(fromCocoa: cocoa, primaryScreenHeight: 1080)
            #expect(backToAX == original)
        }
    }

    @Test func dockEdgeIsBottomWhenItemIsNearestTheBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 900, y: 0, width: 48, height: 60)
        #expect(Geometry.dockEdge(itemFrame: item, screenFrame: screen) == .bottom)
    }

    @Test func dockEdgeIsLeftWhenItemIsNearestTheLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 0, y: 500, width: 60, height: 48)
        #expect(Geometry.dockEdge(itemFrame: item, screenFrame: screen) == .left)
    }

    @Test func dockEdgeIsRightWhenItemIsNearestTheRight() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 1860, y: 500, width: 60, height: 48)
        #expect(Geometry.dockEdge(itemFrame: item, screenFrame: screen) == .right)
    }

    @Test func panelFrameBottomEdgeCentersAboveItem() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 900, y: 0, width: 48, height: 60)
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 400, height: 200), itemFrame: item, edge: .bottom, screenVisibleFrame: screen, gap: 8)
        #expect(rect.midX == item.midX)
        #expect(rect.minY == item.maxY + 8)
        #expect(rect.size == CGSize(width: 400, height: 200))
    }

    @Test func panelFrameBottomEdgeClampsAtLeftEnd() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 10, y: 0, width: 48, height: 60) // near the left end of the Dock
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 400, height: 200), itemFrame: item, edge: .bottom, screenVisibleFrame: screen, gap: 8)
        #expect(rect.minX == screen.insetBy(dx: 8, dy: 8).minX)
    }

    @Test func panelFrameBottomEdgeClampsAtRightEnd() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 1860, y: 0, width: 48, height: 60) // near the right end of the Dock
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 400, height: 200), itemFrame: item, edge: .bottom, screenVisibleFrame: screen, gap: 8)
        #expect(rect.maxX == screen.insetBy(dx: 8, dy: 8).maxX)
    }

    @Test func panelFrameLeftEdgePlacesPanelToTheRightOfTheItem() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 0, y: 500, width: 60, height: 48)
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 300, height: 400), itemFrame: item, edge: .left, screenVisibleFrame: screen, gap: 8)
        #expect(rect.minX == item.maxX + 8)
        #expect(rect.midY == item.midY)
    }

    @Test func panelFrameRightEdgePlacesPanelToTheLeftOfTheItem() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let item = CGRect(x: 1860, y: 500, width: 60, height: 48)
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 300, height: 400), itemFrame: item, edge: .right, screenVisibleFrame: screen, gap: 8)
        #expect(rect.maxX == item.minX - 8)
        #expect(rect.midY == item.midY)
    }

    @Test func panelFrameOnSecondaryScreenWithNonZeroOrigin() {
        // Secondary screen positioned to the right of the primary, in Cocoa global space.
        let screen = CGRect(x: 1920, y: 0, width: 1600, height: 900)
        let item = CGRect(x: 2720, y: 0, width: 48, height: 60)
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 400, height: 200), itemFrame: item, edge: .bottom, screenVisibleFrame: screen, gap: 8)
        let inset = screen.insetBy(dx: 8, dy: 8)
        #expect(rect.midX == item.midX)
        #expect(rect.minX >= inset.minX)
        #expect(rect.maxX <= inset.maxX)
    }

    @Test func panelFrameOnSecondaryScreenClampsAtRightEnd() {
        let screen = CGRect(x: 1920, y: 0, width: 1600, height: 900)
        let item = CGRect(x: 1920 + 1550, y: 0, width: 48, height: 60) // near the right end of that screen
        let rect = Geometry.panelFrame(panelSize: CGSize(width: 400, height: 200), itemFrame: item, edge: .bottom, screenVisibleFrame: screen, gap: 8)
        #expect(rect.maxX == screen.insetBy(dx: 8, dy: 8).maxX)
    }

    @Test func corridorBottomEdgeSpansFromScreenBottomToPanel() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 700, y: 70, width: 400, height: 200)
        let corridor = Geometry.corridor(panelFrame: panel, edge: .bottom, screenFrame: screen)
        #expect(corridor.minX == panel.minX)
        #expect(corridor.width == panel.width)
        #expect(corridor.minY == screen.minY)
        #expect(corridor.maxY == panel.minY)
    }

    @Test func corridorLeftEdgeSpansFromScreenLeftToPanel() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 70, y: 400, width: 300, height: 400)
        let corridor = Geometry.corridor(panelFrame: panel, edge: .left, screenFrame: screen)
        #expect(corridor.minX == screen.minX)
        #expect(corridor.maxX == panel.minX)
        #expect(corridor.minY == panel.minY)
        #expect(corridor.height == panel.height)
    }

    @Test func corridorRightEdgeSpansFromPanelToScreenRight() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 1550, y: 400, width: 300, height: 400)
        let corridor = Geometry.corridor(panelFrame: panel, edge: .right, screenFrame: screen)
        #expect(corridor.minX == panel.maxX)
        #expect(corridor.maxX == screen.maxX)
        #expect(corridor.minY == panel.minY)
        #expect(corridor.height == panel.height)
    }

    @Test func iconTileIsAnchoredToTheScreenEdgeSide() {
        let bottom = Geometry.iconTile(itemFrame: CGRect(x: 500, y: 10, width: 48, height: 60), edge: .bottom)
        #expect(bottom == CGRect(x: 500, y: 10, width: 48, height: 48))

        let left = Geometry.iconTile(itemFrame: CGRect(x: 0, y: 300, width: 60, height: 48), edge: .left)
        #expect(left == CGRect(x: 0, y: 300, width: 48, height: 48))

        let right = Geometry.iconTile(itemFrame: CGRect(x: 1860, y: 300, width: 60, height: 48), edge: .right)
        #expect(right == CGRect(x: 1872, y: 300, width: 48, height: 48))
    }

    @Test func badgeFrameOverlapsTheTilesTopLeftCorner() {
        let item = CGRect(x: 500, y: 10, width: 48, height: 60)
        let tile = Geometry.iconTile(itemFrame: item, edge: .bottom)
        let badge = Geometry.badgeFrame(itemFrame: item, badgeSize: CGSize(width: 18, height: 18), edge: .bottom)
        #expect(badge.size == CGSize(width: 18, height: 18))
        #expect(badge.intersects(tile))
        #expect(badge.minX < tile.minX + 4 && badge.maxX > tile.minX + 8)
        #expect(badge.maxY > tile.maxY && badge.minY < tile.maxY - 8)
        #expect(badge.maxY < item.maxY)
    }

    @Test func screenIndexFindsScreenContainingCenter() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1600, height: 900),
        ]
        let rect = CGRect(x: 2000, y: 100, width: 400, height: 200)
        #expect(Geometry.screenIndex(containing: rect, screenFrames: screens) == 1)
    }

    @Test func screenIndexFallsBackToFirstWhenNoScreenContainsCenter() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1600, height: 900),
        ]
        let rect = CGRect(x: -500, y: -500, width: 10, height: 10)
        #expect(Geometry.screenIndex(containing: rect, screenFrames: screens) == 0)
    }

    @Test func axRectFromCocoaRoundTripsWithCocoaRectFromAX() {
        let rects: [CGRect] = [
            CGRect(x: 100, y: 50, width: 200, height: 80),
            CGRect(x: -300, y: 900, width: 1600, height: 900),
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        for original in rects {
            let cocoa = Geometry.cocoaRect(fromAX: original, primaryScreenHeight: 1080)
            let backToAX = Geometry.axRect(fromCocoa: cocoa, primaryScreenHeight: 1080)
            #expect(backToAX == original)
        }
    }

    // MARK: - Parking

    @Test func parkingOriginOnSingleScreenUsesBottomRight() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = Geometry.parkingOrigin(windowSize: CGSize(width: 800, height: 600), screenFramesAX: [screen])
        #expect(origin == CGPoint(x: screen.maxX - 1, y: screen.maxY - 1))
    }

    @Test func parkingOriginPicksPrimaryBottomRightWhenSecondaryIsStackedAbove() {
        // Secondary sits directly above the primary: negative AX y, maxY = 0.
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondaryAbove = CGRect(x: 0, y: -900, width: 1920, height: 900)
        let origin = Geometry.parkingOrigin(windowSize: CGSize(width: 800, height: 600), screenFramesAX: [primary, secondaryAbove])
        #expect(origin == CGPoint(x: primary.maxX - 1, y: primary.maxY - 1))
    }

    @Test func parkingOriginPicksRightScreenWhenItSitsAtTheSameHeightAsPrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1920, y: 0, width: 1600, height: 1080)
        let origin = Geometry.parkingOrigin(windowSize: CGSize(width: 800, height: 600), screenFramesAX: [primary, right])
        #expect(origin == CGPoint(x: right.maxX - 1, y: right.maxY - 1))
    }

    @Test func parkingOriginFallsBackToBottomLeftWhenBottomRightIsBlocked() {
        // `blocker` sits just to the right of `screen`'s bottom edge, low enough to trip the
        // bottom-right probes but with a smaller maxY so `screen` still sorts first.
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let blocker = CGRect(x: 1000, y: 900, width: 500, height: 99) // maxY = 999 < screen.maxY (1000)
        let origin = Geometry.parkingOrigin(windowSize: CGSize(width: 400, height: 300), screenFramesAX: [screen, blocker])
        #expect(origin == CGPoint(x: screen.minX - 400 + 1, y: screen.maxY - 1))
    }

    @Test func isParkedTrueForTheExactFrameProducedByParkingOrigin() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 800, height: 600)
        let origin = Geometry.parkingOrigin(windowSize: size, screenFramesAX: [screen])
        let parkedFrame = CGRect(origin: origin, size: size)
        #expect(Geometry.isParked(parkedFrame, screenFramesAX: [screen]))
    }

    @Test func isParkedTrueWhenMacOSClampsTheWindowTopAboveTheScreenBottom() {
        // Measured on macOS 26: requested y 1691, granted y 1594 on a 3008×1692 screen.
        let screen = CGRect(x: 0, y: 0, width: 3008, height: 1692)
        let frame = CGRect(x: 3007, y: 1594, width: 1584, height: 1186)
        #expect(Geometry.isParked(frame, screenFramesAX: [screen]))
    }

    @Test func isParkedFalseWhenMacOSPullsAnOffscreenWindowBack() {
        // Requesting x beyond the screen edge makes macOS pull the window back to 40 pt visible;
        // with a tolerance below that this must not count as parked.
        let screen = CGRect(x: 0, y: 0, width: 3008, height: 1692)
        let frame = CGRect(x: 2968, y: 1574, width: 1200, height: 762)
        #expect(Geometry.isParked(frame, screenFramesAX: [screen]) == false)
    }

    @Test func isParkedFalseForAWindowMostlyOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(Geometry.isParked(frame, screenFramesAX: [screen]) == false)
    }

    @Test func restoredOriginUnchangedWhenSufficientlyVisible() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let origin = Geometry.restoredOrigin(for: frame, screenFramesAX: [screen], fallbackScreenAX: screen)
        #expect(origin == frame.origin)
    }

    @Test func restoredOriginRelocatedWhenNotSufficientlyVisible() {
        let oldScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 1919, y: 1079, width: 800, height: 600) // almost entirely off-screen
        let fallback = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = Geometry.restoredOrigin(for: frame, screenFramesAX: [oldScreen], fallbackScreenAX: fallback)
        #expect(origin != frame.origin)
        #expect(origin.x == fallback.midX - frame.width / 2)
    }
}
