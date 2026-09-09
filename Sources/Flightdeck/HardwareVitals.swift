import Darwin
import Foundation
import IOKit
import IOKit.ps

public struct BatteryStatus: Equatable, Sendable {
    public let hasBattery: Bool
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let timeRemainingMinutes: Int?
    public let cycleCount: Int?
    public let healthPercent: Int?
    public let condition: String

    public var statusDescription: String {
        if !hasBattery { return "DESKTOP · AC POWER" }
        if isCharging {
            if let t = timeRemainingMinutes { return "⚡ CHARGING · \(t)m to full" }
            return "⚡ CHARGING"
        }
        if isPluggedIn { return "🔌 PLUGGED IN · FULL" }
        if let t = timeRemainingMinutes {
            let h = t / 60
            let m = t % 60
            return h > 0 ? "🔋 \(h)h \(String(format: "%02d", m))m left" : "🔋 \(m)m left"
        }
        return "🔋 ON BATTERY"
    }
}

public struct SwapStatus: Equatable, Sendable {
    public let usedBytes: Int64
    public let totalBytes: Int64

    public var isHeavy: Bool {
        usedBytes > 2_147_483_648 // > 2 GB
    }

    public var pressureLevel: String {
        if usedBytes == 0 { return "NOMINAL" }
        if usedBytes < 1_073_741_824 { return "LIGHT" }
        if usedBytes < 4_294_967_296 { return "MODERATE" }
        return "HEAVY"
    }
}

public struct ChipInfo: Equatable, Sendable {
    public let name: String
    public let cores: Int
    public let uptimeString: String
}

public struct NetworkVitals: Equatable, Sendable {
    public let interface: String
    public let ipAddress: String
}

/// Real-time native macOS hardware & system health sampler.
/// Gathers battery health, swap file memory, Apple Silicon chip identity,
/// system uptime, and local network status via native Darwin & IOKit APIs.
@Observable
public final class HardwareVitals: @unchecked Sendable {
    public private(set) var battery = BatteryStatus(
        hasBattery: false,
        percent: 100,
        isCharging: false,
        isPluggedIn: true,
        timeRemainingMinutes: nil,
        cycleCount: nil,
        healthPercent: nil,
        condition: "Normal"
    )

    public private(set) var swap = SwapStatus(usedBytes: 0, totalBytes: 0)
    public private(set) var chip = ChipInfo(name: "Apple Silicon", cores: 8, uptimeString: "0m")
    public private(set) var network = NetworkVitals(interface: "en0", ipAddress: "127.0.0.1")

    private var timer: Timer?

    public init() {}

    public func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        battery = Self.fetchBattery()
        swap = Self.fetchSwap()
        chip = Self.fetchChip()
        network = Self.fetchNetwork()
    }

    // MARK: - 1. Native Battery & Power Intelligence

    public static func fetchBattery() -> BatteryStatus {
        let (hasBatt, percent, isCharging, isPlugged, timeLeft) = fetchPowerSource()
        guard hasBatt else {
            return BatteryStatus(
                hasBattery: false,
                percent: 100,
                isCharging: false,
                isPluggedIn: true,
                timeRemainingMinutes: nil,
                cycleCount: nil,
                healthPercent: nil,
                condition: "Normal"
            )
        }

        let (cycles, health, cond) = fetchSmartBatteryDetails()

        return BatteryStatus(
            hasBattery: true,
            percent: percent,
            isCharging: isCharging,
            isPluggedIn: isPlugged,
            timeRemainingMinutes: timeLeft,
            cycleCount: cycles,
            healthPercent: health,
            condition: cond
        )
    }

    private static func fetchPowerSource() -> (hasBattery: Bool, percent: Int, isCharging: Bool, isPlugged: Bool, timeLeftMin: Int?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (false, 100, false, true, nil)
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let isPresent = desc[kIOPSIsPresentKey] as? Bool ?? true
            guard isPresent else { continue }

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100) : curCap

            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = desc[kIOPSPowerSourceStateKey] as? String
            let isPlugged = powerState == kIOPSACPowerValue

            var timeLeft: Int? = nil
            if isCharging {
                if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0 {
                    timeLeft = t
                }
            } else {
                if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 {
                    timeLeft = t
                }
            }

            return (true, min(100, max(0, percent)), isCharging, isPlugged, timeLeft)
        }

        return (false, 100, false, true, nil)
    }

    private static func fetchSmartBatteryDetails() -> (cycles: Int?, healthPercent: Int?, condition: String) {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        let mainPort: mach_port_t = 0
        guard IOServiceGetMatchingServices(mainPort, matching, &iterator) == kIOReturnSuccess else {
            return (nil, nil, "Normal")
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return (nil, nil, "Normal") }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, "Normal")
        }

        let cycles = dict["CycleCount"] as? Int ?? (dict["CycleCount"] as? NSNumber)?.intValue
        let maxCap = dict["MaxCapacity"] as? Double ?? (dict["MaxCapacity"] as? NSNumber)?.doubleValue
        let designCap = dict["DesignCapacity"] as? Double ?? (dict["DesignCapacity"] as? NSNumber)?.doubleValue

        var health: Int? = nil
        if let maxCap, let designCap, designCap > 0 {
            health = min(100, max(0, Int(round((maxCap / designCap) * 100))))
        }

        let condition = (dict["PermanentFailureStatus"] as? Int ?? 0) == 0 ? "Normal" : "Service"
        return (cycles, health, condition)
    }

    // MARK: - 2. Native macOS Memory Swap & Pressure

    public static func fetchSwap() -> SwapStatus {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            return SwapStatus(
                usedBytes: Int64(swap.xsu_used),
                totalBytes: Int64(swap.xsu_total)
            )
        }
        return SwapStatus(usedBytes: 0, totalBytes: 0)
    }

    // MARK: - 3. Apple Silicon Architecture & System Uptime

    public static func fetchChip() -> ChipInfo {
        var size = 0
        var name = "Apple Silicon"
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0) == 0 {
                let parsed = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
                if !parsed.isEmpty { name = parsed }
            }
        }

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let uptime = formatUptime(ProcessInfo.processInfo.systemUptime)

        return ChipInfo(name: name, cores: cores, uptimeString: uptime)
    }

    public static func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - 4. Local Network & Interface Status

    public static func fetchNetwork() -> NetworkVitals {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return NetworkVitals(interface: "en0", ipAddress: "Online") }
        defer { freeifaddrs(ifap) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let name = String(cString: ptr.pointee.ifa_name)
            if !name.hasPrefix("lo") && ptr.pointee.ifa_addr != nil {
                if ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if ip != "127.0.0.1" && !ip.isEmpty {
                            let label = name.hasPrefix("en0") ? "Wi-Fi (\(name))" : name
                            return NetworkVitals(interface: label, ipAddress: ip)
                        }
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }
        return NetworkVitals(interface: "Wi-Fi", ipAddress: "Online")
    }
}
