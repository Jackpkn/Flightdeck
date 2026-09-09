import Testing
import Foundation
@testable import Flightdeck

@Suite("SystemTelemetryTests")
struct SystemTelemetryTests {
    @Test("System CPU usage returns valid percentage range")
    func systemCPURange() {
        let telemetry = SystemTelemetry()
        // First call establishes baseline
        _ = telemetry.currentCPUUsage()
        // Short pause to accumulate ticks
        Thread.sleep(forTimeInterval: 0.05)
        let cpu = telemetry.currentCPUUsage()
        #expect(cpu >= 0.0 && cpu <= 100.0)
    }

    @Test("System Memory snapshot returns realistic physical memory stats")
    func systemMemoryStats() {
        let telemetry = SystemTelemetry()
        let mem = telemetry.currentMemory()
        #expect(mem.totalBytes > 1_000_000_000) // At least 1 GB RAM
        #expect(mem.usedBytes > 0)
        #expect(mem.usedBytes <= mem.totalBytes)
        #expect(mem.fraction >= 0.0 && mem.fraction <= 1.0)
    }

    @Test("Network throughput samples without crashing")
    func networkThroughput() {
        let telemetry = SystemTelemetry()
        _ = telemetry.currentNetworkThroughputKB()
        Thread.sleep(forTimeInterval: 0.02)
        let kb = telemetry.currentNetworkThroughputKB()
        #expect(kb >= 0.0)
    }

    @Test("Disk throughput samples without crashing")
    func diskThroughput() {
        let telemetry = SystemTelemetry()
        _ = telemetry.currentDiskThroughputKB()
        Thread.sleep(forTimeInterval: 0.02)
        let kb = telemetry.currentDiskThroughputKB()
        #expect(kb >= 0.0)
    }

    @Test("GPU telemetry returns valid utilization and memory metrics")
    func gpuTelemetry() {
        let telemetry = SystemTelemetry()
        let gpu = telemetry.currentGPUTelemetry()
        #expect(gpu.utilizationPercent >= 0.0 && gpu.utilizationPercent <= 100.0)
        #expect(gpu.rendererPercent >= 0.0 && gpu.rendererPercent <= 100.0)
        #expect(gpu.tilerPercent >= 0.0 && gpu.tilerPercent <= 100.0)
        #expect(gpu.memoryBytes >= 0)
    }

    @Test("Per-core CPU usage returns valid load for each hardware core")
    func perCoreCPURange() {
        let telemetry = SystemTelemetry()
        _ = telemetry.currentPerCoreCPU()
        Thread.sleep(forTimeInterval: 0.05)
        let cores = telemetry.currentPerCoreCPU()
        #expect(!cores.isEmpty)
        #expect(cores.count == ProcessInfo.processInfo.processorCount)
        for load in cores {
            #expect(load >= 0.0 && load <= 100.0)
        }
    }

    @Test("SleepPreventer toggles active state cleanly")
    func sleepPreventerLifecycle() {
        let preventer = SleepPreventer()
        #expect(preventer.isAwake == false)
        preventer.activate()
        #expect(preventer.isAwake == true)
        preventer.deactivate()
        #expect(preventer.isAwake == false)
        preventer.toggle()
        #expect(preventer.isAwake == true)
        preventer.toggle()
        #expect(preventer.isAwake == false)
    }
}

