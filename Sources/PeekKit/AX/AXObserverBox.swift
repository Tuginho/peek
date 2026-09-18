import ApplicationServices
import Foundation

/// Wraps an `AXObserver` for a single process, dispatching notifications to a
/// Swift closure on the main thread.
public final class AXObserverBox {
    private var observer: AXObserver?
    private let handler: (AXElement, String) -> Void

    public init?(pid: pid_t, handler: @escaping (AXElement, String) -> Void) {
        self.handler = handler

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let box = Unmanaged<AXObserverBox>.fromOpaque(refcon).takeUnretainedValue()
            let axElement = AXElement(raw: element)
            let name = notification as String
            if Thread.isMainThread {
                box.handler(axElement, name)
            } else {
                DispatchQueue.main.async {
                    box.handler(axElement, name)
                }
            }
        }

        let error = AXObserverCreate(pid, callback, &observer)
        guard error == .success, let observer else { return nil }
        self.observer = observer

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    @discardableResult
    public func add(_ notification: String, to element: AXElement) -> Bool {
        guard let observer else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(observer, element.raw, notification as CFString, refcon)
        return error == .success || error == .notificationAlreadyRegistered
    }

    public func remove(_ notification: String, from element: AXElement) {
        guard let observer else { return }
        AXObserverRemoveNotification(observer, element.raw, notification as CFString)
    }

    deinit {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }
}
