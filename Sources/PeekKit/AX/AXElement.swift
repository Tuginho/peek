import ApplicationServices
import CoreGraphics
import Foundation

/// Thin, value-typed wrapper around `AXUIElement` with typed accessors for the
/// attributes Peek needs.
public struct AXElement: Hashable {
    public let raw: AXUIElement

    public init(raw: AXUIElement) {
        self.raw = raw
    }

    public static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        CFEqual(lhs.raw, rhs.raw)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(raw))
    }

    public static func application(pid: pid_t) -> AXElement {
        let raw = AXUIElementCreateApplication(pid)
        // Prevents Peek from hanging when an app's AX server is slow or wedged.
        AXUIElementSetMessagingTimeout(raw, 0.5)
        return AXElement(raw: raw)
    }

    public static var systemWide: AXElement {
        AXElement(raw: AXUIElementCreateSystemWide())
    }

    /// Setting the timeout on the system-wide element applies it to every AX call of this
    /// process, including window elements that were not created via `application(pid:)`.
    public static func setGlobalMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    public func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, name as CFString, &value)
        guard error == .success else { return nil }
        return value as? T
    }

    @discardableResult
    public func setAttribute(_ name: String, _ value: CFTypeRef) -> Bool {
        setAttributeResult(name, value) == .success
    }

    public func setAttributeResult(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(raw, name as CFString, value)
    }

    @discardableResult
    public func performAction(_ name: String) -> Bool {
        AXUIElementPerformAction(raw, name as CFString) == .success
    }

    public func isAttributeSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(raw, name as CFString, &settable)
        return error == .success && settable.boolValue
    }

    public var role: String? {
        attribute(kAXRoleAttribute)
    }

    public var subrole: String? {
        attribute(kAXSubroleAttribute)
    }

    public var title: String? {
        attribute(kAXTitleAttribute)
    }

    /// AX coordinates: global screen space, origin top-left (unlike AppKit's bottom-left origin).
    public var position: CGPoint? {
        guard let value: AXValue = attribute(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    public var size: CGSize? {
        guard let value: AXValue = attribute(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    public var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    public func setPosition(_ point: CGPoint) -> Bool {
        setPositionResult(point) == .success
    }

    public func setPositionResult(_ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return setAttributeResult(kAXPositionAttribute, value)
    }

    public var children: [AXElement] {
        let raws: [AXUIElement] = attribute(kAXChildrenAttribute) ?? []
        return raws.map { AXElement(raw: $0) }
    }

    public var windows: [AXElement] {
        let raws: [AXUIElement] = attribute(kAXWindowsAttribute) ?? []
        return raws.map { AXElement(raw: $0) }
    }

    public var selectedChildren: [AXElement] {
        let raws: [AXUIElement] = attribute(kAXSelectedChildrenAttribute) ?? []
        return raws.map { AXElement(raw: $0) }
    }

    public var isMinimized: Bool {
        boolAttribute(kAXMinimizedAttribute) ?? false
    }

    public var isFullScreen: Bool {
        boolAttribute("AXFullScreen") ?? false
    }

    public var url: URL? {
        attribute(kAXURLAttribute)
    }

    public var pid: pid_t? {
        var pid: pid_t = 0
        let error = AXUIElementGetPid(raw, &pid)
        return error == .success ? pid : nil
    }

    public var windowID: CGWindowID? {
        PrivateAPI.windowID(of: raw)
    }

    /// `point` must be in AX coordinates (global, top-left origin).
    public func element(at point: CGPoint) -> AXElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            raw,
            Float(point.x),
            Float(point.y),
            &element
        )
        guard error == .success, let element else { return nil }
        return AXElement(raw: element)
    }

    public func boolAttribute(_ name: String) -> Bool? {
        (attribute(name) as CFBoolean?).map { CFBooleanGetValue($0) }
    }
}
