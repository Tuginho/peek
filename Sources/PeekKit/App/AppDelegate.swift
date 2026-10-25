import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var signalSources: [DispatchSourceSignal] = []
    private let signalQueue = DispatchQueue(label: "peek.signals")
    private var receivedTerminationSignal = false

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandlers()
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    /// `killall Peek`, Ctrl-C and the like would otherwise exit without
    /// `applicationWillTerminate`, leaving every parked window stranded off-screen. The handler
    /// runs off the main thread so a second signal still exits while termination is stuck
    /// restoring windows of a hung app.
    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if receivedTerminationSignal { exit(1) }
                receivedTerminationSignal = true
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }
}
