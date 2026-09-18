import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Builds a plain-text diagnostic report covering permissions, the Dock AX tree,
/// window enumeration, ScreenCaptureKit access, event taps and app activation.
/// Every section is independently guarded so one failure does not abort the run.
@MainActor
public final class Diagnostics {
    private let windowManager: WindowManager

    public init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    private struct DiagError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private var isRunning = false

    public func run(progress: @escaping (String) -> Void) async -> String {
        guard !isRunning else { return "Diagnostics already running." }
        isRunning = true
        defer { isRunning = false }

        var report = ""

        func line(_ text: String) {
            report += text + "\n"
            progress(report)
        }
        func section(_ title: String) {
            line("")
            line("=== \(title) ===")
        }

        section("System")
        line("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        line("Bundle path: \(Bundle.main.bundlePath)")
        line("Running from .app bundle: \(Bundle.main.bundlePath.hasSuffix(".app"))")
        line("Window ID lookup available: \(PrivateAPI.isWindowIDLookupAvailable)")

        section("Permissions")
        line("Accessibility: \(Permissions.isGranted(.accessibility) ? "granted" : "not granted")")
        line("Screen Recording: \(Permissions.isGranted(.screenRecording) ? "granted" : "not granted")")
        line("Input Monitoring: \(Permissions.isGranted(.inputMonitoring) ? "granted" : "not granted")")

        section("Dock prefs")
        for key in ["orientation", "autohide", "minimize-to-application", "magnification"] {
            if let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) {
                line("\(key): \(value)")
            } else {
                line("\(key): (unset)")
            }
        }

        section("Dock AX tree")
        var dockListElement: AXElement?
        var dockPid: pid_t?
        do {
            guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
                throw DiagError(message: "Dock process not running")
            }
            let pid = dockApp.processIdentifier
            dockPid = pid
            line("Dock pid: \(pid)")
            let appElement = AXElement.application(pid: pid)
            let children = appElement.children
            line("App element children: \(children.count)")
            guard let list = children.first(where: { $0.role == "AXList" }) else {
                throw DiagError(message: "No AXList child found")
            }
            dockListElement = list
            let listChildren = list.children
            line("List children: \(listChildren.count)")
            var histogram: [String: Int] = [:]
            for child in listChildren {
                histogram[child.subrole ?? "(none)", default: 0] += 1
            }
            for (subrole, count) in histogram.sorted(by: { $0.key < $1.key }) {
                line("  subrole \(subrole): \(count)")
            }
            let appItems = listChildren.filter { $0.subrole == "AXApplicationDockItem" }
            for item in appItems.prefix(5) {
                let title = item.title ?? "(none)"
                let url = item.url?.absoluteString ?? "(none)"
                let frame = item.frame.map { "\($0)" } ?? "(none)"
                let running = item.boolAttribute("AXIsApplicationRunning").map { "\($0)" } ?? "(none)"
                line("  item title=\(title) url=\(url) frame=\(frame) running=\(running)")
            }
        } catch {
            line("FAIL: \(error)")
        }

        section("Dock hover notifications")
        if let dockPid, let dockListElement {
            var events: [(elapsedMs: Int, description: String)] = []
            let start = Date()
            let observer = AXObserverBox(pid: dockPid) { element, _ in
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                let selected = element.selectedChildren.first
                let description = selected.map { "\($0.title ?? "(no title)") / \($0.subrole ?? "(no subrole)")" } ?? "(none)"
                events.append((elapsed, description))
            }
            if let observer {
                observer.add(kAXSelectedChildrenChangedNotification, to: dockListElement)
                line(">>> Move the mouse across several Dock icons now (8 s)…")
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                for event in events {
                    line("  +\(event.elapsedMs)ms: \(event.description)")
                }
                line("Total notifications: \(events.count)")
                observer.remove(kAXSelectedChildrenChangedNotification, from: dockListElement)
            } else {
                line("FAIL: could not create AXObserver for Dock")
            }
        } else {
            line("FAIL: skipped, no Dock list element from previous section")
        }

        section("Windows")
        var collected: [(app: NSRunningApplication, window: WindowInfo)] = []
        let myPid = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != myPid
        }
        var totalWindows = 0
        var withWindowIDCount = 0
        var minimizedCount = 0
        for app in regularApps {
            let name = app.localizedName ?? "(unknown)"
            line("\(name) (pid \(app.processIdentifier))")
            let windows = windowManager.windows(of: app.processIdentifier)
            for window in windows {
                totalWindows += 1
                if window.windowID != nil { withWindowIDCount += 1 }
                if window.isMinimized { minimizedCount += 1 }
                collected.append((app, window))
                let windowIDText = window.windowID.map { "\($0)" } ?? "nil"
                line("  \"\(window.title)\" frame=\(window.frame) minimized=\(window.isMinimized) fullscreen=\(window.isFullScreen) canMinimize=\(window.canMinimize) windowID=\(windowIDText)")
            }
        }
        line("Total windows: \(totalWindows), with windowID: \(withWindowIDCount), minimized: \(minimizedCount)")

        section("ScreenCaptureKit")
        do {
            let start = Date()
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let duration = Date().timeIntervalSince(start)
            line("excludingDesktopWindows took \(Int(duration * 1000)) ms, windows: \(content.windows.count)")

            func capture(_ windowInfo: WindowInfo, label: String) async {
                guard let windowID = windowInfo.windowID,
                      let scWindow = content.windows.first(where: { $0.windowID == windowID })
                else {
                    line("\(label): FAIL: no matching SCWindow")
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = 560
                config.height = 350
                config.showsCursor = false
                config.scalesToFit = true
                config.ignoreShadowsSingleWindow = true
                do {
                    let captureStart = Date()
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let captureDuration = Date().timeIntervalSince(captureStart)
                    line("\(label): captured in \(Int(captureDuration * 1000)) ms, size \(image.width)x\(image.height)")
                } catch {
                    line("\(label): FAIL: \(error)")
                }
            }

            if let nonMinimized = collected.first(where: { !$0.window.isMinimized })?.window {
                await capture(nonMinimized, label: "Non-minimized window")
            } else {
                line("Non-minimized window: FAIL: none found")
            }

            if let minimizedEntry = collected.first(where: { $0.window.isMinimized && $0.window.windowID != nil }) {
                let listed = content.windows.contains { $0.windowID == minimizedEntry.window.windowID }
                line("Minimized window listed by SCK: \(listed)")
                await capture(minimizedEntry.window, label: "Minimized window")
            } else {
                line("no minimized window available – minimize one and re-run")
            }
        } catch {
            line("FAIL: \(error)")
        }

        section("Event taps")
        let passthroughCallback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: passthroughCallback,
            userInfo: nil
        ) {
            line("Key-down event tap created: yes")
            CFMachPortInvalidate(tap)
        } else {
            line("Key-down event tap created: no")
        }

        let mouseMask = CGEventMask((1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue))
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mouseMask,
            callback: passthroughCallback,
            userInfo: nil
        ) {
            line("Mouse listen-only event tap created: yes")
            CFMachPortInvalidate(tap)
        } else {
            line("Mouse listen-only event tap created: no")
        }

        section("Activation")
        // The real use case (click in a non-activating panel) activates another app while Peek
        // is NOT active. The diagnostics window made Peek active, so step back first.
        NSApp.hide(nil)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let previousFrontmost = NSWorkspace.shared.frontmostApplication
        line("Peek active during test: \(NSApp.isActive)")
        line("Frontmost before: \(previousFrontmost?.localizedName ?? "(none)")")
        defer {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if let candidateEntry = collected.first(where: { entry in
            entry.app.processIdentifier != previousFrontmost?.processIdentifier && !entry.window.isMinimized
        }) {
            let target = candidateEntry.app
            line("Target: \(target.localizedName ?? "(unknown)") (pid \(target.processIdentifier))")
            windowManager.focus(candidateEntry.window)
            try? await Task.sleep(nanoseconds: 600_000_000)
            let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            line("Frontmost matches target: \(frontmostPid == target.processIdentifier)")

            if let previousFrontmost {
                if let previousWindow = windowManager.focusedWindow(of: previousFrontmost.processIdentifier) {
                    windowManager.focus(previousWindow)
                } else {
                    previousFrontmost.activate()
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        } else {
            line("skipped")
        }

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Peek", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileURL = logsDir.appendingPathComponent("diagnose-\(formatter.string(from: Date())).log")
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            line(fileURL.path)
        } catch {
            line("FAIL: could not write log file: \(error)")
        }

        return report
    }
}
