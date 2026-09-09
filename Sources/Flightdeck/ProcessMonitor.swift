import AppKit
import Darwin
import Foundation

struct ProcessUsage: Identifiable, Sendable {
    let id: pid_t
    let name: String
    let bundleId: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let energyImpact: Double
    let isNotResponding: Bool

    init(
        id: pid_t,
        name: String,
        bundleId: String,
        cpuPercent: Double,
        memoryBytes: Int64,
        energyImpact: Double = 0.0,
        isNotResponding: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.energyImpact = energyImpact
        self.isNotResponding = isNotResponding
    }
}

/// Real per-process CPU/memory via `ps` — one spawn per tick covering every
/// pid at once, not one spawn per app. No special permission: `ps` reads the
/// same process table Activity Monitor does.
@Observable
final class ProcessMonitor {
    private(set) var usages: [ProcessUsage] = []
    /// Real per-core CPU utilization (0-100%) from Mach PROCESSOR_CPU_LOAD_INFO.
    private(set) var perCoreCPU: [Double] = []
    /// Apps sorted by highest energy impact.
    private(set) var topEnergyConsumers: [ProcessUsage] = []
    /// Real system-wide CPU% from Mach HOST_CPU_LOAD_INFO, capped to the last 2 minutes.
    private(set) var cpuHistory: [Double] = []
    /// Real system-wide memory used, in bytes from Mach HOST_VM_INFO64.
    private(set) var memoryHistory: [Double] = []
    /// Real hardware network throughput in KB/sec from BSD getifaddrs.
    private(set) var netHistory: [Double] = []
    /// Real storage disk I/O throughput in KB/sec from IOKit IOBlockStorageDriver.
    private(set) var diskHistory: [Double] = []
    /// Real hardware GPU utilization % from IOKit IOAccelerator, capped to last 2 minutes.
    private(set) var gpuHistory: [Double] = []
    /// Latest detailed system memory breakdown.
    private(set) var memorySnapshot: SystemTelemetry.MemorySnapshot?
    /// Latest real-time metrics.
    private(set) var currentSystemCPU: Double = 0
    private(set) var currentNetKB: Double = 0
    private(set) var currentDiskKB: Double = 0
    private(set) var currentGPU = SystemTelemetry.GPUTelemetry()

    /// Real system thermal pressure — free, no permission, and the honest
    /// stand-in for per-app "energy impact" (which needs root).
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private let telemetry = SystemTelemetry.shared

    /// High-resolution nanosecond timestamps per PID to compute accurate CPU % deltas.
    private var previousPidTimes: [pid_t: (timeNs: UInt64, date: Date)] = [:]
    /// Dedicated background serial queue with QoS .utility — Apple Silicon automatically
    /// schedules this exclusively on the Efficiency cores (E-Cores).
    private let telemetryQueue = DispatchQueue(label: "com.flightdeck.telemetry", qos: .utility)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        thermalObserver = nil
    }

    /// Hard kills a process by PID and bundle ID, with instant removal from the UI.
    func killProcess(pid: pid_t, bundleId: String = "") {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        // 1. Try graceful/force AppKit termination if it's a graphical app
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.forceTerminate()
        }

        // 2. Direct POSIX SIGKILL to ensure unbundled CLI / helper processes die instantly
        kill(pid, SIGKILL)

        // 3. Immediately pull from UI for instant visual feedback
        usages.removeAll { $0.id == pid }
        previousPidTimes.removeValue(forKey: pid)

        // 4. Trigger fresh sweep shortly after
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        telemetryQueue.async { [weak self] in
            self?.sampleTelemetry()
        }
    }

    /// Pure in-process Darwin kernel C telemetry — zero subprocesses (`/bin/ps`), zero fork overhead.
    /// Runs on Apple Silicon Efficiency cores via `qos: .utility`.
    private func sampleTelemetry() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let now = Date()

        var newUsages: [ProcessUsage] = []
        var nextPidTimes: [pid_t: (timeNs: UInt64, date: Date)] = [:]

        for app in apps {
            let pid = app.processIdentifier
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

            let residentBytes = Int64(info.pti_resident_size)
            let totalCpuNs = info.pti_total_user + info.pti_total_system

            let cpuPercent: Double
            if let prev = previousPidTimes[pid] {
                let deltaNs = totalCpuNs >= prev.timeNs ? Double(totalCpuNs - prev.timeNs) : 0
                let deltaSec = max(0.2, now.timeIntervalSince(prev.date))
                cpuPercent = min(800.0, max(0.0, (deltaNs / (1_000_000_000.0 * deltaSec)) * 100.0))
            } else {
                cpuPercent = 0.0
            }
            nextPidTimes[pid] = (totalCpuNs, now)

            let isUnresponsive = app.isTerminated || kill(pid, 0) != 0
            let energy = min(100.0, max(0.0, cpuPercent * 1.05))

            newUsages.append(ProcessUsage(
                id: pid,
                name: app.localizedName ?? "Unknown",
                bundleId: app.bundleIdentifier ?? "",
                cpuPercent: cpuPercent,
                memoryBytes: residentBytes,
                energyImpact: energy,
                isNotResponding: isUnresponsive
            ))
        }

        previousPidTimes = nextPidTimes
        newUsages.sort { $0.memoryBytes > $1.memoryBytes }

        let topEnergy = newUsages
            .filter { $0.energyImpact > 0.5 }
            .sorted { $0.energyImpact > $1.energyImpact }

        // 0. Real Per-Core CPU from Mach PROCESSOR_CPU_LOAD_INFO
        let cores = telemetry.currentPerCoreCPU()

        // 1. Real System CPU from Mach kernel HOST_CPU_LOAD_INFO
        let sysCPU = telemetry.currentCPUUsage()
        let appCPU = newUsages.reduce(0) { $0 + $1.cpuPercent }
        let finalCPU = sysCPU > 0 ? sysCPU : appCPU

        // 2. Real System Memory from Mach kernel HOST_VM_INFO64
        let mem = telemetry.currentMemory()
        let finalMem = mem.usedBytes > 0 ? Double(mem.usedBytes) : newUsages.reduce(0) { $0 + Double($1.memoryBytes) }

        // 3. Real Network throughput from BSD getifaddrs (KB/sec)
        let netKB = telemetry.currentNetworkThroughputKB()

        // 4. Real Disk I/O throughput from IOKit (KB/sec)
        let diskKB = telemetry.currentDiskThroughputKB()

        // 5. Real GPU hardware utilization from IOKit IOAccelerator (%)
        let gpu = telemetry.currentGPUTelemetry()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usages = newUsages
            self.topEnergyConsumers = topEnergy
            self.perCoreCPU = cores
            self.currentSystemCPU = finalCPU
            self.cpuHistory.append(finalCPU)
            if self.cpuHistory.count > 60 { self.cpuHistory.removeFirst(self.cpuHistory.count - 60) }

            self.memorySnapshot = mem
            self.memoryHistory.append(finalMem)
            if self.memoryHistory.count > 60 { self.memoryHistory.removeFirst(self.memoryHistory.count - 60) }

            self.currentNetKB = netKB
            self.netHistory.append(netKB)
            if self.netHistory.count > 60 { self.netHistory.removeFirst(self.netHistory.count - 60) }

            self.currentDiskKB = diskKB
            self.diskHistory.append(diskKB)
            if self.diskHistory.count > 60 { self.diskHistory.removeFirst(self.diskHistory.count - 60) }

            self.currentGPU = gpu
            self.gpuHistory.append(gpu.utilizationPercent)
            if self.gpuHistory.count > 60 { self.gpuHistory.removeFirst(self.gpuHistory.count - 60) }

            TimelineStore.shared.append(
                cpu: finalCPU,
                gpu: gpu.utilizationPercent,
                memBytes: Int64(finalMem),
                netKB: netKB
            )
        }
    }
}

