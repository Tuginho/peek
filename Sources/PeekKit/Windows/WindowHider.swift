import AppKit
import CoreGraphics
import Foundation

/// Hides a single window (Cmd+H's replacement for `NSRunningApplication.hide()`): captures a
/// thumbnail, hides it (parks it off-screen or minimizes it, per `Settings.hideMethod`),
/// remembers it in `HiddenWindowStore`, and raises the app's next window. Every failure path
/// falls back to `app?.hide()`, i.e. stock Cmd+H behaviour.
@MainActor
public final class WindowHider {
    private let windowManager: WindowManager
    private let store: HiddenWindowStore
    private let tracker: HiddenWindowTracker
    private let cache: ThumbnailCache
    private let capturer: WindowCapturing
    private let settings: Settings

    /// Serializes hide requests: each call waits for the previous one before running.
    private var pending: Task<Void, Never>?

    init(
        windowManager: WindowManager,
        store: HiddenWindowStore,
        tracker: HiddenWindowTracker,
        cache: ThumbnailCache,
        capturer: WindowCapturing,
        settings: Settings
    ) {
        self.windowManager = windowManager
        self.store = store
        self.tracker = tracker
        self.cache = cache
        self.capturer = capturer
        self.settings = settings
    }

    public func hideFocusedWindow(of pid: pid_t) {
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            await self?.performHide(pid)
        }
    }

    private func performHide(_ pid: pid_t) async {
        let app = NSRunningApplication(processIdentifier: pid)
        guard let window = windowManager.focusedWindow(of: pid),
              !window.isFullScreen,
              !window.isMinimized,
              window.canMove || window.canMinimize
        else {
            app?.hide()
            return
        }
        await hide(window, focusNext: true)
    }

    public func hide(_ window: WindowInfo, focusNext: Bool) async {
        let app = NSRunningApplication(processIdentifier: window.pid)

        // Use the preferred method if it is possible; otherwise fall back to the other one.
        let usePark = settings.hideMethod == .park ? window.canMove : (!window.canMinimize && window.canMove)

        if usePark {
            await hideByParking(window, app: app, focusNext: focusNext)
        } else if window.canMinimize {
            await hideByMinimizing(window, app: app, focusNext: focusNext)
        } else {
            app?.hide()
        }
    }

    private func hideByMinimizing(_ window: WindowInfo, app: NSRunningApplication?, focusNext: Bool) async {
        let capturedImage = await withTimeout(0.25, { [capturer, settings] in
            let images = await capturer.capture(
                [window],
                boxSize: CGSize(width: settings.thumbnailSize.width, height: settings.thumbnailSize.height),
                scale: 2
            )
            return images[window.key]
        }, onLateResult: { [weak self] image in
            guard let self, !self.cache.contains(window.key) else { return }
            self.cache.store(image, for: window.key, pid: window.pid)
        })
        if let capturedImage {
            cache.store(capturedImage, for: window.key, pid: window.pid)
        }

        guard windowManager.setMinimized(window, true) else {
            app?.hide()
            return
        }

        let hiddenWindow = HiddenWindow(
            key: window.key,
            pid: window.pid,
            bundleID: app?.bundleIdentifier,
            element: window.element,
            windowID: window.windowID,
            title: window.title,
            hiddenAt: Date(),
            method: .minimize,
            originalFrame: window.frame
        )
        store.add(hiddenWindow)
        tracker.track(hiddenWindow)

        guard focusNext else { return }
        raiseNextOrHide(pid: window.pid, excluding: window.key, app: app)
    }

    private func hideByParking(_ window: WindowInfo, app: NSRunningApplication?, focusNext: Bool) async {
        // The capture is position-independent, so it is started unstructured and not awaited:
        // awaiting it would delay the (otherwise instant) hide. The result lands in the cache
        // whenever it arrives.
        Task { [weak self] in
            guard let self else { return }
            let images = await self.capturer.capture(
                [window],
                boxSize: CGSize(width: self.settings.thumbnailSize.width, height: self.settings.thumbnailSize.height),
                scale: 2
            )
            if let image = images[window.key] {
                self.cache.store(image, for: window.key, pid: window.pid)
            }
        }

        let originalFrame = window.frame
        let screenFramesAX = ScreenLayout.currentAXFrames()
        let target = Geometry.parkingOrigin(windowSize: originalFrame.size, screenFramesAX: screenFramesAX)

        let didSet = windowManager.setPosition(element: window.element, target)
        // Some apps apply an AX position change asynchronously, so give the frame a moment to
        // catch up before concluding that the move was refused.
        var parked = false
        if didSet {
            for attempt in 0..<4 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 40_000_000) }
                if let liveFrame = window.element.frame, Geometry.isParked(liveFrame, screenFramesAX: screenFramesAX) {
                    parked = true
                    break
                }
            }
        }

        guard parked else {
            // The app or macOS clamped the position (e.g. a non-standard window manager
            // integration) — put it back and fall back to minimizing.
            windowManager.setPosition(element: window.element, originalFrame.origin)
            if window.canMinimize {
                await hideByMinimizing(window, app: app, focusNext: focusNext)
            } else {
                app?.hide()
            }
            return
        }

        let hiddenWindow = HiddenWindow(
            key: window.key,
            pid: window.pid,
            bundleID: app?.bundleIdentifier,
            element: window.element,
            windowID: window.windowID,
            title: window.title,
            hiddenAt: Date(),
            method: .park,
            originalFrame: originalFrame
        )
        store.add(hiddenWindow)
        tracker.track(hiddenWindow)

        guard focusNext else { return }
        raiseNextOrHide(pid: window.pid, excluding: window.key, app: app)
    }

    private func raiseNextOrHide(pid: pid_t, excluding key: WindowKey, app: NSRunningApplication?) {
        let others = windowManager.windows(of: pid)
        if let next = others.first(where: { $0.key != key && !$0.isMinimized && !store.isHidden($0) }) {
            windowManager.raise(next)
        } else {
            app?.hide()
        }
    }
}
