import CoreGraphics
import Testing
@testable import PeekKit

@MainActor
struct ThumbnailCacheTests {
    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func key(_ id: CGWindowID) -> WindowKey {
        .windowID(id)
    }

    @Test func storesAndRetrieves() {
        let cache = ThumbnailCache()
        let image = makeImage()
        cache.store(image, for: key(1), pid: 100)
        #expect(cache.contains(key(1)))
        #expect(cache.image(for: key(1)) != nil)
    }

    @Test func evictsLeastRecentlyUsed() {
        let cache = ThumbnailCache(capacity: 2)
        let image = makeImage()
        cache.store(image, for: key(1), pid: 100)
        cache.store(image, for: key(2), pid: 100)
        cache.store(image, for: key(3), pid: 100)
        #expect(cache.contains(key(1)) == false)
        #expect(cache.contains(key(2)))
        #expect(cache.contains(key(3)))
        #expect(cache.count == 2)
    }

    @Test func readRefreshesRecency() {
        let cache = ThumbnailCache(capacity: 2)
        let image = makeImage()
        cache.store(image, for: key(1), pid: 100)
        cache.store(image, for: key(2), pid: 100)
        _ = cache.image(for: key(1)) // refresh key 1 so key 2 becomes the least recently used
        cache.store(image, for: key(3), pid: 100)
        #expect(cache.contains(key(2)) == false)
        #expect(cache.contains(key(1)))
        #expect(cache.contains(key(3)))
    }

    @Test func removeAllForPID() {
        let cache = ThumbnailCache()
        let image = makeImage()
        cache.store(image, for: key(1), pid: 100)
        cache.store(image, for: key(2), pid: 200)
        cache.removeAll(pid: 100)
        #expect(cache.contains(key(1)) == false)
        #expect(cache.contains(key(2)))
        #expect(cache.count == 1)
    }

    @Test func remove() {
        let cache = ThumbnailCache()
        let image = makeImage()
        cache.store(image, for: key(1), pid: 100)
        cache.remove(key(1))
        #expect(cache.contains(key(1)) == false)
        #expect(cache.count == 0)
    }
}
