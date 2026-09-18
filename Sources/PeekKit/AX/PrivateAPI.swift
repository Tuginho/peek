import ApplicationServices
import CoreGraphics
import Foundation

/// Access to `_AXUIElementGetWindow`, a private accessibility symbol that maps an
/// `AXUIElement` window to its `CGWindowID`. There is no public API for this.
enum PrivateAPI {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

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
