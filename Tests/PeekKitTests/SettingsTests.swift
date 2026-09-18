import Foundation
import Testing
@testable import PeekKit

@MainActor
struct SettingsTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "PeekKitTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func defaultsMatchSpec() {
        withDefaults { defaults in
            let settings = Settings(defaults: defaults)

            #expect(settings.hoverPreviewEnabled == true)
            #expect(settings.singleWindowHideEnabled == true)
            #expect(settings.hideMethod == .park)
            #expect(settings.hoverDelayMs == 150)
            #expect(Settings.hoverDelayPresets == [150, 300, 500, 800])
            #expect(settings.thumbnailSize == .medium)
            #expect(settings.excludedBundleIDs == [
                "com.apple.ScreenSharing",
                "com.microsoft.rdc.macos",
                "com.parallels.desktop.console",
                "com.vmware.fusion",
                "com.utmapp.UTM",
            ])
            #expect(settings.dockClickRestoreMode == .peekHiddenOnly)
            #expect(settings.restoreOnActivate == true)
            #expect(settings.showDockBadges == true)
        }
    }

    @Test func everyPropertyPersistsAndReloads() {
        withDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.hoverPreviewEnabled = false
            settings.singleWindowHideEnabled = false
            settings.hideMethod = .minimize
            settings.hoverDelayMs = 800
            settings.thumbnailSize = .large
            settings.excludedBundleIDs = ["com.example.one", "com.example.two"]
            settings.dockClickRestoreMode = .allMinimized
            settings.restoreOnActivate = false
            settings.showDockBadges = false

            let reloaded = Settings(defaults: defaults)
            #expect(reloaded.hoverPreviewEnabled == false)
            #expect(reloaded.singleWindowHideEnabled == false)
            #expect(reloaded.hideMethod == .minimize)
            #expect(reloaded.hoverDelayMs == 800)
            #expect(reloaded.thumbnailSize == .large)
            #expect(reloaded.excludedBundleIDs == ["com.example.one", "com.example.two"])
            #expect(reloaded.dockClickRestoreMode == .allMinimized)
            #expect(reloaded.restoreOnActivate == false)
            #expect(reloaded.showDockBadges == false)
        }
    }

    @Test func hideMethodLabels() {
        #expect(Settings.HideMethod.park.label == "Sofort ausblenden (ohne Animation)")
        #expect(Settings.HideMethod.minimize.label == "Minimieren (mit Animation)")
    }

    @Test func thumbnailSizeDimensions() {
        #expect(Settings.ThumbnailSize.small.width == 200)
        #expect(Settings.ThumbnailSize.small.height == 125)
        #expect(Settings.ThumbnailSize.medium.width == 280)
        #expect(Settings.ThumbnailSize.medium.height == 175)
        #expect(Settings.ThumbnailSize.large.width == 360)
        #expect(Settings.ThumbnailSize.large.height == 225)
    }
}
