import CoreGraphics
import Foundation
import ScreenCaptureKit

public protocol WindowCapturing {
    /// Returns images for the windows that could be captured; never throws, never prompts.
    func capture(_ windows: [WindowInfo], boxSize: CGSize, scale: CGFloat) async -> [WindowKey: CGImage]
}

public final class SCKWindowCapturer: WindowCapturing {
    public init() {}

    public func capture(_ windows: [WindowInfo], boxSize: CGSize, scale: CGFloat) async -> [WindowKey: CGImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }

        let candidates = windows.filter { !$0.isMinimized }
        guard !candidates.isEmpty else { return [:] }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return [:]
        }

        let pairs = candidates.compactMap { window -> (WindowInfo, SCWindow)? in
            guard let match = Self.match(window, in: content.windows) else { return nil }
            return (window, match)
        }
        guard !pairs.isEmpty else { return [:] }

        return await withTaskGroup(of: (WindowKey, CGImage?).self) { group in
            for (window, scWindow) in pairs {
                group.addTask {
                    let image = await Self.captureImage(for: window, scWindow: scWindow, boxSize: boxSize, scale: scale)
                    return (window.key, image)
                }
            }
            var results: [WindowKey: CGImage] = [:]
            for await (key, image) in group {
                if let image { results[key] = image }
            }
            return results
        }
    }

    private static func match(_ window: WindowInfo, in scWindows: [SCWindow]) -> SCWindow? {
        if let windowID = window.windowID {
            return scWindows.first { $0.windowID == windowID }
        }
        return scWindows.first { scWindow in
            scWindow.owningApplication?.processID == window.pid
                && scWindow.title == window.title
                && scWindow.frame.isApproximatelyEqual(to: window.frame, tolerance: 2)
        }
    }

    private static func captureImage(for window: WindowInfo, scWindow: SCWindow, boxSize: CGSize, scale: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()

        let fitted = aspectFit(window.frame.size, into: boxSize)
        config.width = max(1, Int((fitted.width * scale).rounded()))
        config.height = max(1, Int((fitted.height * scale).rounded()))
        config.showsCursor = false
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Aspect-fits `size` into `box`, never upscaling.
    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

/// Resumes exactly once with the operation's result, or with nil once `seconds` elapse,
/// whichever comes first. Deliberately not built on `withTaskGroup`, which would block on the
/// slow child until it finishes. If the operation finishes late with a non-nil value,
/// `onLateResult` is called instead of resuming.
@MainActor
public func withTimeout<T>(
    _ seconds: TimeInterval,
    _ operation: @escaping @MainActor () async -> T?,
    onLateResult: (@MainActor (T) -> Void)? = nil
) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let resumeGate = ResumeGate()

        Task { @MainActor in
            let result = await operation()
            if resumeGate.resumeOnce() {
                continuation.resume(returning: result)
            } else if let result {
                onLateResult?(result)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            if resumeGate.resumeOnce() {
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Thread-safe one-shot gate so the two racing tasks in `withTimeout` agree on who resumes.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
