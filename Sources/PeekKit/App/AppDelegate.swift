import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }
}
