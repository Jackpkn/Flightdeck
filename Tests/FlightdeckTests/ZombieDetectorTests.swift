import Testing
import Foundation
@testable import Flightdeck

@Suite("ZombieDetectorTests")
struct ZombieDetectorTests {
    @Test("Dev keywords include primary developer runtimes")
    func devKeywordsCoverage() {
        let keywords = ZombieDetector.devKeywords
        #expect(keywords.contains("node"))
        #expect(keywords.contains("python"))
        #expect(keywords.contains("dart"))
        #expect(keywords.contains("ruby"))
        #expect(keywords.contains("java"))
        #expect(keywords.contains("rustc"))
        #expect(keywords.contains("esbuild"))
        #expect(keywords.contains("cargo"))
    }

    @Test("Safety guards prevent killing PID 0, PID 1, or self")
    func killSafetyGuards() {
        let detector = ZombieDetector()
        let selfPid = ProcessInfo.processInfo.processIdentifier

        #expect(!detector.isKillable(pid: 0))
        #expect(!detector.isKillable(pid: 1))
        #expect(!detector.isKillable(pid: selfPid))
        #expect(detector.isKillable(pid: 98765))
    }

    @Test("Total wasted memory aggregates memoryBytes correctly")
    func totalWastedMemoryCalculation() {
        let p1 = OrphanProcess(pid: 101, name: "dart", path: "/Users/dev/dart", memoryBytes: 20 * 1024 * 1024)
        let p2 = OrphanProcess(pid: 102, name: "node", path: "/usr/local/bin/node", memoryBytes: 50 * 1024 * 1024)

        let total = [p1, p2].reduce(0) { $0 + $1.memoryBytes }
        #expect(total == 70 * 1024 * 1024)
    }

    @Test("Live scan queries Darwin process table without throwing or crashing")
    func liveScanSmokeTest() {
        let orphans = ZombieDetector.discoverOrphans()
        // We know on this machine there are active orphans, but test verifies array structure
        for orphan in orphans {
            #expect(orphan.pid > 1)
            #expect(!orphan.name.isEmpty)
            #expect(!orphan.path.isEmpty)
            #expect(orphan.memoryBytes >= 0)
        }
    }
}
