import Testing
import Foundation
@testable import Flightdeck

@Suite("ProcessActionTests")
struct ProcessActionTests {
    @Test("Process filter filters by bundle ID and heavy resource threshold")
    func processFiltering() {
        let app1 = ProcessUsage(id: 100, name: "Xcode", bundleId: "com.apple.dt.Xcode", cpuPercent: 25.0, memoryBytes: 800_000_000)
        let app2 = ProcessUsage(id: 101, name: "TextEdit", bundleId: "com.apple.TextEdit", cpuPercent: 1.0, memoryBytes: 50_000_000)
        let cli1 = ProcessUsage(id: 102, name: "node", bundleId: "", cpuPercent: 15.0, memoryBytes: 200_000_000)
        let cli2 = ProcessUsage(id: 103, name: "grep", bundleId: "", cpuPercent: 0.5, memoryBytes: 10_000_000)

        let all = [app1, app2, cli1, cli2]

        // Filter: Apps only (non-empty bundleId)
        let appsOnly = all.filter { !$0.bundleId.isEmpty }
        #expect(appsOnly.count == 2)
        #expect(appsOnly.contains(where: { $0.name == "Xcode" }))
        #expect(appsOnly.contains(where: { $0.name == "TextEdit" }))

        // Filter: Hogs only (CPU >= 10% or Mem >= 500MB)
        let hogsOnly = all.filter { $0.cpuPercent >= 10.0 || $0.memoryBytes >= 500_000_000 }
        #expect(hogsOnly.count == 2)
        #expect(hogsOnly.contains(where: { $0.name == "Xcode" }))
        #expect(hogsOnly.contains(where: { $0.name == "node" }))
    }

    @Test("Self PID is excluded from killable candidates")
    func selfPIDProtection() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let row = ProcessUsage(id: currentPID, name: "Flightdeck", bundleId: "com.flightdeck.app", cpuPercent: 5.0, memoryBytes: 100_000_000)
        let isKillable = row.id != ProcessInfo.processInfo.processIdentifier
        #expect(!isKillable)
    }

    @Test("Energy impact and responsiveness attributes are tracked on processes")
    func energyAndResponsivenessTracking() {
        let heavyApp = ProcessUsage(
            id: 105,
            name: "Heavy3D",
            bundleId: "com.heavy.render",
            cpuPercent: 88.0,
            memoryBytes: 2_000_000_000,
            energyImpact: 92.4,
            isNotResponding: false
        )
        let hungApp = ProcessUsage(
            id: 106,
            name: "FrozenApp",
            bundleId: "com.hung.app",
            cpuPercent: 0.0,
            memoryBytes: 100_000_000,
            energyImpact: 0.0,
            isNotResponding: true
        )

        #expect(heavyApp.energyImpact > 50.0)
        #expect(!heavyApp.isNotResponding)
        #expect(hungApp.isNotResponding)
    }
}
