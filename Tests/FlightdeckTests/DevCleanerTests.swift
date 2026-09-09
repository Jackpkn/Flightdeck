import Testing
import Foundation
@testable import Flightdeck

@Suite("DevCleanerTests")
struct DevCleanerTests {
    @Test("Default targets include primary dev build caches")
    func defaultTargetsCoverage() {
        let targets = DevCleaner.defaultTargets
        let ids = targets.map(\.id)

        #expect(ids.contains("xcode_derived_data"))
        #expect(ids.contains("npm_cache"))
        #expect(ids.contains("gradle_cache"))
        #expect(ids.contains("spm_cache"))
        #expect(ids.contains("cocoapods_cache"))
        #expect(ids.contains("simulator_cache"))
    }

    @Test("All target paths reside securely inside user home directory")
    func targetPathsSafety() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targets = DevCleaner.defaultTargets

        for target in targets {
            #expect(target.path.path.hasPrefix(home))
            #expect(!target.path.path.hasPrefix("/System"))
            #expect(!target.path.path.hasPrefix("/usr"))
        }
    }

    @Test("Directory size calculation returns 0 for non-existent directory")
    func nonExistentDirSize() {
        let nonExistent = URL(fileURLWithPath: "/tmp/flightdeck_fake_nonexistent_cache_\(UUID().uuidString)")
        let size = DevCleaner.calculateDirectorySize(at: nonExistent)
        #expect(size == 0)
    }

    @Test("Total cruft bytes aggregates sizeBytes across categories")
    func totalCruftBytesAggregation() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var c1 = CruftCategory(id: "c1", name: "C1", icon: "hammer", path: home)
        c1.sizeBytes = 1024 * 1024 * 50 // 50 MB
        var c2 = CruftCategory(id: "c2", name: "C2", icon: "cube", path: home)
        c2.sizeBytes = 1024 * 1024 * 100 // 100 MB

        let total = [c1, c2].reduce(0) { $0 + $1.sizeBytes }
        #expect(total == 150 * 1024 * 1024)
    }

    @Test("Safety guard refuses to purge paths outside user home or non-cache directories")
    func safetyRefusesRootOrDangerousPaths() {
        let root = URL(fileURLWithPath: "/")
        #expect(DevCleaner.safelyEmptyDirectory(at: root) == 0)

        let etc = URL(fileURLWithPath: "/etc")
        #expect(DevCleaner.safelyEmptyDirectory(at: etc) == 0)
    }
}
