import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings

    @State private var selectedBundleID: String?
    @State private var dockMinimizeToApplicationEnabled = SettingsView.readDockMinimizeToApplication()

    var body: some View {
        Form {
            Section("Dock-Vorschau") {
                Toggle("Hover-Vorschau aktivieren", isOn: $settings.hoverPreviewEnabled)

                Picker("Hover-Verzögerung", selection: $settings.hoverDelayMs) {
                    ForEach(Settings.hoverDelayPresets, id: \.self) { preset in
                        Text("\(preset) ms").tag(preset)
                    }
                }

                Picker("Thumbnail-Größe", selection: $settings.thumbnailSize) {
                    ForEach(Settings.ThumbnailSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
            }

            Section("Cmd+H") {
                Picker("Verstecken per", selection: $settings.hideMethod) {
                    ForEach(Settings.HideMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method)
                    }
                }
                if settings.hideMethod == .park {
                    Text("Geparkte Fenster bleiben für macOS offen: Mission Control zeigt sie, Cmd+` kann sie auswählen. Beim Beenden holt Peek sie zurück.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Toggle("Cmd+H versteckt nur das aktuelle Fenster", isOn: $settings.singleWindowHideEnabled)
                Toggle("Beim App-Wechsel zuletzt verstecktes Fenster wiederherstellen", isOn: $settings.restoreOnActivate)
                Toggle("Anzahl versteckter Fenster am Dock-Symbol anzeigen", isOn: $settings.showDockBadges)

                Picker("Beim Dock-Klick wiederherstellen", selection: $settings.dockClickRestoreMode) {
                    ForEach(Settings.DockClickRestoreMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if !dockMinimizeToApplicationEnabled {
                    Text("Tipp: In Systemeinstellungen → Schreibtisch & Dock „Fenster hinter Programmsymbol im Dock ablegen“ aktivieren. Sonst sammeln sich versteckte Fenster rechts im Dock.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Ausnahmen (Cmd+H bleibt unverändert)") {
                List(settings.excludedBundleIDs, id: \.self, selection: $selectedBundleID) { bundleID in
                    exclusionRow(for: bundleID)
                }
                .frame(minHeight: 120)

                HStack {
                    Button("App hinzufügen…") { addExclusion() }
                    Button("Entfernen") { removeSelectedExclusion() }
                        .disabled(selectedBundleID == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func exclusionRow(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(name)
            }
        } else {
            Text(bundleID)
        }
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
    }

    private func removeSelectedExclusion() {
        guard let selectedBundleID else { return }
        settings.excludedBundleIDs.removeAll { $0 == selectedBundleID }
        self.selectedBundleID = nil
    }

    private static func readDockMinimizeToApplication() -> Bool {
        guard let value = CFPreferencesCopyAppValue("minimize-to-application" as CFString, "com.apple.dock" as CFString) else {
            return false
        }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
    }
}
