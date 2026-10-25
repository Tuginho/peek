import AppKit
import Foundation

/// Pure ordering logic for restoring several windows at once, kept separate from AX/AppKit so
/// it is unit testable.
public enum RestoreOrder {
    /// Order in which windows are deminiaturized; the LAST element ends up frontmost.
    /// `peekHidden` is in hide order (oldest first). Result for `.peekHiddenOnly` = `peekHidden`.
    /// Result for `.allMinimized` = minimized keys not in `peekHidden` (given order), then `peekHidden`.
    public static func order(peekHidden: [WindowKey], minimized: [WindowKey], mode: Settings.DockClickRestoreMode) -> [WindowKey] {
        switch mode {
        case .peekHiddenOnly:
            return peekHidden
        case .allMinimized:
            let peekHiddenSet = Set(peekHidden)
            let others = minimized.filter { !peekHiddenSet.contains($0) }
            return others + peekHidden
        }
    }
}

/// Restores windows Peek (and, in `.allMinimized` mode, the user) minimized, in an order that
/// leaves the most recently hidden window frontmost.
@MainActor
public final class WindowRestorer {
    private let store: HiddenWindowStore
    private let windowManager: WindowManager
    private let tracker: HiddenWindowTracker
    private let settings: Settings

    /// Suppresses `handleActivation` for a pid right after Peek itself triggers activation:
    /// the resulting `didActivateApplication` would otherwise be mistaken for a user click that
    /// should restore another window, while the just-restored window may still be animating and
    /// AX may still report it minimized.
    private var suppressedUntil: [pid_t: Date] = [:]

    init(store: HiddenWindowStore, windowManager: WindowManager, tracker: HiddenWindowTracker, settings: Settings) {
        self.store = store
        self.windowManager = windowManager
        self.tracker = tracker
        self.settings = settings
    }

    public func hasRestorableWindows(pid: pid_t, mode: Settings.DockClickRestoreMode) -> Bool {
        if store.count(for: pid) > 0 { return true }
        guard mode == .allMinimized else { return false }
        return windowManager.windows(of: pid).contains { $0.isMinimized }
    }

    /// Restores one hidden window (minimize: deminiaturize; park: move back to its original
    /// frame, relocated onto `fallbackScreenAX` if the display layout changed while it was
    /// parked), removes it from the store and stops tracking it. If the app could not answer
    /// (hung, or Accessibility revoked) the entry stays, so a later restore can retry instead of
    /// stranding the window parked with no record of it.
    @discardableResult
    public func restore(_ entry: HiddenWindow, raise: Bool) -> Bool {
        restoreResult(entry, raise: raise) == .success
    }

    private func restoreResult(_ entry: HiddenWindow, raise: Bool) -> AXError {
        let result: AXError
        switch entry.method {
        case .minimize:
            result = windowManager.setMinimizedResult(element: entry.element, false)
        case .park:
            let screenFramesAX = ScreenLayout.currentAXFrames()
            let fallbackAX = Self.currentMainScreenAXFrame()
            let target = Geometry.restoredOrigin(for: entry.originalFrame, screenFramesAX: screenFramesAX, fallbackScreenAX: fallbackAX)
            result = windowManager.setPositionResult(element: entry.element, target)
        }

        if Self.isTransientFailure(result) {
            return result
        }

        if raise {
            windowManager.raise(element: entry.element)
        }

        store.remove(key: entry.key)
        tracker.untrack(entry)
        return result
    }

    /// The app did not answer in time (hung or busy) or Accessibility was revoked: the window
    /// still exists, so its entry must survive for a later retry.
    private static func isTransientFailure(_ result: AXError) -> Bool {
        result == .cannotComplete || result == .apiDisabled
    }

    public func restoreAll(pid: pid_t, mode: Settings.DockClickRestoreMode) {
        let hiddenEntries = store.windows(for: pid)

        var elementsByKey: [WindowKey: AXElement] = [:]
        var entriesByKey: [WindowKey: HiddenWindow] = [:]
        for entry in hiddenEntries {
            elementsByKey[entry.key] = entry.element
            entriesByKey[entry.key] = entry
        }

        var minimizedKeys: [WindowKey] = []
        if mode == .allMinimized {
            for window in windowManager.windows(of: pid) where window.isMinimized {
                minimizedKeys.append(window.key)
                if elementsByKey[window.key] == nil {
                    elementsByKey[window.key] = window.element
                }
            }
        }

        let orderedKeys = RestoreOrder.order(peekHidden: hiddenEntries.map(\.key), minimized: minimizedKeys, mode: mode)
        guard !orderedKeys.isEmpty else { return }

        for key in orderedKeys {
            if let entry = entriesByKey[key] {
                // A hung app would make every remaining window wait out the AX timeout as well,
                // and raising or activating it would only block again.
                if Self.isTransientFailure(restoreResult(entry, raise: false)) { return }
            } else if let element = elementsByKey[key] {
                // A plain minimized window the user (not Peek) minimized: `.allMinimized` mode
                // deminiaturizes it too, but it was never tracked in the store.
                windowManager.setMinimized(element: element, false)
            }
        }
        if let lastElement = orderedKeys.compactMap({ elementsByKey[$0] }).last {
            windowManager.raise(element: lastElement)
        }

        noteOwnActivation(pid)
        windowManager.activateApp(pid: pid)
    }

    public func restoreLast(pid: pid_t) {
        guard let last = store.windows(for: pid).last else { return }
        restore(last, raise: true)
    }

    /// Restores every `.park` entry of every app without activating them; used on quit so
    /// parked windows don't stay stranded off-screen while Peek is not running.
    public func restoreAllParked() {
        for entries in store.windowsByPID.values {
            for entry in entries where entry.method == .park {
                if Self.isTransientFailure(restoreResult(entry, raise: false)) { break }
            }
        }
    }

    public func handleActivation(pid: pid_t) {
        guard settings.restoreOnActivate else { return }
        if let deadline = suppressedUntil[pid], deadline > Date() { return }
        guard store.count(for: pid) > 0 else { return }

        let liveWindows = windowManager.windows(of: pid)
        let hasVisibleWindow = liveWindows.contains { !$0.isMinimized && !store.isHidden($0) }
        guard !hasVisibleWindow else { return }

        restoreLast(pid: pid)
    }

    public func noteOwnActivation(_ pid: pid_t) {
        suppressedUntil[pid] = Date().addingTimeInterval(1.0)
    }

    private static func currentMainScreenAXFrame() -> CGRect {
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first,
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return .zero }
        return Geometry.axRect(fromCocoa: mainScreen.frame, primaryScreenHeight: primaryHeight)
    }
}
