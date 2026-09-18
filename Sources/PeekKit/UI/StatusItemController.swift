import AppKit
import ServiceManagement

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onRunDiagnostics: (() -> Void)?
    var hiddenWindowsProvider: (() -> [(pid: pid_t, name: String, count: Int)])?
    var onRestoreApp: ((pid_t) -> Void)?

    private let settings: Settings
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(settings: Settings) {
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Peek")
            image?.isTemplate = true
            button.image = image
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hoverPreviewItem = NSMenuItem(title: "Hover-Vorschau", action: #selector(toggleHoverPreview), keyEquivalent: "")
        hoverPreviewItem.target = self
        hoverPreviewItem.state = settings.hoverPreviewEnabled ? .on : .off
        menu.addItem(hoverPreviewItem)

        let singleWindowHideItem = NSMenuItem(title: "Cmd+H nur für aktuelles Fenster", action: #selector(toggleSingleWindowHide), keyEquivalent: "")
        singleWindowHideItem.target = self
        singleWindowHideItem.state = settings.singleWindowHideEnabled ? .on : .off
        menu.addItem(singleWindowHideItem)

        menu.addItem(.separator())

        let hiddenWindowsHeaderItem = NSMenuItem(title: "Versteckte Fenster", action: nil, keyEquivalent: "")
        hiddenWindowsHeaderItem.isEnabled = false
        menu.addItem(hiddenWindowsHeaderItem)

        let hiddenApps = hiddenWindowsProvider?() ?? []
        if hiddenApps.isEmpty {
            let noneItem = NSMenuItem(title: "Keine", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            menu.addItem(noneItem)
        } else {
            for entry in hiddenApps {
                let item = NSMenuItem(title: "\(entry.name) (\(entry.count))", action: #selector(restoreApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.pid
                menu.addItem(item)
            }
        }

        let hoverDelayItem = NSMenuItem(title: "Hover-Verzögerung", action: nil, keyEquivalent: "")
        hoverDelayItem.submenu = hoverDelaySubmenu()
        menu.addItem(hoverDelayItem)

        let thumbnailSizeItem = NSMenuItem(title: "Thumbnail-Größe", action: nil, keyEquivalent: "")
        thumbnailSizeItem.submenu = thumbnailSizeSubmenu()
        menu.addItem(thumbnailSizeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Berechtigungen…", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let diagnosticsItem = NSMenuItem(title: "Diagnose ausführen", action: #selector(runDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Beim Login starten", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Peek beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func hoverDelaySubmenu() -> NSMenu {
        let submenu = NSMenu()
        for preset in Settings.hoverDelayPresets {
            let item = NSMenuItem(title: "\(preset) ms", action: #selector(selectHoverDelay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset
            item.state = settings.hoverDelayMs == preset ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func thumbnailSizeSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for size in Settings.ThumbnailSize.allCases {
            let item = NSMenuItem(title: size.label, action: #selector(selectThumbnailSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = settings.thumbnailSize == size ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func toggleHoverPreview() {
        settings.hoverPreviewEnabled.toggle()
    }

    @objc private func toggleSingleWindowHide() {
        settings.singleWindowHideEnabled.toggle()
    }

    @objc private func selectHoverDelay(_ sender: NSMenuItem) {
        settings.hoverDelayMs = sender.tag
    }

    @objc private func selectThumbnailSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Settings.ThumbnailSize else { return }
        settings.thumbnailSize = size
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openPermissions() {
        onOpenPermissions?()
    }

    @objc private func runDiagnostics() {
        onRunDiagnostics?()
    }

    @objc private func restoreApp(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? pid_t else { return }
        onRestoreApp?(pid)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
