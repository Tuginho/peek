import CoreGraphics
import Foundation
import Testing
@testable import PeekKit

@MainActor
struct HiddenWindowStoreTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "PeekKitTests.HiddenWindowStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeWindow(
        pid: pid_t,
        windowID: CGWindowID?,
        title: String,
        hiddenAt: Date = Date(),
        method: Settings.HideMethod = .minimize,
        originalFrame: CGRect = .zero
    ) -> HiddenWindow {
        HiddenWindow(
            key: WindowKey(windowID: windowID, pid: pid, title: title, frame: .zero),
            pid: pid,
            bundleID: "com.example.app",
            element: AXElement.application(pid: pid),
            windowID: windowID,
            title: title,
            hiddenAt: hiddenAt,
            method: method,
            originalFrame: originalFrame
        )
    }

    @Test func addAndRemoveByKey() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let window = makeWindow(pid: 1, windowID: 10, title: "A")
            store.add(window)
            #expect(store.contains(key: window.key))
            #expect(store.count(for: 1) == 1)

            let removed = store.remove(key: window.key)
            #expect(removed?.key == window.key)
            #expect(store.count(for: 1) == 0)
            #expect(store.contains(key: window.key) == false)
        }
    }

    @Test func removeByElement() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let window = makeWindow(pid: 1, windowID: 10, title: "A")
            store.add(window)
            let removed = store.remove(element: window.element)
            #expect(removed?.key == window.key)
            #expect(store.count(for: 1) == 0)
        }
    }

    @Test func removeAllForPID() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let a = makeWindow(pid: 1, windowID: 10, title: "A")
            let b = makeWindow(pid: 1, windowID: 11, title: "B")
            let c = makeWindow(pid: 2, windowID: 12, title: "C")
            store.add(a)
            store.add(b)
            store.add(c)

            let removed = store.removeAll(pid: 1)
            #expect(removed.map(\.key) == [a.key, b.key])
            #expect(store.count(for: 1) == 0)
            #expect(store.count(for: 2) == 1)
        }
    }

    @Test func orderIsHideOrderOldestFirst() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let a = makeWindow(pid: 1, windowID: 10, title: "A")
            let b = makeWindow(pid: 1, windowID: 11, title: "B")
            store.add(a)
            store.add(b)
            #expect(store.windows(for: 1).map(\.key) == [a.key, b.key])
        }
    }

    @Test func readdingSameKeyMovesToEnd() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let a = makeWindow(pid: 1, windowID: 10, title: "A")
            let b = makeWindow(pid: 1, windowID: 11, title: "B")
            store.add(a)
            store.add(b)
            let aAgain = makeWindow(pid: 1, windowID: 10, title: "A")
            store.add(aAgain)
            #expect(store.windows(for: 1).map(\.key) == [b.key, aAgain.key])
            #expect(store.count(for: 1) == 2)
        }
    }

    @Test func totalCount() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            store.add(makeWindow(pid: 1, windowID: 10, title: "A"))
            store.add(makeWindow(pid: 2, windowID: 11, title: "B"))
            #expect(store.totalCount == 2)
        }
    }

    @Test func persistedRecordRoundTripOnlyIncludesWindowID() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            store.add(makeWindow(pid: 1, windowID: 10, title: "A"))
            store.add(makeWindow(pid: 1, windowID: nil, title: "B"))

            let data = defaults.data(forKey: "peek.hiddenWindows")
            let records = HiddenWindowStore.decodeRecords(data)
            #expect(records.count == 1)
            #expect(records.first?.windowID == 10)
            #expect(records.first?.pid == 1)
            #expect(records.first?.bundleID == "com.example.app")

            let encoded = HiddenWindowStore.encodeRecords(records)
            let decodedAgain = HiddenWindowStore.decodeRecords(encoded)
            #expect(decodedAgain == records)
        }
    }

    @Test func persistedRecordRoundTripIncludesMethodAndFrame() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
            store.add(makeWindow(pid: 1, windowID: 10, title: "A", method: .park, originalFrame: frame))

            let data = defaults.data(forKey: "peek.hiddenWindows")
            let records = HiddenWindowStore.decodeRecords(data)
            #expect(records.count == 1)
            #expect(records.first?.method == .park)
            #expect(records.first?.originalFrame == frame)

            let encoded = HiddenWindowStore.encodeRecords(records)
            let decodedAgain = HiddenWindowStore.decodeRecords(encoded)
            #expect(decodedAgain == records)
        }
    }

    @Test func legacyRecordWithoutMethodAndFrameDecodesToMinimizeAndZero() {
        struct LegacyRecord: Codable {
            let pid: pid_t
            let windowID: CGWindowID
            let bundleID: String?
            let hiddenAt: Date
        }
        let legacy = [LegacyRecord(pid: 1, windowID: 10, bundleID: "com.example.app", hiddenAt: Date())]
        let data = try! JSONEncoder().encode(legacy)

        let records = HiddenWindowStore.decodeRecords(data)
        #expect(records.count == 1)
        #expect(records.first?.method == .minimize)
        #expect(records.first?.originalFrame == .zero)
        #expect(records.first?.pid == 1)
        #expect(records.first?.windowID == 10)
    }

    @Test func isHiddenMatchesContains() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let window = makeWindow(pid: 1, windowID: 10, title: "A")
            let info = WindowInfo(
                key: window.key,
                pid: 1,
                element: window.element,
                windowID: 10,
                title: "A",
                frame: .zero,
                isMinimized: false,
                isFullScreen: false,
                canMinimize: true,
                canMove: true
            )
            #expect(store.isHidden(info) == false)
            store.add(window)
            #expect(store.isHidden(info) == true)
        }
    }

    @Test func entryForKeyFindsAddedWindow() {
        withDefaults { defaults in
            let store = HiddenWindowStore(defaults: defaults)
            let window = makeWindow(pid: 1, windowID: 10, title: "A")
            #expect(store.entry(for: window.key) == nil)
            store.add(window)
            #expect(store.entry(for: window.key)?.key == window.key)
        }
    }
}
