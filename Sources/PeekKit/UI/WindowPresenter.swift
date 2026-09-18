import AppKit
import SwiftUI

/// Hosts SwiftUI views in plain `NSWindow`s, keeping at most one window per id
/// so repeated calls (e.g. from the status menu) reuse the same window.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<V: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = NSRect(origin: .zero, size: size)

        if let window = windows[id] {
            window.contentView = hostingView
            window.title = title
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.center()
            windows[id] = window
        }

        NSApp.activate(ignoringOtherApps: true)
        windows[id]?.makeKeyAndOrderFront(nil)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    func isVisible(id: String) -> Bool {
        windows[id]?.isVisible ?? false
    }
}
