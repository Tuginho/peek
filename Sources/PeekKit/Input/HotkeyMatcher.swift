import CoreGraphics
import Foundation

/// Read-only snapshot of the state the event tap needs to decide what to do with a key or
/// mouse event. Written from the main actor via `EventTapThread.updateSnapshot`, read on the
/// event tap thread under `OSAllocatedUnfairLock`.
public struct TapSnapshot {
    public var hotkeyEnabled = true
    public var excludedBundleIDs: Set<String> = []
    public var frontmostBundleID: String?
    public var frontmostPID: pid_t = 0
    public var ownPID: pid_t = 0
    /// CG global coordinates (top-left origin), already padded. `.null` while unknown.
    public var dockRect: CGRect = .null
}

public enum HotkeyDecision: Equatable {
    case passThrough
    case swallowOnly
    case hide(pid: pid_t)
}

/// Pure decision logic for the Cmd+H hotkey, kept free of AX/NSWorkspace calls so it can run
/// on the event tap thread and be unit tested without permissions.
public enum HotkeyMatcher {
    public static func decide(
        keyCode: Int64,
        characters: String?,
        flags: CGEventFlags,
        isAutorepeat: Bool,
        snapshot: TapSnapshot
    ) -> HotkeyDecision {
        let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        guard flags.intersection(relevantMask) == .maskCommand else { return .passThrough }

        let keyMatches: Bool
        if characters?.lowercased() == "h" {
            keyMatches = true
        } else if keyCode == 4 {
            // `characters?.unicodeScalars.first` is nil for both nil and empty strings.
            if let first = characters?.unicodeScalars.first {
                keyMatches = !isASCIILetter(first)
            } else {
                keyMatches = true
            }
        } else {
            keyMatches = false
        }
        guard keyMatches else { return .passThrough }

        guard snapshot.hotkeyEnabled else { return .passThrough }
        guard snapshot.frontmostPID != snapshot.ownPID, snapshot.frontmostPID != 0 else { return .passThrough }
        if let bundleID = snapshot.frontmostBundleID, snapshot.excludedBundleIDs.contains(bundleID) {
            return .passThrough
        }

        if isAutorepeat { return .swallowOnly }
        return .hide(pid: snapshot.frontmostPID)
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }
}
