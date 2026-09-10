import Darwin
import Foundation
import SwiftUI

/// A single developer process reparented to PID 1 without a controlling terminal (orphan/zombie).
public struct OrphanProcess: Identifiable, Hashable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let path: String
    public let memoryBytes: Int64
    public let isZombie: Bool

    public init(
        pid: pid_t,
        name: String,
        path: String,
        memoryBytes: Int64,
        isZombie: Bool = false
    ) {
        self.pid = pid
        self.name = name
        self.path = path
        self.memoryBytes = memoryBytes
        self.isZombie = isZombie
    }
}

/// Zero-subprocess Darwin kernel C monitor identifying runaway orphaned developer processes
/// (`ppid == 1` and `e_tdev == NODEV`) that linger after a terminal or IDE was closed.
@Observable
public final class ZombieDetector {
    public static let shared = ZombieDetector()

    public private(set) var orphans: [OrphanProcess] = []
    public private(set) var isScanning = false
    public var totalWastedBytes: Int64 {
        orphans.reduce(0) { $0 + $1.memoryBytes }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.flightdeck.zombiedetector", qos: .utility)

    public static let devKeywords = [
        "node", "python", "dart", "ruby", "java", "rustc", "swift-frontend",
        "esbuild", "webpack", "tsc", "gradle", "bun", "deno", "next-server",
        "flutter", "gunicorn", "uvicorn", "cargo"
    ]

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        scan()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - In-Process Darwin C Scanning

    public func scan() {
        guard !isScanning else { return }
        isScanning = true

        queue.async { [weak self] in
            guard let self else { return }
            let detected = Self.discoverOrphans()
            DispatchQueue.main.async {
                if self.orphans != detected {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.orphans = detected
                    }
                }
                self.isScanning = false
            }
        }
    }

    public static func discoverOrphans() -> [OrphanProcess] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(MemoryLayout<pid_t>.size * pids.count)
        )
        guard byteCount > 0 else { return [] }
        let count = Int(byteCount) / MemoryLayout<pid_t>.size
        let selfPid = ProcessInfo.processInfo.processIdentifier

        var results: [OrphanProcess] = []

        for i in 0..<count {
            let pid = pids[i]
            // Never touch PID 0, 1, or Flightdeck itself
            guard pid > 1 && pid != selfPid else { continue }

            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { continue }

            // Parent must be launchd (PPID 1)
            guard bsd.pbi_ppid == 1 else { continue }

            // Must have NO controlling terminal (NODEV / 0xFFFFFFFF or 0)
            let noTerminal = bsd.e_tdev == 4294967295 || bsd.e_tdev == 0
            guard noTerminal else { continue }

            // Fetch executable path
            var pathBuffer = [CChar](repeating: 0, count: 1024)
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = pathLen > 0 ? String(cString: pathBuffer) : ""
            guard !path.isEmpty else { continue }

            // Must NOT be a system daemon under /System or /usr/libexec or /Library/Apple
            if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/Library/Apple/") {
                continue
            }

            // Must match known developer runtime keywords
            let lowerPath = path.lowercased()
            let isDevProcess = devKeywords.contains(where: { lowerPath.contains($0) })
            guard isDevProcess else { continue }

            // Query memory footprint
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            var memBytes: Int64 = 0
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize {
                memBytes = Int64(task.pti_resident_size)
            }

            let pName = URL(fileURLWithPath: path).lastPathComponent
            let isZombieStatus = bsd.pbi_status == 5 // SZOMB in Darwin

            results.append(OrphanProcess(
                pid: pid,
                name: pName.isEmpty ? "Unknown" : pName,
                path: path,
                memoryBytes: memBytes,
                isZombie: isZombieStatus
            ))
        }

        // Sort descending by memory footprint
        return results.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    public private(set) var isPurging = false

    // MARK: - Actions

    public func killOrphan(pid: pid_t) {
        guard isKillable(pid: pid) else { return }
        CockpitAudio.playPing()

        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            orphans.removeAll { $0.pid == pid }
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.terminatePid(pid)
            usleep(800_000)
            self.scan()
        }
    }

    public func purgeAllOrphans() {
        let targets = orphans
        guard !targets.isEmpty, !isPurging else { return }
        isPurging = true
        CockpitAudio.playPing()

        queue.async { [weak self] in
            guard let self else { return }
            // Terminate all target PIDs with SIGTERM then SIGKILL
            for target in targets {
                if self.isKillable(pid: target.pid) {
                    kill(target.pid, SIGTERM)
                    kill(target.pid, SIGKILL)
                }
            }
            // Allow launchd 1000ms to reap child processes from the system process table
            usleep(1_000_000)
            let detected = Self.discoverOrphans()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    self.orphans = detected
                }
                self.isPurging = false
            }
        }
    }

    public func isKillable(pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        return true
    }

    private func terminatePid(_ pid: pid_t) {
        kill(pid, SIGTERM)
        kill(pid, SIGKILL)
    }
}
