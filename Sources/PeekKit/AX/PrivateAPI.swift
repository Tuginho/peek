import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Access to `_AXUIElementGetWindow`, a private accessibility symbol that maps an
/// `AXUIElement` window to its `CGWindowID`. There is no public API for this.
enum PrivateAPI {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow = symbol("_AXUIElementGetWindow", as: GetWindowFunction.self)

    /// Looks a C function up in every image loaded into the process (`RTLD_DEFAULT`).
    static func symbol<Function>(_ name: String, as type: Function.Type) -> Function? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static var isWindowIDLookupAvailable: Bool {
        getWindow != nil
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var windowID: CGWindowID = 0
        let error = getWindow(element, &windowID)
        guard error == .success, windowID != 0 else { return nil }
        return windowID
    }
}

/// Access to `CGSCopyManagedDisplaySpaces`, a private SkyLight call that reports which Space
/// each display currently shows. There is no public API to tell a full-screen app Space apart.
enum SpacesAPI {
    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let mainConnection = PrivateAPI.symbol("CGSMainConnectionID", as: MainConnectionFunction.self)
    private static let copyManagedDisplaySpaces = PrivateAPI.symbol(
        "CGSCopyManagedDisplaySpaces",
        as: CopyManagedDisplaySpacesFunction.self
    )

    /// Space type SkyLight reports for a full-screen app Space (0 is a regular desktop).
    private static let fullScreenSpaceType = 4

    /// Identifiers of the displays whose current Space is a full-screen app Space: display UUID
    /// strings, or `"Main"` for every display when "Displays have separate Spaces" is off.
    /// Empty when the private symbols are unavailable.
    static func displaysShowingFullScreenSpace() -> Set<String> {
        guard let mainConnection, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        var result: Set<String> = []
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let currentSpace = display["Current Space"] as? [String: Any],
                  currentSpace["type"] as? Int == fullScreenSpaceType
            else { continue }
            result.insert(identifier)
        }
        return result
    }

    static func uuidString(of screen: NSScreen) -> String? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
