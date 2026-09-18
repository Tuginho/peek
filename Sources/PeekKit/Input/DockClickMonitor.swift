import AppKit
import CoreGraphics
import Foundation

/// Detects a plain click on a Dock app icon (via the mouse taps in `EventTapThread`) and
/// restores that app's Peek-hidden windows. Also keeps the tap's Dock hit-test rect current.
@MainActor
final class DockClickMonitor {
    private let tapThread: EventTapThread
    private let restorer: WindowRestorer
    private let settings: Settings

    /// When set, hover resolution (from `DockObserver`, which already tracks the selected Dock
    /// item) is preferred over the tap thread's own hit-test, since it is cheaper and already
    /// current.
    weak var dockObserver: DockObserver?
    var onDockAppClicked: (() -> Void)?

    private var dockPid: pid_t?
    private var dockAppElement: AXElement?
    private var dockListElement: AXElement?

    private var gesture = DockClickGesture<AXElement>()

    private var screenParamsObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private var rectRetryTimer: Timer?
    private var rectRetryCount = 0
    private static let maxRectRetries = 6
    private var recomputeWorkItem: DispatchWorkItem?
    private var dockRelaunchWorkItem: DispatchWorkItem?

    init(tapThread: EventTapThread, restorer: WindowRestorer, settings: Settings) {
        self.tapThread = tapThread
        self.restorer = restorer
        self.settings = settings
    }

    func start() {
        tapThread.onMouseDown = { [weak self] point, flags in
            self?.handleMouseDown(point: point, flags: flags)
        }
        tapThread.onMouseUp = { [weak self] point in
            self?.handleMouseUp(point: point)
        }

        resolveDock()
        recomputeDockRect()

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeDockRect() }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        launchObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleWorkspaceChange(notification) }
        }
        terminateObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleWorkspaceChange(notification) }
        }
    }

    private func handleWorkspaceChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == "com.apple.dock" {
            scheduleDockRelaunch()
        } else {
            scheduleRecompute(after: 0.5)
        }
    }

    private func scheduleRecompute(after delay: TimeInterval) {
        recomputeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.recomputeDockRect() }
        recomputeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleDockRelaunch() {
        dockRelaunchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resolveDock()
            self?.recomputeDockRect()
        }
        dockRelaunchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func resolveDock() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            dockPid = nil
            dockAppElement = nil
            dockListElement = nil
            return
        }
        let pid = dockApp.processIdentifier
        dockPid = pid
        let appElement = AXElement.application(pid: pid)
        dockAppElement = appElement
        dockListElement = appElement.children.first { $0.role == "AXList" }
    }

    /// Dock magnification enlarges icons beyond the resting frame, hence the generous inset.
    private func recomputeDockRect() {
        guard let dockListElement, let frame = dockListElement.frame else {
            tapThread.updateSnapshot { $0.dockRect = .null }
            scheduleRectRetry()
            return
        }
        rectRetryTimer?.invalidate()
        rectRetryTimer = nil
        rectRetryCount = 0
        let padded = frame.insetBy(dx: -120, dy: -120)
        tapThread.updateSnapshot { $0.dockRect = padded }
    }

    /// Bounded so an unresolvable Dock does not leave a timer running forever; launch, screen and
    /// Dock-relaunch notifications trigger a fresh attempt anyway.
    private func scheduleRectRetry() {
        guard rectRetryTimer == nil, rectRetryCount < Self.maxRectRetries else { return }
        rectRetryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rectRetryTimer = nil
                self.rectRetryCount += 1
                self.resolveDock()
                self.recomputeDockRect()
            }
        }
    }

    private func handleMouseDown(point: CGPoint, flags: CGEventFlags) {
        let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let hasModifiers = !flags.intersection(modifierMask).isEmpty
        gesture.mouseDown(item: resolvedItem(at: point), hasModifiers: hasModifiers, at: ProcessInfo.processInfo.systemUptime)
    }

    private func handleMouseUp(point: CGPoint) {
        guard let clicked = gesture.mouseUp(item: resolvedItem(at: point), at: ProcessInfo.processInfo.systemUptime) else { return }
        onDockAppClicked?()
        restoreApps(for: clicked)
        scheduleRecompute(after: 1.0)
    }

    /// The hovered item is only trusted when the click really lands on it. The Dock keeps its
    /// selection for a while after the pointer has moved on, e.g. into the preview panel, and the
    /// panel lies inside the padded Dock rect — a click on a thumbnail must not count as a click
    /// on the Dock icon (it would restore every hidden window instead of the chosen one).
    private func resolvedItem(at point: CGPoint) -> AXElement? {
        if let hovered = dockObserver?.hoveredItem?.element, hovered.frame?.contains(point) == true {
            return hovered
        }
        return dockItem(at: point)
    }

    private func dockItem(at point: CGPoint) -> AXElement? {
        guard let dockAppElement, let hit = dockAppElement.element(at: point), hit.subrole == "AXApplicationDockItem" else {
            return nil
        }
        return hit
    }

    private func restoreApps(for item: AXElement) {
        guard let url = item.url?.standardizedFileURL else { return }
        let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == url }
        for app in matches {
            restorer.restoreAll(pid: app.processIdentifier, mode: settings.dockClickRestoreMode)
        }
    }
}
