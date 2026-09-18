import AppKit
import CoreGraphics

/// Reads the current display layout as AX frames, for the parking geometry which otherwise
/// takes no AppKit state directly.
@MainActor
public enum ScreenLayout {
    public static func currentAXFrames() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryScreenHeight: primaryHeight) }
    }
}
