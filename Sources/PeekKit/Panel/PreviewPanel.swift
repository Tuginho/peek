import AppKit
import SwiftUI

/// Floating, non-activating panel that shows window thumbnails above a hovered Dock icon.
/// Deliberately never becomes key so hovering the Dock never steals focus from the frontmost
/// app; `ClickableHostingView.acceptsFirstMouse` makes the first click on a cell still register
/// despite that.
final class PreviewPanel: NSPanel {
    init<V: View>(content: V) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMaskImage(cornerRadius: 14)
        effectView.autoresizingMask = [.width, .height]

        let hosting = ClickableHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = effectView.bounds
        effectView.addSubview(hosting)

        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bumped by `present` so a fade-out still in flight cannot order out a newer presentation.
    private var presentationGeneration = 0

    func present(at frame: NSRect) {
        presentationGeneration += 1
        setFrame(frame, display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.orderOut(nil)
        }
    }

    /// Resizable rounded-rect mask so the visual effect view's corners stay round at any size.
    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let diameter = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// The panel never becomes key, so without this override the first click on a cell would be
/// swallowed activating the window instead of registering as a click.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
