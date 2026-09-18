import AppKit
import CoreGraphics
import Foundation

public struct HiddenWindow: Identifiable {
    public var id: WindowKey { key }

    public let key: WindowKey
    public let pid: pid_t
    public let bundleID: String?
    public let element: AXElement
    public let windowID: CGWindowID?
    public let title: String
    public let hiddenAt: Date
    public let method: Settings.HideMethod
    /// Frame (AX coordinates) recorded right before hiding, used to restore `.park` windows and
    /// filled for `.minimize` too.
    public let originalFrame: CGRect

    public init(
        key: WindowKey,
        pid: pid_t,
        bundleID: String?,
        element: AXElement,
        windowID: CGWindowID?,
        title: String,
        hiddenAt: Date,
        method: Settings.HideMethod,
        originalFrame: CGRect
    ) {
        self.key = key
        self.pid = pid
        self.bundleID = bundleID
        self.element = element
        self.windowID = windowID
        self.title = title
        self.hiddenAt = hiddenAt
        self.method = method
        self.originalFrame = originalFrame
    }
}

/// Tracks windows Peek has minimized on the user's behalf, grouped by owning app, so they can
/// be restored later (Dock click, app activation, status menu). Persists the windowID-bearing
/// subset across launches.
@MainActor
public final class HiddenWindowStore: ObservableObject {
    struct PersistedRecord: Codable, Equatable {
        let pid: pid_t
        let windowID: CGWindowID
        let bundleID: String?
        let hiddenAt: Date
        let method: Settings.HideMethod
        let originalFrame: CGRect

        private enum CodingKeys: String, CodingKey {
            case pid, windowID, bundleID, hiddenAt, method, x, y, width, height
        }

        init(pid: pid_t, windowID: CGWindowID, bundleID: String?, hiddenAt: Date, method: Settings.HideMethod, originalFrame: CGRect) {
            self.pid = pid
            self.windowID = windowID
            self.bundleID = bundleID
            self.hiddenAt = hiddenAt
            self.method = method
            self.originalFrame = originalFrame
        }

        // Custom Codable so records written by the previous version (no method/frame) still
        // decode, defaulting to `.minimize` / `.zero`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pid = try container.decode(pid_t.self, forKey: .pid)
            windowID = try container.decode(CGWindowID.self, forKey: .windowID)
            bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
            hiddenAt = try container.decode(Date.self, forKey: .hiddenAt)
            method = try container.decodeIfPresent(Settings.HideMethod.self, forKey: .method) ?? .minimize
            let x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
            let y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
            let width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? 0
            let height = try container.decodeIfPresent(CGFloat.self, forKey: .height) ?? 0
            originalFrame = CGRect(x: x, y: y, width: width, height: height)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pid, forKey: .pid)
            try container.encode(windowID, forKey: .windowID)
            try container.encodeIfPresent(bundleID, forKey: .bundleID)
            try container.encode(hiddenAt, forKey: .hiddenAt)
            try container.encode(method, forKey: .method)
            try container.encode(originalFrame.origin.x, forKey: .x)
            try container.encode(originalFrame.origin.y, forKey: .y)
            try container.encode(originalFrame.size.width, forKey: .width)
            try container.encode(originalFrame.size.height, forKey: .height)
        }
    }

    private static let defaultsKey = "peek.hiddenWindows"

    /// Append order = hide order, oldest first.
    @Published public private(set) var windowsByPID: [pid_t: [HiddenWindow]] = [:]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func add(_ window: HiddenWindow) {
        var list = windowsByPID[window.pid] ?? []
        list.removeAll { $0.key == window.key }
        list.append(window)
        windowsByPID[window.pid] = list
        persist()
    }

    @discardableResult
    public func remove(key: WindowKey) -> HiddenWindow? {
        for (pid, list) in windowsByPID {
            guard let index = list.firstIndex(where: { $0.key == key }) else { continue }
            var updated = list
            let removed = updated.remove(at: index)
            windowsByPID[pid] = updated.isEmpty ? nil : updated
            persist()
            return removed
        }
        return nil
    }

    @discardableResult
    public func remove(element: AXElement) -> HiddenWindow? {
        for (pid, list) in windowsByPID {
            guard let index = list.firstIndex(where: { $0.element == element }) else { continue }
            var updated = list
            let removed = updated.remove(at: index)
            windowsByPID[pid] = updated.isEmpty ? nil : updated
            persist()
            return removed
        }
        return nil
    }

    @discardableResult
    public func removeAll(pid: pid_t) -> [HiddenWindow] {
        guard let removed = windowsByPID.removeValue(forKey: pid) else { return [] }
        persist()
        return removed
    }

    public func windows(for pid: pid_t) -> [HiddenWindow] {
        windowsByPID[pid] ?? []
    }

    public func contains(key: WindowKey) -> Bool {
        windowsByPID.values.contains { $0.contains { $0.key == key } }
    }

    public func isHidden(_ window: WindowInfo) -> Bool {
        contains(key: window.key)
    }

    public func entry(for key: WindowKey) -> HiddenWindow? {
        for list in windowsByPID.values {
            if let found = list.first(where: { $0.key == key }) { return found }
        }
        return nil
    }

    public func count(for pid: pid_t) -> Int {
        windowsByPID[pid]?.count ?? 0
    }

    public var totalCount: Int {
        windowsByPID.values.reduce(0) { $0 + $1.count }
    }

    /// Restores entries saved on a previous launch, dropping anything that no longer matches a
    /// running app (same pid AND bundle ID) with a still-minimized window of that windowID.
    public func restorePersisted(using windowManager: WindowManager) {
        let records = Self.decodeRecords(defaults.data(forKey: Self.defaultsKey))
        let screenFramesAX = ScreenLayout.currentAXFrames()

        for record in records {
            guard let app = NSRunningApplication(processIdentifier: record.pid),
                  app.bundleIdentifier == record.bundleID
            else { continue }

            let liveWindows = windowManager.windows(of: record.pid)
            guard let match = liveWindows.first(where: { $0.windowID == record.windowID }) else { continue }

            switch record.method {
            case .minimize:
                guard match.isMinimized else { continue }
            case .park:
                guard Geometry.isParked(match.frame, screenFramesAX: screenFramesAX) else { continue }
            }

            let hiddenWindow = HiddenWindow(
                key: match.key,
                pid: record.pid,
                bundleID: record.bundleID,
                element: match.element,
                windowID: match.windowID,
                title: match.title,
                hiddenAt: record.hiddenAt,
                method: record.method,
                originalFrame: record.originalFrame
            )
            windowsByPID[record.pid, default: []].append(hiddenWindow)
        }

        persist()
    }

    static func decodeRecords(_ data: Data?) -> [PersistedRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PersistedRecord].self, from: data)) ?? []
    }

    static func encodeRecords(_ records: [PersistedRecord]) -> Data {
        (try? JSONEncoder().encode(records)) ?? Data()
    }

    private func persist() {
        let records = windowsByPID.values.flatMap { $0 }.compactMap { window -> PersistedRecord? in
            guard let windowID = window.windowID else { return nil }
            return PersistedRecord(
                pid: window.pid,
                windowID: windowID,
                bundleID: window.bundleID,
                hiddenAt: window.hiddenAt,
                method: window.method,
                originalFrame: window.originalFrame
            )
        }
        defaults.set(Self.encodeRecords(records), forKey: Self.defaultsKey)
    }
}
