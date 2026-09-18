import CoreGraphics
import Foundation

@MainActor
public final class Settings: ObservableObject {
    public enum ThumbnailSize: String, CaseIterable {
        case small, medium, large

        public var width: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 280
            case .large: return 360
            }
        }

        public var height: CGFloat {
            width * 0.625
        }

        public var label: String {
            switch self {
            case .small: return "Klein"
            case .medium: return "Mittel"
            case .large: return "Groß"
            }
        }
    }

    public enum HideMethod: String, CaseIterable, Codable {
        case park
        case minimize

        public var label: String {
            switch self {
            case .park: return "Sofort ausblenden (ohne Animation)"
            case .minimize: return "Minimieren (mit Animation)"
            }
        }
    }

    public enum DockClickRestoreMode: String, CaseIterable {
        case peekHiddenOnly
        case allMinimized

        public var label: String {
            switch self {
            case .peekHiddenOnly: return "Nur von Peek versteckte Fenster"
            case .allMinimized: return "Alle minimierten Fenster"
            }
        }
    }

    public static let hoverDelayPresets = [150, 300, 500, 800]

    private static let defaultExcludedBundleIDs = [
        "com.apple.ScreenSharing",
        "com.microsoft.rdc.macos",
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "com.utmapp.UTM",
    ]

    @Published public var hoverPreviewEnabled: Bool {
        didSet { defaults.set(hoverPreviewEnabled, forKey: Key.hoverPreviewEnabled) }
    }

    @Published public var singleWindowHideEnabled: Bool {
        didSet { defaults.set(singleWindowHideEnabled, forKey: Key.singleWindowHideEnabled) }
    }

    @Published public var hideMethod: HideMethod {
        didSet { defaults.set(hideMethod.rawValue, forKey: Key.hideMethod) }
    }

    @Published public var hoverDelayMs: Int {
        didSet { defaults.set(hoverDelayMs, forKey: Key.hoverDelayMs) }
    }

    @Published public var thumbnailSize: ThumbnailSize {
        didSet { defaults.set(thumbnailSize.rawValue, forKey: Key.thumbnailSize) }
    }

    @Published public var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    @Published public var dockClickRestoreMode: DockClickRestoreMode {
        didSet { defaults.set(dockClickRestoreMode.rawValue, forKey: Key.dockClickRestoreMode) }
    }

    @Published public var restoreOnActivate: Bool {
        didSet { defaults.set(restoreOnActivate, forKey: Key.restoreOnActivate) }
    }

    @Published public var showDockBadges: Bool {
        didSet { defaults.set(showDockBadges, forKey: Key.showDockBadges) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let hoverPreviewEnabled = "peek.hoverPreviewEnabled"
        static let singleWindowHideEnabled = "peek.singleWindowHideEnabled"
        static let hideMethod = "peek.hideMethod"
        static let hoverDelayMs = "peek.hoverDelayMs"
        static let thumbnailSize = "peek.thumbnailSize"
        static let excludedBundleIDs = "peek.excludedBundleIDs"
        static let dockClickRestoreMode = "peek.dockClickRestoreMode"
        static let restoreOnActivate = "peek.restoreOnActivate"
        static let showDockBadges = "peek.showDockBadges"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        hoverPreviewEnabled = (defaults.object(forKey: Key.hoverPreviewEnabled) as? Bool) ?? true
        singleWindowHideEnabled = (defaults.object(forKey: Key.singleWindowHideEnabled) as? Bool) ?? true
        hideMethod = (defaults.string(forKey: Key.hideMethod)).flatMap(HideMethod.init) ?? .park
        hoverDelayMs = (defaults.object(forKey: Key.hoverDelayMs) as? Int) ?? 150
        thumbnailSize = (defaults.string(forKey: Key.thumbnailSize)).flatMap(ThumbnailSize.init) ?? .medium
        excludedBundleIDs = (defaults.array(forKey: Key.excludedBundleIDs) as? [String]) ?? Settings.defaultExcludedBundleIDs
        dockClickRestoreMode = (defaults.string(forKey: Key.dockClickRestoreMode)).flatMap(DockClickRestoreMode.init) ?? .peekHiddenOnly
        restoreOnActivate = (defaults.object(forKey: Key.restoreOnActivate) as? Bool) ?? true
        showDockBadges = (defaults.object(forKey: Key.showDockBadges) as? Bool) ?? true
    }
}
