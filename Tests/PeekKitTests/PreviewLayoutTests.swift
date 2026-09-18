import CoreGraphics
import Testing
@testable import PeekKit

struct PreviewLayoutTests {
    private let thumbnail = CGSize(width: 280, height: 175) // Settings.ThumbnailSize.medium

    @Test func cellSizeAddsInsetAndTitleHeight() {
        let size = PreviewLayout.cellSize(thumbnail: thumbnail)
        #expect(size.width == thumbnail.width + 2 * PreviewLayout.cellInset)
        #expect(size.height == thumbnail.height + 2 * PreviewLayout.cellInset + PreviewLayout.titleHeight)
    }

    @Test func contentSizeHorizontalForBottomEdge() {
        let count = 3
        let size = PreviewLayout.contentSize(count: count, thumbnail: thumbnail, edge: .bottom)
        let cell = PreviewLayout.cellSize(thumbnail: thumbnail)
        let expectedWidth = 2 * PreviewLayout.padding + CGFloat(count) * cell.width + CGFloat(count - 1) * PreviewLayout.spacing
        let expectedHeight = 2 * PreviewLayout.padding + PreviewLayout.headerHeight + cell.height
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test func contentSizeVerticalForLeftAndRightEdge() {
        let count = 4
        for edge in [DockEdge.left, .right] {
            let size = PreviewLayout.contentSize(count: count, thumbnail: thumbnail, edge: edge)
            let cell = PreviewLayout.cellSize(thumbnail: thumbnail)
            let expectedWidth = 2 * PreviewLayout.padding + cell.width
            let expectedHeight = 2 * PreviewLayout.padding + PreviewLayout.headerHeight
                + CGFloat(count) * cell.height + CGFloat(count - 1) * PreviewLayout.spacing
            #expect(size.width == expectedWidth)
            #expect(size.height == expectedHeight)
        }
    }

    @Test func contentSizeDiffersBetweenHorizontalAndVerticalLayout() {
        let horizontal = PreviewLayout.contentSize(count: 3, thumbnail: thumbnail, edge: .bottom)
        let vertical = PreviewLayout.contentSize(count: 3, thumbnail: thumbnail, edge: .left)
        #expect(horizontal.width > vertical.width)
        #expect(vertical.height > horizontal.height)
    }

    @Test func panelSizeClampsHorizontalContentToVisibleFrame() {
        let screen = CGRect(x: 0, y: 0, width: 600, height: 900)
        let count = 10 // wide enough to exceed the screen
        let content = PreviewLayout.contentSize(count: count, thumbnail: thumbnail, edge: .bottom)
        #expect(content.width > screen.width - 40) // sanity: unclamped content really is too wide

        let size = PreviewLayout.panelSize(count: count, thumbnail: thumbnail, edge: .bottom, screenVisibleFrame: screen)
        #expect(size.width == screen.width - 40)
        #expect(size.height == content.height) // only the layout axis is clamped
    }

    @Test func panelSizeClampsVerticalContentToVisibleFrame() {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 500)
        let count = 10
        let content = PreviewLayout.contentSize(count: count, thumbnail: thumbnail, edge: .left)
        #expect(content.height > screen.height - 40)

        let size = PreviewLayout.panelSize(count: count, thumbnail: thumbnail, edge: .left, screenVisibleFrame: screen)
        #expect(size.height == screen.height - 40)
        #expect(size.width == content.width)
    }

    @Test func panelSizeDoesNotClampWhenContentFits() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = PreviewLayout.panelSize(count: 2, thumbnail: thumbnail, edge: .bottom, screenVisibleFrame: screen)
        let content = PreviewLayout.contentSize(count: 2, thumbnail: thumbnail, edge: .bottom)
        #expect(size == content)
    }
}
