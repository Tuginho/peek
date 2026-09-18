import CoreGraphics
import Testing
@testable import PeekKit

struct HotkeyMatcherTests {
    private func snapshot(
        hotkeyEnabled: Bool = true,
        excludedBundleIDs: Set<String> = [],
        frontmostBundleID: String? = "com.example.frontmost",
        frontmostPID: pid_t = 100,
        ownPID: pid_t = 1
    ) -> TapSnapshot {
        var snap = TapSnapshot()
        snap.hotkeyEnabled = hotkeyEnabled
        snap.excludedBundleIDs = excludedBundleIDs
        snap.frontmostBundleID = frontmostBundleID
        snap.frontmostPID = frontmostPID
        snap.ownPID = ownPID
        return snap
    }

    @Test func cmdHHides() {
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .hide(pid: 100))
    }

    @Test func cmdOptHPassesThrough() {
        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: flags, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .passThrough)
    }

    @Test func cmdShiftHPassesThrough() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: flags, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .passThrough)
    }

    @Test func cmdCtrlHPassesThrough() {
        let flags: CGEventFlags = [.maskCommand, .maskControl]
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: flags, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .passThrough)
    }

    @Test func plainHPassesThrough() {
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: [], isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .passThrough)
    }

    @Test func capsLockAndFnBitsAreIgnored() {
        let flags: CGEventFlags = [.maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad]
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: flags, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .hide(pid: 100))
    }

    @Test func disabledSettingPassesThrough() {
        let decision = HotkeyMatcher.decide(
            keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: false,
            snapshot: snapshot(hotkeyEnabled: false)
        )
        #expect(decision == .passThrough)
    }

    @Test func excludedBundlePassesThrough() {
        let decision = HotkeyMatcher.decide(
            keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: false,
            snapshot: snapshot(excludedBundleIDs: ["com.example.frontmost"])
        )
        #expect(decision == .passThrough)
    }

    @Test func ownPIDPassesThrough() {
        let decision = HotkeyMatcher.decide(
            keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: false,
            snapshot: snapshot(frontmostPID: 1, ownPID: 1)
        )
        #expect(decision == .passThrough)
    }

    @Test func pidZeroPassesThrough() {
        let decision = HotkeyMatcher.decide(
            keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: false,
            snapshot: snapshot(frontmostPID: 0)
        )
        #expect(decision == .passThrough)
    }

    @Test func autorepeatSwallowsOnly() {
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "h", flags: .maskCommand, isAutorepeat: true, snapshot: snapshot())
        #expect(decision == .swallowOnly)
    }

    @Test func dvorakKeyCode4PassesThrough() {
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "d", flags: .maskCommand, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .passThrough)
    }

    @Test func cyrillicKeyCode4Hides() {
        let decision = HotkeyMatcher.decide(keyCode: 4, characters: "р", flags: .maskCommand, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .hide(pid: 100))
    }

    @Test func keyCode11WithHHides() {
        let decision = HotkeyMatcher.decide(keyCode: 11, characters: "h", flags: .maskCommand, isAutorepeat: false, snapshot: snapshot())
        #expect(decision == .hide(pid: 100))
    }
}
