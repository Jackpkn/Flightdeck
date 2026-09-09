import Darwin
import Foundation
import IOKit
import IOKit.ps

public enum VitalCategory: String, CaseIterable, Identifiable, Sendable {
    case battery = "BATTERY & POWER"
    case gpu = "GPU & METAL"
    case swap = "MEMORY & SWAP"
    case chip = "PROCESSOR & UPTIME"
    case network = "NETWORK & INTERFACE"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .battery: return "BATTERY"
        case .gpu: return "GPU"
        case .swap: return "RAM & SWAP"
        case .chip: return "PROCESSOR"
        case .network: return "NETWORK"
        }
    }

    public var icon: String {
        switch self {
        case .battery: return "bolt.batteryblock.fill"
        case .gpu: return "sparkles"
        case .swap: return "memorychip"
        case .chip: return "cpu"
        case .network: return "wifi"
        }
    }
}

public struct BatteryStatus: Equatable, Sendable {
    public let hasBattery: Bool
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let timeRemainingMinutes: Int?
    public let cycleCount: Int?
    public let healthPercent: Int?
    public let condition: String
    public let voltageMV: Int?
    public let amperageMA: Int?
    public let temperatureC: Double?
    public let designCapacityMAh: Int?
    public let nominalCapacityMAh: Int?
    public let adapterWatts: Int?

    public init(
        hasBattery: Bool,
        percent: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        timeRemainingMinutes: Int? = nil,
        cycleCount: Int? = nil,
        healthPercent: Int? = nil,
        condition: String = "Normal",
        voltageMV: Int? = nil,
        amperageMA: Int? = nil,
        temperatureC: Double? = nil,
        designCapacityMAh: Int? = nil,
        nominalCapacityMAh: Int? = nil,
        adapterWatts: Int? = nil
    ) {
        self.hasBattery = hasBattery
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeRemainingMinutes = timeRemainingMinutes
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.condition = condition
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
        self.temperatureC = temperatureC
        self.designCapacityMAh = designCapacityMAh
        self.nominalCapacityMAh = nominalCapacityMAh
        self.adapterWatts = adapterWatts
    }

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
    public let perfCores: Int
    public let efficiencyCores: Int
    public let uptimeString: String
    public let bootDate: Date?

    public init(
        name: String,
        cores: Int,
        perfCores: Int = 0,
        efficiencyCores: Int = 0,
        uptimeString: String = "0m",
        bootDate: Date? = nil
    ) {
        self.name = name
        self.cores = cores
        self.perfCores = perfCores
        self.efficiencyCores = efficiencyCores
        self.uptimeString = uptimeString
        self.bootDate = bootDate
    }
}

public struct NetworkVitals: Equatable, Sendable {
    public let interface: String
    public let ipAddress: String
    public let ipv6Address: String?

    public init(interface: String, ipAddress: String, ipv6Address: String? = nil) {
        self.interface = interface
        self.ipAddress = ipAddress
        self.ipv6Address = ipv6Address
    }
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

        let details = fetchSmartBatteryDetails()

        return BatteryStatus(
            hasBattery: true,
            percent: percent,
            isCharging: isCharging,
            isPluggedIn: isPlugged,
            timeRemainingMinutes: timeLeft,
            cycleCount: details.cycles,
            healthPercent: details.healthPercent,
            condition: details.condition,
            voltageMV: details.voltageMV,
            amperageMA: details.amperageMA,
            temperatureC: details.temperatureC,
            designCapacityMAh: details.designCap,
            nominalCapacityMAh: details.nominalCap,
            adapterWatts: details.adapterWatts
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

    private static func fetchSmartBatteryDetails() -> (
        cycles: Int?,
        healthPercent: Int?,
        condition: String,
        voltageMV: Int?,
        amperageMA: Int?,
        temperatureC: Double?,
        designCap: Int?,
        nominalCap: Int?,
        adapterWatts: Int?
    ) {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        let mainPort: mach_port_t = 0
        guard IOServiceGetMatchingServices(mainPort, matching, &iterator) == kIOReturnSuccess else {
            return (nil, nil, "Normal", nil, nil, nil, nil, nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return (nil, nil, "Normal", nil, nil, nil, nil, nil, nil) }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, "Normal", nil, nil, nil, nil, nil, nil)
        }

        let cycles = dict["CycleCount"] as? Int ?? (dict["CycleCount"] as? NSNumber)?.intValue
        let maxCap = dict["MaxCapacity"] as? Double ?? (dict["MaxCapacity"] as? NSNumber)?.doubleValue
        let designCap = dict["DesignCapacity"] as? Double ?? (dict["DesignCapacity"] as? NSNumber)?.doubleValue
        let nominalCap = dict["NominalChargeCapacity"] as? Double ?? (dict["NominalChargeCapacity"] as? NSNumber)?.doubleValue
        let voltage = dict["Voltage"] as? Int ?? (dict["Voltage"] as? NSNumber)?.intValue
        let amperage = dict["Amperage"] as? Int ?? (dict["Amperage"] as? NSNumber)?.intValue

        var tempC: Double? = nil
        if let rawT = dict["Temperature"] as? Double ?? (dict["Temperature"] as? NSNumber)?.doubleValue {
            tempC = rawT / 100.0 // AppleSmartBattery is in hundredths of °C
        }

        var watts: Int? = nil
        if let adapter = dict["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int {
            watts = w
        }

        var health: Int? = nil
        let bestCap = nominalCap ?? maxCap
        if let bestCap, let designCap, designCap > 0 {
            health = min(100, max(0, Int(round((bestCap / designCap) * 100))))
        }

        let condition = (dict["PermanentFailureStatus"] as? Int ?? 0) == 0 ? "Normal" : "Service"
        return (
            cycles,
            health,
            condition,
            voltage,
            amperage,
            tempC,
            designCap != nil ? Int(designCap!) : nil,
            nominalCap != nil ? Int(nominalCap!) : nil,
            watts
        )
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
        var pCores: Int32 = 0
        var pSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.logicalcpu", &pCores, &pSize, nil, 0)

        var eCores: Int32 = 0
        var eSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel1.logicalcpu", &eCores, &eSize, nil, 0)

        var bootTime = timeval()
        var bSize = MemoryLayout<timeval>.size
        var bootDate: Date? = nil
        if sysctlbyname("kern.boottime", &bootTime, &bSize, nil, 0) == 0 {
            bootDate = Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
        }

        let uptime = formatUptime(ProcessInfo.processInfo.systemUptime)

        return ChipInfo(
            name: name,
            cores: cores,
            perfCores: Int(pCores),
            efficiencyCores: Int(eCores),
            uptimeString: uptime,
            bootDate: bootDate
        )
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

        var ipv4: String?
        var ipv6: String?
        var primaryName = "en0"

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let name = String(cString: ptr.pointee.ifa_name)
            if !name.hasPrefix("lo") && ptr.pointee.ifa_addr != nil {
                let family = ptr.pointee.ifa_addr.pointee.sa_family
                if family == UInt8(AF_INET) && ipv4 == nil {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if ip != "127.0.0.1" && !ip.isEmpty {
                            ipv4 = ip
                            primaryName = name
                        }
                    }
                } else if family == UInt8(AF_INET6) && ipv6 == nil {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if !ip.hasPrefix("fe80:") && !ip.hasPrefix("::1") && !ip.isEmpty {
                            ipv6 = ip
                        }
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        let label = primaryName.hasPrefix("en0") ? "Wi-Fi (\(primaryName))" : primaryName
        return NetworkVitals(
            interface: label,
            ipAddress: ipv4 ?? "Online",
            ipv6Address: ipv6
        )
    }
}
