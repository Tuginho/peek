import ApplicationServices
import AppKit
import Foundation

/// Keeps `HiddenWindowStore` in sync with reality: drops an entry when its window closes or is
/// deminiaturized outside of Peek, and clears everything for an app that quits. One
/// `AXObserverBox` per pid, released once that pid has no hidden windows left.
@MainActor
final class HiddenWindowTracker {
    private let store: HiddenWindowStore
    private let cache: ThumbnailCache
    private var observers: [pid_t: AXObserverBox] = [:]
    private var terminationObserver: NSObjectProtocol?

    init(store: HiddenWindowStore, cache: ThumbnailCache) {
        self.store = store
        self.cache = cache

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in self?.appTerminated(pid: app.processIdentifier) }
        }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func track(_ window: HiddenWindow) {
        let pid = window.pid
        let observer = observers[pid] ?? AXObserverBox(pid: pid) { [weak self] element, notification in
            self?.handle(notification: notification, element: element, pid: pid)
        }
        guard let observer else { return }
        observers[pid] = observer
        observer.add(kAXUIElementDestroyedNotification, to: window.element)
        observer.add(kAXWindowDeminiaturizedNotification, to: window.element)
        if window.method == .park {
            observer.add(kAXWindowMovedNotification, to: window.element)
        }
    }

    func untrack(_ window: HiddenWindow) {
        guard let observer = observers[window.pid] else { return }
        observer.remove(kAXUIElementDestroyedNotification, from: window.element)
        observer.remove(kAXWindowDeminiaturizedNotification, from: window.element)
        observer.remove(kAXWindowMovedNotification, from: window.element)
    }

    func appTerminated(pid: pid_t) {
        store.removeAll(pid: pid)
        cache.removeAll(pid: pid)
        observers[pid] = nil
    }

    private func handle(notification: String, element: AXElement, pid: pid_t) {
        if notification == kAXUIElementDestroyedNotification {
            if let removed = store.remove(element: element) {
                cache.remove(removed.key)
            }
        } else if notification == kAXWindowDeminiaturizedNotification {
            // Keep the thumbnail: the window is visible again, not hidden by the user.
            store.remove(element: element)
        } else if notification == kAXWindowMovedNotification {
            // The window came back on-screen by other means (user, app, display
            // reconfiguration) — or this is Peek's own restore, in which case the entry is
            // already gone and this is a harmless no-op.
            if let frame = element.frame, !Geometry.isParked(frame, screenFramesAX: ScreenLayout.currentAXFrames()) {
                store.remove(element: element)
            }
        }

        if store.count(for: pid) == 0 {
            observers[pid] = nil
        }
    }
}
