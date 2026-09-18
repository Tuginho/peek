import Foundation

/// Wires the event tap's hide callback to `WindowHider`. Deliberately thin.
@MainActor
final class HotkeyInterceptor {
    init(tapThread: EventTapThread, hider: WindowHider) {
        tapThread.onHide = { pid in
            hider.hideFocusedWindow(of: pid)
        }
    }
}
