import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Draws a small click-through count badge over the Dock icon of every app that has
/// Peek-hidden windows. macOS offers no API to badge another app's Dock icon, so this owns one
/// borderless overlay panel per app, positioned above the Dock window level.
@MainActor
final class DockBadgeOverlay {
    private let store: HiddenWindowStore
    private let dockObserver: DockObserver
    private let settings: Settings

    private var panels: [URL: NSPanel] = [:]
    private var isHovering = false

    private var storeSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var screenParamsObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private var layoutWorkItem: DispatchWorkItem?

    init(store: HiddenWindowStore, dockObserver: DockObserver, settings: Settings) {
        self.store = store
        self.dockObserver = dockObserver
        self.settings = settings
    }

    func start() {
        storeSubscription = store.$windowsByPID.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleLayout(after: 0) }
        }
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change is applied, so read on the next tick.
            DispatchQueue.main.async { [weak self] in self?.scheduleLayout(after: 0) }
        }
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleLayout(after: 0) }
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

        scheduleLayout(after: 0)
    }

    /// Badges hide immediately while an icon is hovered (Dock magnification would otherwise
    /// misplace them) and reappear 400 ms after the pointer leaves, once the magnification
    /// animation has settled.
    func hoverChanged(_ item: DockItem?) {
        if item != nil {
            isHovering = true
            layoutWorkItem?.cancel()
            hideAll()
        } else {
            isHovering = false
            scheduleLayout(after: 0.4)
        }
    }

    private func handleWorkspaceChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == "com.apple.dock" {
            scheduleLayout(after: 2.5)
        } else {
            scheduleLayout(after: 0.7)
        }
    }

    private func scheduleLayout(after delay: TimeInterval) {
        layoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.layout() }
        layoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func layout() {
        guard settings.showDockBadges, !isHovering else {
            hideAll()
            return
        }

        let counts = hiddenCountsByBundleURL()
        var itemsByURL: [URL: DockItem] = [:]
        for item in dockObserver.appItems() {
            itemsByURL[item.bundleURL] = item
        }

        let screenFrames = NSScreen.screens.map(\.frame)
        guard let primaryHeight = screenFrames.first?.height else { return }

        for (url, count) in counts {
            guard count > 0, let item = itemsByURL[url] else { continue }
            let cocoaFrame = Geometry.cocoaRect(fromAX: item.frame, primaryScreenHeight: primaryHeight)
            let screenFrame = screenFrames[Geometry.screenIndex(containing: cocoaFrame, screenFrames: screenFrames)]
            let edge = Geometry.dockEdge(itemFrame: cocoaFrame, screenFrame: screenFrame)
            let badgeSize = Self.badgeSize(for: count)
            let frame = Geometry.badgeFrame(itemFrame: cocoaFrame, badgeSize: badgeSize, edge: edge)

            let panel = panelFor(url)
            (panel.contentView as? NSHostingView<BadgeView>)?.rootView = BadgeView(count: count)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }

        for (url, panel) in panels where counts[url] == nil || itemsByURL[url] == nil {
            panel.orderOut(nil)
            panels[url] = nil
        }
    }

    private func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    private func hiddenCountsByBundleURL() -> [URL: Int] {
        var counts: [URL: Int] = [:]
        for (pid, list) in store.windowsByPID where !list.isEmpty {
            guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL else { continue }
            counts[url, default: 0] += list.count
        }
        return counts
    }

    private func panelFor(_ url: URL) -> NSPanel {
        if let existing = panels[url] { return existing }
        let panel = Self.makeBadgePanel()
        panels[url] = panel
        return panel
    }

    private static func badgeSize(for count: Int) -> CGSize {
        let text = "\(count)" as NSString
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let textWidth = text.size(withAttributes: [.font: font]).width
        return CGSize(width: max(18, textWidth + 10), height: 18)
    }

    private static func makeBadgePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Deliberately NOT .fullScreenAuxiliary: there is no Dock in full-screen Spaces.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: BadgeView(count: 0))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}

private struct BadgeView: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(
                Capsule()
                    .fill(Color(white: 0.2, opacity: 0.95))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            )
    }
}
