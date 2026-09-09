import Darwin
import Darwin.Mach
import Foundation
import IOKit

/// Native macOS Mach kernel and POSIX C-level telemetry engine.
/// Reads real-time hardware telemetry directly from the operating system:
/// - System-wide CPU load via Mach `HOST_CPU_LOAD_INFO`
/// - System-wide RAM usage via Mach `HOST_VM_INFO64`
/// - Hardware Network throughput via BSD `getifaddrs`
/// - Storage Disk I/O throughput via IOKit `IOBlockStorageDriver`
public final class SystemTelemetry: @unchecked Sendable {
    public static let shared = SystemTelemetry()

    private var previousCpuTicks: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNetBytes: (rx: UInt64, tx: UInt64, time: Date)?
    private var previousDiskBytes: (total: UInt64, time: Date)?

    public init() {}

    // MARK: - 1. Real System CPU Load (Mach Kernel)

    /// Returns the true system-wide CPU utilization (0.0 to 100.0%) across all cores.
    public func currentCPUUsage() -> Double {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }

        let user = loadInfo.cpu_ticks.0
        let sys = loadInfo.cpu_ticks.1
        let idle = loadInfo.cpu_ticks.2
        let nice = loadInfo.cpu_ticks.3

        guard let prev = previousCpuTicks else {
            previousCpuTicks = (user, sys, idle, nice)
            return 0
        }

        let userDelta = user >= prev.user ? Double(user - prev.user) : 0
        let sysDelta = sys >= prev.sys ? Double(sys - prev.sys) : 0
        let idleDelta = idle >= prev.idle ? Double(idle - prev.idle) : 0
        let niceDelta = nice >= prev.nice ? Double(nice - prev.nice) : 0

        previousCpuTicks = (user, sys, idle, nice)

        let total = userDelta + sysDelta + idleDelta + niceDelta
        guard total > 0 else { return 0 }

        let active = userDelta + sysDelta + niceDelta
        return min(100.0, max(0.0, (active / total) * 100.0))
    }

    // MARK: - 2. Real System Memory (Mach VM Info)

    public struct MemorySnapshot {
        public let usedBytes: Int64
        public let totalBytes: Int64
        public let freeBytes: Int64
        public let activeBytes: Int64
        public let wiredBytes: Int64
        public let compressedBytes: Int64

        public var fraction: Double {
            totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        }
    }

    /// Returns the total resident, wired, and compressed memory in bytes.
    public func currentMemory() -> MemorySnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return MemorySnapshot(
                usedBytes: 0,
                totalBytes: total,
                freeBytes: total,
                activeBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0
            )
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = Int64(pageSize > 0 ? pageSize : 16384)

        let active = Int64(vmStats.active_count) * ps
        let wired = Int64(vmStats.wire_count) * ps
        let compressed = Int64(vmStats.compressor_page_count) * ps
        let free = Int64(vmStats.free_count) * ps
        let used = min(total, active + wired + compressed)

        return MemorySnapshot(
            usedBytes: used,
            totalBytes: total,
            freeBytes: free,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed
        )
    }

    // MARK: - 3. Real Network I/O Throughput (getifaddrs)

    /// Returns network throughput in KB/sec (received + sent across physical network interfaces).
    public func currentNetworkThroughputKB() -> Double {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return 0 }
        defer { freeifaddrs(ifap) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let name = String(cString: ptr.pointee.ifa_name)
            // Filter loopback (lo0) to track external ethernet/wifi
            if !name.hasPrefix("lo") && ptr.pointee.ifa_addr != nil {
                if ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = ptr.pointee.ifa_data {
                        let ifData = data.assumingMemoryBound(to: if_data.self)
                        totalRx += UInt64(ifData.pointee.ifi_ibytes)
                        totalTx += UInt64(ifData.pointee.ifi_obytes)
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        let now = Date()
        guard let prev = previousNetBytes else {
            previousNetBytes = (totalRx, totalTx, now)
            return 0
        }

        let elapsed = now.timeIntervalSince(prev.time)
        previousNetBytes = (totalRx, totalTx, now)

        guard elapsed > 0 else { return 0 }
        let rxDelta = totalRx >= prev.rx ? (totalRx - prev.rx) : 0
        let txDelta = totalTx >= prev.tx ? (totalTx - prev.tx) : 0
        let bytesPerSec = Double(rxDelta + txDelta) / elapsed
        return bytesPerSec / 1024.0 // KB/s
    }

    // MARK: - 4. Real Disk Storage I/O Throughput (IOKit)

    /// Returns disk I/O throughput in KB/sec across block storage drives.
    public func currentDiskThroughputKB() -> Double {
        var totalBytes: UInt64 = 0
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")

        let mainPort: mach_port_t = 0
        if IOServiceGetMatchingServices(mainPort, matching, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let stats = dict["Statistics"] as? [String: Any] {
                    if let r = stats["Bytes (Read)"] as? UInt64 { totalBytes += r }
                    else if let rNum = stats["Bytes (Read)"] as? NSNumber { totalBytes += rNum.uint64Value }

                    if let w = stats["Bytes (Write)"] as? UInt64 { totalBytes += w }
                    else if let wNum = stats["Bytes (Write)"] as? NSNumber { totalBytes += wNum.uint64Value }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let now = Date()
        guard let prev = previousDiskBytes else {
            previousDiskBytes = (totalBytes, now)
            return 0
        }

        let elapsed = now.timeIntervalSince(prev.time)
        previousDiskBytes = (totalBytes, now)

        guard elapsed > 0, totalBytes >= prev.total else { return 0 }
        let bytesPerSec = Double(totalBytes - prev.total) / elapsed
        return bytesPerSec / 1024.0 // KB/s
    }

    // MARK: - 5. Real GPU Hardware Utilization & VRAM (IOKit IOAccelerator)

    public struct GPUTelemetry: Equatable, Sendable {
        public let utilizationPercent: Double
        public let rendererPercent: Double
        public let tilerPercent: Double
        public let memoryBytes: Int64

        public init(
            utilizationPercent: Double = 0,
            rendererPercent: Double = 0,
            tilerPercent: Double = 0,
            memoryBytes: Int64 = 0
        ) {
            self.utilizationPercent = utilizationPercent
            self.rendererPercent = rendererPercent
            self.tilerPercent = tilerPercent
            self.memoryBytes = memoryBytes
        }
    }

    /// Returns the true system GPU utilization % and VRAM allocated across all accelerators (Apple Silicon & Intel).
    public func currentGPUTelemetry() -> GPUTelemetry {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let mainPort: mach_port_t = 0

        guard IOServiceGetMatchingServices(mainPort, matching, &iterator) == kIOReturnSuccess else {
            return GPUTelemetry()
        }

        var maxDeviceUtil: Double = 0
        var maxRenderUtil: Double = 0
        var maxTilerUtil: Double = 0
        var totalMemory: Int64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {

                if let u = stats["Device Utilization %"] as? NSNumber {
                    maxDeviceUtil = max(maxDeviceUtil, u.doubleValue)
                }
                if let r = stats["Renderer Utilization %"] as? NSNumber {
                    maxRenderUtil = max(maxRenderUtil, r.doubleValue)
                }
                if let t = stats["Tiler Utilization %"] as? NSNumber {
                    maxTilerUtil = max(maxTilerUtil, t.doubleValue)
                }
                if let mem = stats["In use system memory"] as? NSNumber {
                    totalMemory += mem.int64Value
                } else if let memAlloc = stats["Alloc system memory"] as? NSNumber {
                    totalMemory += memAlloc.int64Value
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        return GPUTelemetry(
            utilizationPercent: min(100.0, max(0.0, maxDeviceUtil)),
            rendererPercent: min(100.0, max(0.0, maxRenderUtil)),
            tilerPercent: min(100.0, max(0.0, maxTilerUtil)),
            memoryBytes: max(0, totalMemory)
        )
    }
}

