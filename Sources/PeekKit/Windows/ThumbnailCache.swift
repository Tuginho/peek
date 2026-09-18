import CoreGraphics
import Foundation

/// In-memory LRU cache of window thumbnails, keyed by `WindowKey`.
@MainActor
public final class ThumbnailCache {
    private struct Entry {
        let image: CGImage
        let pid: pid_t
    }

    public let capacity: Int

    private var entries: [WindowKey: Entry] = [:]
    /// Least-recently-used first.
    private var recencyOrder: [WindowKey] = []

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    public var count: Int { entries.count }

    public func store(_ image: CGImage, for key: WindowKey, pid: pid_t) {
        entries[key] = Entry(image: image, pid: pid)
        touch(key)
        evictIfNeeded()
    }

    public func image(for key: WindowKey) -> CGImage? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry.image
    }

    public func contains(_ key: WindowKey) -> Bool {
        entries[key] != nil
    }

    public func remove(_ key: WindowKey) {
        entries[key] = nil
        recencyOrder.removeAll { $0 == key }
    }

    public func removeAll(pid: pid_t) {
        let keys = entries.filter { $0.value.pid == pid }.map(\.key)
        guard !keys.isEmpty else { return }
        for key in keys {
            entries[key] = nil
        }
        let keySet = Set(keys)
        recencyOrder.removeAll { keySet.contains($0) }
    }

    private func touch(_ key: WindowKey) {
        recencyOrder.removeAll { $0 == key }
        recencyOrder.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > capacity, !recencyOrder.isEmpty {
            let oldest = recencyOrder.removeFirst()
            entries[oldest] = nil
        }
    }
}
