import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

public enum PermissionKind: CaseIterable {
    case accessibility
    case screenRecording
    case inputMonitoring
}

public enum Permissions {
    public static func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .inputMonitoring:
            return CGPreflightListenEventAccess()
        }
    }

    public static func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .inputMonitoring:
            CGRequestListenEventAccess()
        }
    }

    public static func openSystemSettings(_ kind: PermissionKind) {
        NSWorkspace.shared.open(settingsURL(kind))
    }

    public static func settingsURL(_ kind: PermissionKind) -> URL {
        switch kind {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}
