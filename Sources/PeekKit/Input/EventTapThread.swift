import CoreGraphics
import Foundation
import os

/// Owns the two low-level event taps (key-down, mouse listen-only) on a dedicated run loop
/// thread. The tap callback must stay O(1): it only reads the lock-protected snapshot,
/// inspects the event and dispatches to main — no AX calls, no NSWorkspace, no main-actor state.
public final class EventTapThread {
    public let snapshot = OSAllocatedUnfairLock<TapSnapshot>(initialState: TapSnapshot())

    public func updateSnapshot(_ body: (inout TapSnapshot) -> Void) {
        snapshot.withLock { state in body(&state) }
    }

    var onHide: ((pid_t) -> Void)?
    var onMouseDown: ((CGPoint, CGEventFlags) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    private var keyTap: CFMachPort?
    private var mouseTap: CFMachPort?
    private var keyRunLoopSource: CFRunLoopSource?
    private var mouseRunLoopSource: CFRunLoopSource?
    private var dedicatedThread: Thread?
    private var dedicatedRunLoop: CFRunLoop?

    public init() {}

    // The taps hold an unretained pointer to self as userInfo; they must not outlive it.
    deinit { stop() }

    public var isKeyTapActive: Bool {
        guard let keyTap else { return false }
        return CGEvent.tapIsEnabled(tap: keyTap)
    }

    /// Idempotent: a second call while already started is a no-op returning `true`. If the key
    /// tap failed to create, `keyTap` stays nil so a later call can retry.
    @discardableResult
    public func start() -> Bool {
        guard keyTap == nil else { return true }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let keyTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }
        self.keyTap = keyTap
        keyRunLoopSource = CFMachPortCreateRunLoopSource(nil, keyTap, 0)

        let mouseMask = CGEventMask((1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue))
        if let mouseTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mouseMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) {
            self.mouseTap = mouseTap
            mouseRunLoopSource = CFMachPortCreateRunLoopSource(nil, mouseTap, 0)
        } else {
            NSLog("Peek: failed to create mouse listen-only event tap")
        }

        let thread = Thread { [self] in runOnDedicatedThread() }
        thread.name = "peek.eventtap"
        thread.qualityOfService = .userInteractive
        dedicatedThread = thread
        thread.start()

        return true
    }

    public func stop() {
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: false)
            CFMachPortInvalidate(keyTap)
        }
        if let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: false)
            CFMachPortInvalidate(mouseTap)
        }
        if let dedicatedRunLoop {
            CFRunLoopStop(dedicatedRunLoop)
        }
        keyTap = nil
        mouseTap = nil
        keyRunLoopSource = nil
        mouseRunLoopSource = nil
        dedicatedThread = nil
        dedicatedRunLoop = nil
    }

    private func runOnDedicatedThread() {
        let runLoop = CFRunLoopGetCurrent()
        dedicatedRunLoop = runLoop

        if let keyRunLoopSource {
            CFRunLoopAddSource(runLoop, keyRunLoopSource, .commonModes)
        }
        if let mouseRunLoopSource {
            CFRunLoopAddSource(runLoop, mouseRunLoopSource, .commonModes)
        }
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: true)
        }
        if let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: true)
        }

        CFRunLoopRun()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .leftMouseDown, .leftMouseUp:
            handleMouse(type: type, event: event)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags

        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let characters = length > 0 ? String(utf16CodeUnits: chars, count: length) : nil

        let snap = snapshot.withLock { $0 }
        let decision = HotkeyMatcher.decide(
            keyCode: keyCode,
            characters: characters,
            flags: flags,
            isAutorepeat: isAutorepeat,
            snapshot: snap
        )

        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .swallowOnly:
            return nil
        case .hide(let pid):
            DispatchQueue.main.async { [weak self] in self?.onHide?(pid) }
            return nil
        }
    }

    private func handleMouse(type: CGEventType, event: CGEvent) {
        let point = event.location
        let snap = snapshot.withLock { $0 }
        guard snap.dockRect.contains(point) else { return }

        if type == .leftMouseDown {
            let flags = event.flags
            DispatchQueue.main.async { [weak self] in self?.onMouseDown?(point, flags) }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onMouseUp?(point) }
        }
    }
}

/// Global, non-capturing so it converts implicitly to a C function pointer; `userInfo` carries
/// the `EventTapThread` instance.
private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<EventTapThread>.fromOpaque(userInfo).takeUnretainedValue()
    return box.handle(type: type, event: event)
}
