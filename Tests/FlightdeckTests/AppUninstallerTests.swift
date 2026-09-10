import Testing
import Foundation
@testable import Flightdeck

@Suite("AppUninstallerTests")
struct AppUninstallerTests {

    @Test("Discovers installed applications from system and user directories")
    func discoverInstalledApps() {
        let apps = AppUninstaller.discoverInstalledApps()
        #expect(!apps.isEmpty)

        // Standard macOS apps should be found
        let names = apps.map { $0.name.lowercased() }
        let hasCommonApp = names.contains { $0.contains("safari") || $0.contains("terminal") || $0.contains("notes") || $0.contains("finder") }
        #expect(hasCommonApp)
    }

    @Test("System applications are marked with isSystemApp = true")
    func systemAppsAreProtected() {
        let apps = AppUninstaller.discoverInstalledApps()
        let systemApps = apps.filter(\.isSystemApp)

        #expect(!systemApps.isEmpty)
        for app in systemApps {
            #expect(app.bundleURL.path.hasPrefix("/System") || FileGuard.isSystemProtected(app.bundleURL.path))
        }
    }

    @Test("findRelatedPaths resolves candidate ~/Library directories safely")
    func findRelatedPathsResolution() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Test with a mock bundle id
        let paths = AppUninstaller.findRelatedPaths(
            bundleId: "com.apple.dt.Xcode",
            appName: "Xcode",
            home: home
        )

        // Related paths should always reside in ~/Library
        for item in paths {
            #expect(item.url.path.hasPrefix(home.path + "/Library"))
            #expect(item.sizeBytes >= 0)
        }
    }

    @Test("Orphaned leftover discovery ignores currently known bundle IDs")
    func orphanedDiscoveryFiltersKnownBundles() {
        let known: Set<String> = ["com.apple.dt.Xcode", "com.google.Chrome", "com.microsoft.VSCode"]
        let orphans = AppUninstaller.discoverOrphanedLeftovers(knownBundleIds: known)

        for orphan in orphans {
            #expect(!known.contains(orphan.bundleId))
            #expect(!orphan.bundleId.hasPrefix("com.apple."))
        }
    }

    @Test("InstalledApp computes storage breakdown correctly")
    func storageBreakdownCalculation() {
        let dummyBundle = URL(fileURLWithPath: "/Applications/TestApp.app")
        let related = [
            RelatedPath(url: URL(fileURLWithPath: "/Users/test/Library/Application Support/TestApp"), category: .applicationSupport, sizeBytes: 50 * 1024 * 1024),
            RelatedPath(url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.test.app"), category: .caches, sizeBytes: 25 * 1024 * 1024),
            RelatedPath(url: URL(fileURLWithPath: "/Users/test/Library/Saved Application State/com.test.app.savedState"), category: .savedState, sizeBytes: 5 * 1024 * 1024)
        ]

        let app = InstalledApp(
            name: "TestApp",
            bundleId: "com.test.app",
            version: "2.1.0",
            bundleURL: dummyBundle,
            appBinarySize: 100 * 1024 * 1024,
            relatedPaths: related,
            isSystemApp: false
        )

        #expect(app.appBinarySize == 100 * 1024 * 1024)
        #expect(app.userDataSize == 50 * 1024 * 1024)
        #expect(app.cachesSize == 30 * 1024 * 1024)
        #expect(app.totalSizeBytes == 180 * 1024 * 1024)
    }
}
