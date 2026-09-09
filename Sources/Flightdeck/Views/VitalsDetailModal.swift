import SwiftUI
import AppKit

/// Comprehensive Cyberpunk diagnostic modal for system vitals.
/// Displays deep hardware metrics, live gauges, and native macOS shortcuts
/// for Battery, GPU, Swap/Memory, Processor, and Network.
struct VitalsDetailModal: View {
    @State var category: VitalCategory
    let onDismiss: () -> Void

    @Environment(HardwareVitals.self) private var vitals
    @Environment(ProcessMonitor.self) private var monitor
    @State private var copiedIP = false

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .onTapGesture {
                    CockpitAudio.playPing()
                    onDismiss()
                }

            // Modal Card
            VStack(alignment: .leading, spacing: 16) {
                header
                categoryPicker
                heroInstrument
                diagnosticsGrid
                Divider().background(Theme.hairline2)
                actionBar
            }
            .padding(22)
            .frame(width: 540)
            .background(Theme.panel.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
            )
            .cornerBracket(color: accentColor)
            .shadow(color: accentColor.opacity(0.22), radius: 26)
        }
    }

    private var accentColor: Color {
        switch category {
        case .battery:
            let b = vitals.battery
            if b.isCharging { return Theme.accent }
            if b.percent > 40 { return Theme.good }
            if b.percent > 20 { return Theme.warning }
            return Theme.critical
        case .gpu:
            return Theme.gpuColor
        case .swap:
            return vitals.swap.isHeavy ? Theme.warning : Theme.copilotColor
        case .chip:
            return Theme.accent
        case .network:
            return Theme.accentSecondary
        }
    }

    // MARK: - 1. Header & Navigation

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accentColor)

            Text("HARDWARE TELEMETRY · \(category.rawValue)")
                .font(Theme.display(11)).tracking(0.8)
                .foregroundStyle(accentColor)

            Spacer()

            Button {
                CockpitAudio.playPing()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(VitalCategory.allCases) { cat in
                let isSelected = category == cat
                Button {
                    CockpitAudio.playPing()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        category = cat
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon).font(.system(size: 9))
                        Text(cat.shortTitle).font(Theme.mono(9, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? Theme.ink1 : Theme.ink3)
                    .padding(.horizontal, 7.5).padding(.vertical, 3.5)
                    .background(isSelected ? Theme.track.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 2. Hero Instrument View

    @ViewBuilder
    private var heroInstrument: some View {
        switch category {
        case .battery:
            batteryHero
        case .gpu:
            gpuHero
        case .swap:
            swapHero
        case .chip:
            chipHero
        case .network:
            networkHero
        }
    }

    private var batteryHero: some View {
        let b = vitals.battery
        return HStack(spacing: 16) {
            RingGauge(
                fraction: Double(b.percent) / 100.0,
                color: accentColor,
                lineWidth: 5,
                diameter: 64,
                showTicks: true,
                centerLabel: "\(b.percent)%"
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(b.statusDescription)
                        .font(Theme.ui(14, weight: .bold))
                        .foregroundStyle(Theme.ink1)

                    Text(b.condition.uppercased())
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(b.condition == "Normal" ? Theme.good : Theme.critical)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background((b.condition == "Normal" ? Theme.good : Theme.critical).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }

                if b.hasBattery {
                    Text("Health: \(b.healthPercent ?? 100)% · Cycle Count: \(b.cycleCount ?? 0) of 1000")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text("Desktop Workstation · Operating on AC Wall Power")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var gpuHero: some View {
        let gpu = monitor.currentGPU
        return HStack(spacing: 16) {
            RingGauge(
                fraction: gpu.utilizationPercent / 100.0,
                color: Theme.gpuColor,
                lineWidth: 5,
                diameter: 64,
                showTicks: true,
                centerLabel: String(format: "%.0f%%", gpu.utilizationPercent)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("METAL ACCELERATOR")
                        .font(Theme.ui(14, weight: .bold))
                        .foregroundStyle(Theme.ink1)

                    if gpu.utilizationPercent >= 70 {
                        Text("HIGH LOAD")
                            .font(Theme.mono(8.5, weight: .bold))
                            .foregroundStyle(Theme.critical)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Theme.critical.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text("Allocated VRAM: \(ByteCountFormatter.string(fromByteCount: gpu.memoryBytes, countStyle: .memory)) · Unified Memory Architecture")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var swapHero: some View {
        let s = vitals.swap
        let mem = monitor.memorySnapshot
        let totalRAM = mem?.totalBytes ?? 16_000_000_000
        let usedRAM = mem?.usedBytes ?? 0
        let freeRAM = mem?.freeBytes ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PHYSICAL RAM: \(ByteCountFormatter.string(fromByteCount: usedRAM, countStyle: .memory)) USED OF \(ByteCountFormatter.string(fromByteCount: totalRAM, countStyle: .memory))")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                    Text("Free: \(ByteCountFormatter.string(fromByteCount: freeRAM, countStyle: .memory)) · Pressure: \(s.pressureLevel)")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Text("SWAP: \(ByteCountFormatter.string(fromByteCount: s.usedBytes, countStyle: .memory))")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(s.isHeavy ? Theme.warning : Theme.copilotColor)
            }

            // Proportional RAM distribution bar
            GeometryReader { geo in
                let w = geo.size.width
                let wiredFrac = mem != nil ? Double(mem!.wiredBytes) / Double(totalRAM) : 0.2
                let activeFrac = mem != nil ? Double(mem!.activeBytes) / Double(totalRAM) : 0.4
                let compFrac = mem != nil ? Double(mem!.compressedBytes) / Double(totalRAM) : 0.1
                let freeFrac = max(0, 1.0 - wiredFrac - activeFrac - compFrac)

                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.critical.opacity(0.85)).frame(width: max(2, w * wiredFrac))
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.85)).frame(width: max(2, w * activeFrac))
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accentSecondary.opacity(0.85)).frame(width: max(2, w * compFrac))
                    RoundedRectangle(cornerRadius: 2).fill(Theme.good.opacity(0.4)).frame(width: max(2, w * freeFrac))
                }
            }
            .frame(height: 12)

            HStack(spacing: 12) {
                legendItem(color: Theme.critical, label: "Wired")
                legendItem(color: Theme.accent, label: "Active")
                legendItem(color: Theme.accentSecondary, label: "Compressed")
                legendItem(color: Theme.good, label: "Free")
            }
        }
        .padding(14)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chipHero: some View {
        let c = vitals.chip
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(c.name)
                    .font(Theme.ui(15, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Text("\(c.cores) Cores Total (\(c.perfCores) Performance + \(c.efficiencyCores) Efficiency)")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text("Continuous System Uptime: \(c.uptimeString)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var networkHero: some View {
        let n = vitals.network
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accentSecondary.opacity(0.14)).frame(width: 64, height: 64)
                Image(systemName: "wifi")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(n.interface)
                    .font(Theme.ui(15, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Text("Local IP: \(n.ipAddress)")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.accentSecondary)

                if let v6 = n.ipv6Address {
                    Text("IPv6: \(v6)")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 3. Diagnostics Metrics Grid

    @ViewBuilder
    private var diagnosticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            switch category {
            case .battery:
                let b = vitals.battery
                metricCell(title: "BATTERY VOLTAGE", value: b.voltageMV != nil ? "\(b.voltageMV!) mV (\(String(format: "%.2f", Double(b.voltageMV!) / 1000.0)) V)" : "AC Powered")
                metricCell(title: "CURRENT FLOW", value: b.amperageMA != nil ? "\(b.amperageMA!) mA" : "Nominal")
                metricCell(title: "TEMPERATURE", value: b.temperatureC != nil ? String(format: "%.1f °C", b.temperatureC!) : "Nominal (25°C)")
                metricCell(title: "CHARGING ADAPTER", value: b.adapterWatts != nil ? "\(b.adapterWatts!)W USB-C PD" : (b.isPluggedIn ? "AC Wall Connected" : "On Battery"))
                metricCell(title: "DESIGN CAPACITY", value: b.designCapacityMAh != nil ? "\(b.designCapacityMAh!) mAh" : "Built-in")
                metricCell(title: "MAX CHARGE CAPACITY", value: b.nominalCapacityMAh != nil ? "\(b.nominalCapacityMAh!) mAh" : "100%")

            case .gpu:
                let gpu = monitor.currentGPU
                metricCell(title: "TOTAL GPU LOAD", value: String(format: "%.1f%%", gpu.utilizationPercent))
                metricCell(title: "3D / RENDERER LOAD", value: String(format: "%.1f%%", gpu.rendererPercent))
                metricCell(title: "TILER ACCELERATOR", value: String(format: "%.1f%%", gpu.tilerPercent))
                metricCell(title: "UNIFIED GRAPHICS MEMORY", value: ByteCountFormatter.string(fromByteCount: gpu.memoryBytes, countStyle: .memory))
                metricCell(title: "GRAPHICS PIPELINE", value: "Metal 3 / Apple Silicon")
                metricCell(title: "DISPLAY REFRESH", value: "\(NSScreen.main?.maximumFramesPerSecond ?? 60) Hz ProMotion")

            case .swap:
                let s = vitals.swap
                let mem = monitor.memorySnapshot
                metricCell(title: "SWAP FILE ALLOCATED", value: ByteCountFormatter.string(fromByteCount: s.totalBytes, countStyle: .memory))
                metricCell(title: "SWAP USED BY KERNEL", value: ByteCountFormatter.string(fromByteCount: s.usedBytes, countStyle: .memory))
                metricCell(title: "WIRED (NON-PAGEABLE)", value: mem != nil ? ByteCountFormatter.string(fromByteCount: mem!.wiredBytes, countStyle: .memory) : "0 GB")
                metricCell(title: "ACTIVE (IN MEMORY)", value: mem != nil ? ByteCountFormatter.string(fromByteCount: mem!.activeBytes, countStyle: .memory) : "0 GB")
                metricCell(title: "COMPRESSED RAM", value: mem != nil ? ByteCountFormatter.string(fromByteCount: mem!.compressedBytes, countStyle: .memory) : "0 GB")
                metricCell(title: "VIRTUAL SWAP PATH", value: "/var/vm/swapfile0")

            case .chip:
                let c = vitals.chip
                metricCell(title: "TOTAL CORES", value: "\(c.cores) Active Cores")
                metricCell(title: "PERFORMANCE CORES", value: "\(c.perfCores) High-Perf (Firestorm/Avalanche)")
                metricCell(title: "EFFICIENCY CORES", value: "\(c.efficiencyCores) Energy-Efficient (Icestorm/Blizzard)")
                metricCell(title: "SYSTEM ARCHITECTURE", value: "Apple Silicon arm64e")
                metricCell(title: "THERMAL STATE", value: thermalStateString(monitor.thermalState))
                metricCell(title: "BOOT TIMESTAMP", value: c.bootDate != nil ? c.bootDate!.formatted(date: .abbreviated, time: .shortened) : "System Boot")

            case .network:
                let n = vitals.network
                metricCell(title: "PRIMARY INTERFACE", value: n.interface)
                metricCell(title: "IPv4 ADDRESS", value: n.ipAddress)
                metricCell(title: "NETWORK SPEED (CURRENT)", value: String(format: "%.1f KB/s", monitor.currentNetKB))
                metricCell(title: "SUBNET / PROTOCOL", value: "TCP/IP v4 & v6 Active")
                metricCell(title: "HARDWARE ADAPTER", value: "Apple Integrated Broadcom/Wi-Fi")
                metricCell(title: "DNS STATUS", value: "macOS System Resolved")
            }
        }
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(Theme.ink1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.track.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 4. Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("DISMISS") {
                CockpitAudio.playPing()
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(Theme.mono(10.5, weight: .semibold))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))

            Spacer()

            switch category {
            case .battery:
                Button {
                    CockpitAudio.playPing()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") ?? URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                } label: {
                    actionButtonLabel(icon: "gearshape", title: "OPEN BATTERY SETTINGS")
                }
                .buttonStyle(.plain)

            case .gpu:
                Button {
                    CockpitAudio.playPing()
                    DevAppLauncher.openSystemActivityMonitor()
                } label: {
                    actionButtonLabel(icon: "arrow.up.forward.app", title: "GPU IN ACTIVITY MONITOR")
                }
                .buttonStyle(.plain)

            case .swap:
                Button {
                    CockpitAudio.playPing()
                    DevAppLauncher.openSystemActivityMonitor()
                } label: {
                    actionButtonLabel(icon: "memorychip", title: "MEMORY IN ACTIVITY MONITOR")
                }
                .buttonStyle(.plain)

            case .chip:
                Button {
                    CockpitAudio.playPing()
                    DevAppLauncher.openSystemActivityMonitor()
                } label: {
                    actionButtonLabel(icon: "cpu", title: "CPU IN ACTIVITY MONITOR")
                }
                .buttonStyle(.plain)

            case .network:
                Button {
                    CockpitAudio.playPing()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vitals.network.ipAddress, forType: .string)
                    copiedIP = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedIP = false }
                } label: {
                    actionButtonLabel(icon: copiedIP ? "checkmark" : "doc.on.doc", title: copiedIP ? "COPIED IP!" : "COPY LOCAL IP")
                }
                .buttonStyle(.plain)

                Button {
                    CockpitAudio.playPing()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") ?? URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                } label: {
                    actionButtonLabel(icon: "gearshape", title: "NETWORK SETTINGS")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9.5))
            Text(title).font(Theme.mono(10, weight: .bold))
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(Theme.mono(8.5)).foregroundStyle(Theme.ink3)
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal (Cool)"
        case .fair: return "Fair (Warm)"
        case .serious: return "Serious (Throttled)"
        case .critical: return "Critical (Extreme)"
        @unknown default: return "Unknown"
        }
    }
}
