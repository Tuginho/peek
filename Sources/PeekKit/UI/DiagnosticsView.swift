import AppKit
import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: Diagnostics

    @State private var report = ""
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(report)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("bottom")
                }
                .onChange(of: report) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            if isRunning {
                ProgressView()
                    .padding(8)
            }

            HStack {
                Button("Kopieren") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(report, forType: .string)
                }
                Button("Erneut ausführen") {
                    run()
                }
                .disabled(isRunning)
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 640, height: 480)
        .onAppear {
            run()
        }
    }

    private func run() {
        isRunning = true
        report = ""
        Task {
            let result = await diagnostics.run { progress in
                report = progress
            }
            report = result
            isRunning = false
        }
    }
}
