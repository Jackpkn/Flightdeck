import AppKit
import Foundation

struct ProcessUsage: Identifiable {
    let id: pid_t
    let name: String
    let bundleId: String
    let cpuPercent: Double
    let memoryBytes: Int64
}

/// Real per-process CPU/memory via `ps` — one spawn per tick covering every
/// pid at once, not one spawn per app. No special permission: `ps` reads the
/// same process table Activity Monitor does.
@Observable
final class ProcessMonitor {
    private(set) var usages: [ProcessUsage] = []
    /// Real system-wide CPU% from Mach HOST_CPU_LOAD_INFO, capped to the last 2 minutes.
    private(set) var cpuHistory: [Double] = []
    /// Real system-wide memory used, in bytes from Mach HOST_VM_INFO64.
    private(set) var memoryHistory: [Double] = []
    /// Real hardware network throughput in KB/sec from BSD getifaddrs.
    private(set) var netHistory: [Double] = []
    /// Real storage disk I/O throughput in KB/sec from IOKit IOBlockStorageDriver.
    private(set) var diskHistory: [Double] = []
    /// Latest detailed system memory breakdown.
    private(set) var memorySnapshot: SystemTelemetry.MemorySnapshot?
    /// Latest real-time metrics.
    private(set) var currentSystemCPU: Double = 0
    private(set) var currentNetKB: Double = 0
    private(set) var currentDiskKB: Double = 0

    /// Real system thermal pressure — free, no permission, and the honest
    /// stand-in for per-app "energy impact" (which needs root).
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private let telemetry = SystemTelemetry.shared

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

        // 4. Trigger fresh sweep shortly after
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard !apps.isEmpty else {
            usages = []
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,rss=,pcpu="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        var byPid: [pid_t: (rssKB: Int64, cpu: Double)] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = pid_t(parts[0]),
                  let rss = Int64(parts[1]),
                  let cpu = Double(parts[2])
            else { continue }
            byPid[pid] = (rss, cpu)
        }

        usages = apps.compactMap { app -> ProcessUsage? in
            guard let stats = byPid[app.processIdentifier] else { return nil }
            return ProcessUsage(
                id: app.processIdentifier,
                name: app.localizedName ?? "Unknown",
                bundleId: app.bundleIdentifier ?? "",
                cpuPercent: stats.cpu,
                memoryBytes: stats.rssKB * 1024
            )
        }.sorted { $0.memoryBytes > $1.memoryBytes }

        // 1. Real System CPU from Mach kernel HOST_CPU_LOAD_INFO
        let sysCPU = telemetry.currentCPUUsage()
        let appCPU = usages.reduce(0) { $0 + $1.cpuPercent }
        let finalCPU = sysCPU > 0 ? sysCPU : appCPU
        currentSystemCPU = finalCPU
        cpuHistory.append(finalCPU)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }

        // 2. Real System Memory from Mach kernel HOST_VM_INFO64
        let mem = telemetry.currentMemory()
        memorySnapshot = mem
        let finalMem = mem.usedBytes > 0 ? Double(mem.usedBytes) : usages.reduce(0) { $0 + Double($1.memoryBytes) }
        memoryHistory.append(finalMem)
        if memoryHistory.count > 60 { memoryHistory.removeFirst(memoryHistory.count - 60) }

        // 3. Real Network throughput from BSD getifaddrs (KB/sec)
        let netKB = telemetry.currentNetworkThroughputKB()
        currentNetKB = netKB
        netHistory.append(netKB)
        if netHistory.count > 60 { netHistory.removeFirst(netHistory.count - 60) }

        // 4. Real Disk I/O throughput from IOKit (KB/sec)
        let diskKB = telemetry.currentDiskThroughputKB()
        currentDiskKB = diskKB
        diskHistory.append(diskKB)
        if diskHistory.count > 60 { diskHistory.removeFirst(diskHistory.count - 60) }
    }
}
