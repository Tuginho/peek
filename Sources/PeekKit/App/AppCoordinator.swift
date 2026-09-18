import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator {
    private let settings = Settings()
    private let windowManager = WindowManager()
    private lazy var statusItemController = StatusItemController(settings: settings)
    private let windowPresenter = WindowPresenter()
    private lazy var diagnostics = Diagnostics(windowManager: windowManager)

    private var permissionCheckTimer: Timer?
    private(set) var servicesStarted = false

    private var thumbnailCache: ThumbnailCache?
    private var hiddenWindowStore: HiddenWindowStore?
    private var hiddenWindowTracker: HiddenWindowTracker?
    private var windowCapturer: SCKWindowCapturer?
    private var windowRestorer: WindowRestorer?
    private var windowHider: WindowHider?
    private var eventTapThread: EventTapThread?
    private var hotkeyInterceptor: HotkeyInterceptor?
    private var dockClickMonitor: DockClickMonitor?
    private var dockObserver: DockObserver?
    private var previewPanelController: PreviewPanelController?
    private var dockBadgeOverlay: DockBadgeOverlay?

    private var settingsChangeObserver: AnyCancellable?
    private var activationObserver: NSObjectProtocol?

    func start() {
        AXElement.setGlobalMessagingTimeout(0.5)

        statusItemController.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItemController.onOpenPermissions = { [weak self] in self?.openPermissions() }
        statusItemController.onRunDiagnostics = { [weak self] in self?.openDiagnostics() }

        if !Permissions.isGranted(.accessibility) || !Permissions.isGranted(.screenRecording) {
            openPermissions()
        }

        startServicesIfPermitted()

        if !Permissions.isGranted(.accessibility) {
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.startServicesIfPermitted()
                    if Permissions.isGranted(.accessibility) {
                        self.permissionCheckTimer?.invalidate()
                        self.permissionCheckTimer = nil
                    }
                }
            }
        }
    }

    func startServicesIfPermitted() {
        guard Permissions.isGranted(.accessibility), !servicesStarted else { return }
        servicesStarted = true

        let thumbnailCache = ThumbnailCache()
        let hiddenWindowStore = HiddenWindowStore()
        let hiddenWindowTracker = HiddenWindowTracker(store: hiddenWindowStore, cache: thumbnailCache)
        let windowCapturer = SCKWindowCapturer()
        let windowRestorer = WindowRestorer(store: hiddenWindowStore, windowManager: windowManager, tracker: hiddenWindowTracker, settings: settings)
        let windowHider = WindowHider(
            windowManager: windowManager,
            store: hiddenWindowStore,
            tracker: hiddenWindowTracker,
            cache: thumbnailCache,
            capturer: windowCapturer,
            settings: settings
        )
        let eventTapThread = EventTapThread()
        let hotkeyInterceptor = HotkeyInterceptor(tapThread: eventTapThread, hider: windowHider)
        let dockClickMonitor = DockClickMonitor(tapThread: eventTapThread, restorer: windowRestorer, settings: settings)

        self.thumbnailCache = thumbnailCache
        self.hiddenWindowStore = hiddenWindowStore
        self.hiddenWindowTracker = hiddenWindowTracker
        self.windowCapturer = windowCapturer
        self.windowRestorer = windowRestorer
        self.windowHider = windowHider
        self.eventTapThread = eventTapThread
        self.hotkeyInterceptor = hotkeyInterceptor
        self.dockClickMonitor = dockClickMonitor

        hiddenWindowStore.restorePersisted(using: windowManager)
        for windows in hiddenWindowStore.windowsByPID.values {
            for window in windows {
                hiddenWindowTracker.track(window)
            }
        }

        statusItemController.hiddenWindowsProvider = { [weak hiddenWindowStore] in
            guard let hiddenWindowStore else { return [] }
            return hiddenWindowStore.windowsByPID.map { pid, windows in
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "PID \(pid)"
                return (pid: pid, name: name, count: windows.count)
            }
        }
        statusItemController.onRestoreApp = { [weak windowRestorer] pid in
            windowRestorer?.restoreAll(pid: pid, mode: .peekHiddenOnly)
        }

        eventTapThread.updateSnapshot { snapshot in
            snapshot.ownPID = ProcessInfo.processInfo.processIdentifier
            snapshot.hotkeyEnabled = settings.singleWindowHideEnabled
            snapshot.excludedBundleIDs = Set(settings.excludedBundleIDs)
            let frontmost = NSWorkspace.shared.frontmostApplication
            snapshot.frontmostBundleID = frontmost?.bundleIdentifier
            snapshot.frontmostPID = frontmost?.processIdentifier ?? 0
        }

        settingsChangeObserver = settings.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change is applied, so read on the next tick.
            DispatchQueue.main.async {
                guard let self, let eventTapThread = self.eventTapThread else { return }
                eventTapThread.updateSnapshot { snapshot in
                    snapshot.hotkeyEnabled = self.settings.singleWindowHideEnabled
                    snapshot.excludedBundleIDs = Set(self.settings.excludedBundleIDs)
                }
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventTapThread?.updateSnapshot { snapshot in
                    snapshot.frontmostBundleID = app.bundleIdentifier
                    snapshot.frontmostPID = app.processIdentifier
                }
                self.windowRestorer?.handleActivation(pid: app.processIdentifier)
            }
        }

        if !eventTapThread.start() {
            openPermissions()
        }

        dockClickMonitor.start()

        let dockObserver = DockObserver()
        let previewPanelController = PreviewPanelController(
            settings: settings,
            dockObserver: dockObserver,
            windowManager: windowManager,
            store: hiddenWindowStore,
            cache: thumbnailCache,
            capturer: windowCapturer,
            hider: windowHider,
            restorer: windowRestorer
        )
        let dockBadgeOverlay = DockBadgeOverlay(store: hiddenWindowStore, dockObserver: dockObserver, settings: settings)

        dockObserver.onHoverChanged = { [weak previewPanelController, weak dockBadgeOverlay] item in
            previewPanelController?.hoverChanged(item)
            dockBadgeOverlay?.hoverChanged(item)
        }

        dockClickMonitor.dockObserver = dockObserver
        dockClickMonitor.onDockAppClicked = { [weak previewPanelController] in
            previewPanelController?.dismissForDockClick()
        }

        self.dockObserver = dockObserver
        self.previewPanelController = previewPanelController
        self.dockBadgeOverlay = dockBadgeOverlay

        previewPanelController.start()
        dockBadgeOverlay.start()
        dockObserver.start()
    }

    func prepareForTermination() {
        windowRestorer?.restoreAllParked()
    }

    private func openSettings() {
        windowPresenter.show(id: "settings", title: "Peek – Einstellungen", size: NSSize(width: 480, height: 480)) {
            SettingsView(settings: self.settings)
        }
    }

    private func openPermissions() {
        windowPresenter.show(id: "permissions", title: "Peek – Berechtigungen", size: NSSize(width: 480, height: 360)) {
            PermissionsView()
        }
    }

    private func openDiagnostics() {
        windowPresenter.show(id: "diagnostics", title: "Peek – Diagnose", size: NSSize(width: 640, height: 480)) {
            DiagnosticsView(diagnostics: self.diagnostics)
        }
    }
}
