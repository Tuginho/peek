import AppKit
import SwiftUI

struct PermissionsView: View {
    @State private var granted: [PermissionKind: Bool] = [:]
    @State private var timer: Timer?

    private struct Row {
        let kind: PermissionKind
        let name: String
        let purpose: String
    }

    private let rows: [Row] = [
        Row(kind: .accessibility, name: "Bedienungshilfen", purpose: "Dock-Hover erkennen, Fenster steuern, Cmd+H abfangen."),
        Row(kind: .screenRecording, name: "Bildschirmaufnahme", purpose: "Fenster-Thumbnails aufnehmen. Ohne Freigabe zeigt Peek Platzhalter."),
        Row(kind: .inputMonitoring, name: "Eingabeüberwachung (optional)", purpose: "Nur nötig, falls Cmd+H trotz Bedienungshilfen nicht reagiert."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(rows, id: \.kind) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isGranted(row.kind) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(isGranted(row.kind) ? .green : .orange)
                        .font(.system(size: 18))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name).font(.headline)
                        Text(row.purpose).font(.subheadline).foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Systemeinstellungen öffnen") {
                        Permissions.request(row.kind)
                        Permissions.openSystemSettings(row.kind)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Nach Erteilen der Bildschirmaufnahme Peek neu starten.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("Peek neu starten") {
                    relaunch()
                }
            }
        }
        .padding(20)
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func isGranted(_ kind: PermissionKind) -> Bool {
        granted[kind] ?? false
    }

    private func refresh() {
        for kind in PermissionKind.allCases {
            granted[kind] = Permissions.isGranted(kind)
        }
    }

    private func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            NSApp.terminate(nil)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
