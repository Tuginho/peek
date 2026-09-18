import AppKit
import Combine
import CoreGraphics
import Foundation

/// Drives the Dock hover preview panel: scheduling it after a hover delay, prefetching
/// thumbnails, positioning/resizing it, keeping it alive while the pointer travels to it, and
/// wiring the cell actions (select/hide/close).
@MainActor
final class PreviewPanelController {
    private enum State {
        case idle
        case pending(item: DockItem, showWorkItem: DispatchWorkItem)
        case showing(item: DockItem)
    }

    private let settings: Settings
    private let dockObserver: DockObserver
    private let windowManager: WindowManager
    private let store: HiddenWindowStore
    private let cache: ThumbnailCache
    private let capturer: WindowCapturing
    private let hider: WindowHider
    private let restorer: WindowRestorer

    private let model = PreviewModel()
    private var panel: PreviewPanel?

    private var state: State = .idle
    private var activeScreenFrame: CGRect = .zero
    /// Dock list frame (Cocoa coordinates) padded for magnified icons; `.infinite` if unknown.
    private var activeDockRect: CGRect = .infinite

    private var tickTimer: Timer?
    private var pendingSwitch: DispatchWorkItem?
    /// Pointer positions of the last ~200 ms (one per tick), oldest first.
    private var recentPointerSamples: [(time: TimeInterval, point: NSPoint)] = []
    private var lastMouseLocation: NSPoint?
    private var lastInsideTime = Date()

    private var inFlightCaptures: Set<URL> = []
    private var lastCaptureFinished: [URL: Date] = [:]

    private var storeSubscription: AnyCancellable?
    private var spaceChangeObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?

    init(
        settings: Settings,
        dockObserver: DockObserver,
        windowManager: WindowManager,
        store: HiddenWindowStore,
        cache: ThumbnailCache,
        capturer: WindowCapturing,
        hider: WindowHider,
        restorer: WindowRestorer
    ) {
        self.settings = settings
        self.dockObserver = dockObserver
        self.windowManager = windowManager
        self.store = store
        self.cache = cache
        self.capturer = capturer
        self.hider = hider
        self.restorer = restorer

        model.onSelect = { [weak self] item in self?.select(item) }
        model.onHide = { [weak self] item in
            Task { @MainActor [weak self] in await self?.hideItem(item) }
        }
        model.onClose = { [weak self] item in self?.closeItem(item) }
    }

    func start() {
        storeSubscription = store.$windowsByPID.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshStates() }
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissInternal() }
        }
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissInternal() }
        }
    }

    // MARK: - Hover

    func hoverChanged(_ item: DockItem?) {
        guard settings.hoverPreviewEnabled else {
            if case .pending(_, let workItem) = state { workItem.cancel() }
            if case .showing = state { dismissInternal() }
            state = .idle
            return
        }

        let effective: DockItem? = (item?.isRunning == false) ? nil : item

        switch effective {
        case let .some(newItem):
            switch state {
            case .showing(let shown):
                guard shown != newItem else {
                    cancelPendingSwitch()
                    return
                }
                if isPointerHeadingToPanel() {
                    scheduleSwitch(to: newItem)
                } else {
                    cancelPendingSwitch()
                    show(newItem)
                }
            case .pending(let pending, let workItem):
                guard pending != newItem else { return }
                workItem.cancel()
                schedulePending(newItem)
            case .idle:
                schedulePending(newItem)
            }
        case .none:
            switch state {
            case .pending(_, let workItem):
                workItem.cancel()
                state = .idle
            case .showing, .idle:
                cancelPendingSwitch()
                // the tick decides whether a `.showing` panel should close
            }
        }
    }

    // MARK: - Aiming at the panel

    /// The way from the icon to a thumbnail often crosses a neighbouring icon. Switching the
    /// panel at that moment (or closing it, if that app has no windows) would pull it away from
    /// under the pointer. So a hover change that happens while the pointer travels towards the
    /// panel only takes effect if the pointer then comes to rest on that icon.
    private func scheduleSwitch(to item: DockItem) {
        cancelPendingSwitch()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSwitch = nil
            guard case .showing = self.state, self.isPointer(over: item) else { return }
            self.show(item)
        }
        pendingSwitch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func cancelPendingSwitch() {
        pendingSwitch?.cancel()
        pendingSwitch = nil
    }

    private func isPointer(over item: DockItem) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let axFrame = dockObserver.currentFrame(of: item)
        else { return false }
        let frame = Geometry.cocoaRect(fromAX: axFrame, primaryScreenHeight: primaryHeight).insetBy(dx: -4, dy: -4)
        return frame.contains(NSEvent.mouseLocation)
    }

    /// Movement over the last ~200 ms points away from the Dock edge, at more than ~17° to it.
    private func isPointerHeadingToPanel() -> Bool {
        guard let oldest = recentPointerSamples.first else { return false }
        let now = NSEvent.mouseLocation
        let dx = now.x - oldest.point.x
        let dy = now.y - oldest.point.y
        switch model.edge {
        case .bottom: return dy > 3 && dy > abs(dx) * 0.3
        case .left: return dx > 3 && dx > abs(dy) * 0.3
        case .right: return dx < -3 && -dx > abs(dy) * 0.3
        }
    }

    private func schedulePending(_ item: DockItem) {
        let delay = TimeInterval(settings.hoverDelayMs) / 1000.0
        let workItem = DispatchWorkItem { [weak self] in self?.show(item) }
        state = .pending(item: item, showWorkItem: workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)

        let prefetchDelay = min(0.1, delay)
        // Skip the capture when the pointer merely swept across the icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + prefetchDelay) { [weak self] in
            guard let self else { return }
            switch self.state {
            case .pending(let pending, _) where pending == item:
                self.prefetch(item)
            case .showing(let shown) where shown == item:
                self.prefetch(item)
            default:
                break
            }
        }
    }

    // MARK: - Prefetch

    private func prefetch(_ item: DockItem) {
        let bundleURL = item.bundleURL
        guard !inFlightCaptures.contains(bundleURL) else { return }
        if let last = lastCaptureFinished[bundleURL], Date().timeIntervalSince(last) < 1.0 { return }

        let pids = runningPIDs(for: bundleURL)
        guard !pids.isEmpty else { return }
        let windows = pids.flatMap { windowManager.windows(of: $0) }.filter { !$0.isMinimized }
        guard !windows.isEmpty else { return }

        inFlightCaptures.insert(bundleURL)
        let boxSize = CGSize(width: settings.thumbnailSize.width, height: settings.thumbnailSize.height)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let images = await self.capturer.capture(windows, boxSize: boxSize, scale: 2)
            self.inFlightCaptures.remove(bundleURL)
            self.lastCaptureFinished[bundleURL] = Date()

            for (key, image) in images {
                guard let pid = windows.first(where: { $0.key == key })?.pid else { continue }
                self.cache.store(image, for: key, pid: pid)
            }

            if case .showing(let shown) = self.state, shown.bundleURL == bundleURL {
                self.updateModelImages(from: images)
            }
        }
    }

    private func updateModelImages(from images: [WindowKey: CGImage]) {
        for index in model.items.indices {
            if let image = images[model.items[index].window.key] {
                model.items[index].image = image
            }
        }
    }

    // MARK: - Show / layout

    private func show(_ item: DockItem) {
        let pids = runningPIDs(for: item.bundleURL)
        let windows = pids.flatMap { windowManager.windows(of: $0) }
        guard !windows.isEmpty else {
            dismissInternal()
            return
        }

        populateModel(appItem: item, pids: pids, windows: windows)

        guard let metrics = layoutMetrics(for: item, itemCount: model.items.count) else {
            dismissInternal()
            return
        }
        model.edge = metrics.edge
        activeScreenFrame = metrics.screenFrame
        if let listFrame = dockObserver.listFrame, let primaryHeight = NSScreen.screens.first?.frame.height {
            activeDockRect = Geometry.cocoaRect(fromAX: listFrame, primaryScreenHeight: primaryHeight)
                .insetBy(dx: -100, dy: -100)
        } else {
            activeDockRect = .infinite
        }

        ensurePanel()
        panel?.present(at: metrics.rect)

        state = .showing(item: item)
        startTick()
        prefetch(item)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        panel = PreviewPanel(content: PreviewView(model: model))
    }

    private func populateModel(appItem: DockItem, pids: [pid_t], windows: [WindowInfo]) {
        model.appName = appItem.title
        model.appIcon = NSWorkspace.shared.icon(forFile: appItem.bundleURL.path)
        model.thumbnailSize = settings.thumbnailSize
        model.items = orderedItems(windows: windows, pids: pids, appName: appItem.title)
    }

    private func orderedItems(windows: [WindowInfo], pids: [pid_t], appName: String) -> [PreviewWindowItem] {
        let appHidden = pids.contains { NSRunningApplication(processIdentifier: $0)?.isHidden == true }
        let visible = windows.filter { !$0.isMinimized && !store.isHidden($0) }
        let rest = windows.filter { $0.isMinimized || store.isHidden($0) }

        return (visible + rest).map { window in
            PreviewWindowItem(
                window: window,
                state: windowState(for: window, appHidden: appHidden),
                image: cache.image(for: window.key),
                appName: appName
            )
        }
    }

    private func windowState(for window: WindowInfo, appHidden: Bool) -> PreviewWindowState {
        if store.contains(key: window.key) { return .peekHidden }
        if window.isMinimized { return .minimized }
        if appHidden { return .appHidden }
        return .visible
    }

    private func layoutMetrics(
        for item: DockItem,
        itemCount: Int,
        edgeOverride: DockEdge? = nil
    ) -> (rect: CGRect, edge: DockEdge, screenFrame: CGRect)? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }

        let axFrame = dockObserver.currentFrame(of: item) ?? item.frame
        let cocoaItemFrame = Geometry.cocoaRect(fromAX: axFrame, primaryScreenHeight: primaryHeight)

        let screenFrames = NSScreen.screens.map(\.frame)
        let index = Geometry.screenIndex(containing: cocoaItemFrame, screenFrames: screenFrames)
        guard NSScreen.screens.indices.contains(index) else { return nil }
        let screen = NSScreen.screens[index]

        let edge = edgeOverride ?? Geometry.dockEdge(itemFrame: cocoaItemFrame, screenFrame: screen.frame)
        let thumbnail = CGSize(width: settings.thumbnailSize.width, height: settings.thumbnailSize.height)
        let panelSize = PreviewLayout.panelSize(count: itemCount, thumbnail: thumbnail, edge: edge, screenVisibleFrame: screen.visibleFrame)
        let rect = Geometry.panelFrame(panelSize: panelSize, itemFrame: cocoaItemFrame, edge: edge, screenVisibleFrame: screen.visibleFrame, gap: 8)

        return (rect, edge, screen.frame)
    }

    private func repositionPanel() {
        guard case .showing(let shown) = state, let panel else { return }
        guard let metrics = layoutMetrics(for: shown, itemCount: model.items.count, edgeOverride: model.edge) else { return }
        activeScreenFrame = metrics.screenFrame
        panel.setFrame(metrics.rect, display: true)
    }

    private func runningPIDs(for bundleURL: URL) -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL?.standardizedFileURL == bundleURL }
            .map(\.processIdentifier)
    }

    // MARK: - Keep-alive tick

    private func startTick() {
        lastMouseLocation = NSEvent.mouseLocation
        lastInsideTime = Date()
        recentPointerSamples = [(ProcessInfo.processInfo.systemUptime, NSEvent.mouseLocation)]
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard case .showing(let shown) = state, let panel else { return }

        let point = NSEvent.mouseLocation
        let moved = lastMouseLocation != point
        lastMouseLocation = point

        let now = ProcessInfo.processInfo.systemUptime
        recentPointerSamples.append((now, point))
        recentPointerSamples.removeAll { now - $0.time > 0.2 }

        let keepAlive = panel.frame.insetBy(dx: -6, dy: -6)
            .union(Geometry.corridor(panelFrame: panel.frame, edge: model.edge, screenFrame: activeScreenFrame))
        let inKeepAlive = keepAlive.contains(point)

        // The global monitor in DockObserver does not fire while the pointer is over our own
        // panel, so the tick re-reads the Dock's selection. Not only on movement: after a fast
        // sweep across icon and panel the pointer can come to rest before the Dock has cleared
        // its selection, and nothing would refresh the stale hover afterwards.
        if moved || !inKeepAlive {
            dockObserver.refreshHover()
        }

        // A hover only counts while the pointer can physically be on the Dock; guards against a
        // selection the Dock never clears.
        let dockHoverMatches = dockObserver.hoveredItem?.bundleURL == shown.bundleURL
            && activeDockRect.contains(point)

        if dockHoverMatches || inKeepAlive {
            lastInsideTime = Date()
        } else if Date().timeIntervalSince(lastInsideTime) > 0.2 {
            dismissInternal()
        }
    }

    // MARK: - Live state

    private func refreshStates() {
        guard case .showing = state else { return }
        for index in model.items.indices {
            let window = model.items[index].window
            let appHidden = NSRunningApplication(processIdentifier: window.pid)?.isHidden == true
            model.items[index].state = windowState(for: window, appHidden: appHidden)
        }
    }

    private func reloadShownApp() {
        guard case .showing(let shown) = state else { return }
        let pids = runningPIDs(for: shown.bundleURL)
        let windows = pids.flatMap { windowManager.windows(of: $0) }
        guard !windows.isEmpty else {
            dismissInternal()
            return
        }
        populateModel(appItem: shown, pids: pids, windows: windows)
        repositionPanel()
    }

    // MARK: - Actions

    private func select(_ item: PreviewWindowItem) {
        restorer.noteOwnActivation(item.window.pid)
        if let entry = store.entry(for: item.window.key) {
            restorer.restore(entry, raise: false)
        }
        windowManager.focus(item.window)
        dismissInternal()
    }

    private func hideItem(_ item: PreviewWindowItem) async {
        await hider.hide(item.window, focusNext: false)
        reloadShownApp()
    }

    private func closeItem(_ item: PreviewWindowItem) {
        guard windowManager.close(item.window) else {
            NSSound.beep()
            return
        }
        cache.remove(item.window.key)
        store.remove(key: item.window.key)
        model.items.removeAll { $0.id == item.id }
        if model.items.isEmpty {
            dismissInternal()
        } else {
            repositionPanel()
        }
    }

    // MARK: - Dismiss

    private func dismissInternal() {
        stopTick()
        cancelPendingSwitch()
        panel?.dismiss()
        state = .idle
    }

    func dismissForDockClick() {
        dismissInternal()
    }
}
