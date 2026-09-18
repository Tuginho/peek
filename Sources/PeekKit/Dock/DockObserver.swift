import AppKit
import ApplicationServices
import Foundation

/// Tracks which Dock app icon is currently hovered via the Dock's own
/// `kAXSelectedChildrenChangedNotification`. `hoveredItem`/`onHoverChanged` drive both the hover
/// preview panel and the badge overlay.
@MainActor
public final class DockObserver {
    public var onHoverChanged: ((DockItem?) -> Void)?
    public private(set) var hoveredItem: DockItem?

    private var dockPid: pid_t?
    private var dockAppElement: AXElement?
    private var listElement: AXElement?
    private var observerBox: AXObserverBox?

    private var retryTimer: Timer?
    private var retryCount = 0
    private static let maxRetries = 10

    private var launchObserver: NSObjectProtocol?

    /// Safety net for hover-end: the Dock does not reliably fire a notification when the
    /// pointer just leaves the Dock without landing on another icon, so while something is
    /// hovered this monitor re-reads the selection on pointer movement. Removed as soon as
    /// nothing is hovered, so it never runs while idle.
    private var globalMonitor: Any?
    private var lastMonitorRefresh: TimeInterval = 0

    public init() {}

    deinit {
        retryTimer?.invalidate()
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }

    public func start() {
        resolve()

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleWorkspaceLaunch(notification) }
        }
    }

    private func handleWorkspaceLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.dock"
        else { return }

        observerBox = nil
        dockAppElement = nil
        listElement = nil
        dockPid = nil
        setHovered(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.retryCount = 0
                self.resolve()
            }
        }
    }

    private func resolve() {
        retryTimer?.invalidate()
        retryTimer = nil

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            scheduleRetry()
            return
        }
        let pid = dockApp.processIdentifier
        let appElement = AXElement.application(pid: pid)
        guard let list = appElement.children.first(where: { $0.role == "AXList" }) else {
            scheduleRetry()
            return
        }

        let observer = AXObserverBox(pid: pid) { [weak self] _, notification in
            guard notification == kAXSelectedChildrenChangedNotification else { return }
            self?.refreshHover()
        }
        guard let observer else {
            scheduleRetry()
            return
        }
        observer.add(kAXSelectedChildrenChangedNotification, to: list)

        dockPid = pid
        dockAppElement = appElement
        listElement = list
        observerBox = observer
        retryCount = 0

        refreshHover()
    }

    private func scheduleRetry() {
        guard retryCount < Self.maxRetries else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.retryCount += 1
                self.resolve()
            }
        }
    }

    public func refreshHover() {
        guard let listElement else { return }
        let selected = listElement.selectedChildren.first
        let newItem = selected.flatMap { DockItem(element: $0) }

        let changed: Bool
        switch (hoveredItem, newItem) {
        case (nil, nil):
            changed = false
        case (nil, .some), (.some, nil):
            changed = true
        case let (.some(old), .some(new)):
            changed = old != new
        }
        guard changed else { return }
        setHovered(newItem)
    }

    private func setHovered(_ item: DockItem?) {
        hoveredItem = item
        updateGlobalMonitor()
        onHoverChanged?(item)
    }

    private func updateGlobalMonitor() {
        if hoveredItem != nil, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleGlobalMonitorEvent() }
            }
        } else if hoveredItem == nil, let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func handleGlobalMonitorEvent() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMonitorRefresh >= 0.05 else { return }
        lastMonitorRefresh = now
        refreshHover()
    }

    /// Fresh `element.frame`, since Dock magnification continuously changes an icon's frame.
    public func currentFrame(of item: DockItem) -> CGRect? {
        item.element.frame
    }

    public func appItems() -> [DockItem] {
        guard let listElement else { return [] }
        return listElement.children.compactMap { DockItem(element: $0) }
    }

    public var listFrame: CGRect? {
        listElement?.frame
    }
}
