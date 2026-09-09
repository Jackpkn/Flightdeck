import SwiftUI

/// A hyper-dense, horizontal Cyberpunk instrument strip displaying native
/// macOS hardware vitals: Battery health & power, memory swap usage,
/// Apple Silicon chip identity, system uptime, and local network status.
/// Each card is interactive and opens a deep diagnostic modal on click.
struct SystemVitalsStrip: View {
    @Binding var selectedCategory: VitalCategory?
    @Environment(HardwareVitals.self) private var vitals
    @Environment(ProcessMonitor.self) private var monitor
    @State private var hoveredCategory: VitalCategory?

    init(selectedCategory: Binding<VitalCategory?> = .constant(nil)) {
        self._selectedCategory = selectedCategory
    }

    var body: some View {
        HStack(spacing: 12) {
            batteryCard
            gpuCard
            swapCard
            chipCard
            networkCard
        }
        .frame(maxWidth: .infinity)
    }

    private func interactiveCard<Content: View>(
        category: VitalCategory,
        accent: Color,
        helpText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isHovered = hoveredCategory == category
        return Button {
            CockpitAudio.playPing()
            selectedCategory = category
        } label: {
            content()
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .glassPanel(accent: isHovered ? accent : accent.opacity(0.6))
                .cornerBracket(color: isHovered ? accent : accent.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? accent.opacity(0.5) : Color.clear, lineWidth: 1.2)
                )
                .shadow(color: isHovered ? accent.opacity(0.25) : Color.clear, radius: 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredCategory = isHovered ? category : nil
        }
        .help("\(helpText) — Click for deep diagnostics")
    }

    // MARK: - 1. Battery & Power Health Card

    private var batteryCard: some View {
        let b = vitals.battery
        let color: Color = {
            if b.isCharging { return Theme.accent }
            if b.percent > 40 { return Theme.good }
            if b.percent > 20 { return Theme.warning }
            return Theme.critical
        }()

        let icon: String = {
            if !b.hasBattery { return "powerplug.fill" }
            if b.isCharging { return "bolt.batteryblock.fill" }
            if b.percent >= 85 { return "battery.100" }
            if b.percent >= 60 { return "battery.75" }
            if b.percent >= 35 { return "battery.50" }
            if b.percent >= 15 { return "battery.25" }
            return "battery.0"
        }()

        return interactiveCard(
            category: .battery,
            accent: color,
            helpText: "Battery Condition: \(b.condition)"
        ) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(b.hasBattery ? "\(b.percent)%" : "AC POWER")
                            .font(Theme.mono(12.5, weight: .bold))
                            .foregroundStyle(Theme.ink1)

                        Text(b.statusDescription)
                            .font(Theme.mono(9, weight: .semibold))
                            .foregroundStyle(color)
                            .lineLimit(1)
                    }

                    if b.hasBattery {
                        HStack(spacing: 4) {
                            if let h = b.healthPercent {
                                Text("\(h)% Health")
                                    .font(Theme.mono(9.5))
                                    .foregroundStyle(Theme.ink2)
                            }
                            if let c = b.cycleCount {
                                Text("· \(c) cycles")
                                    .font(Theme.mono(9.5))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                    } else {
                        Text("DESKTOP WORKSTATION")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.ink3)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
            }
        }
    }

    // MARK: - 2. Hardware GPU & VRAM Card

    private var gpuCard: some View {
        let gpu = monitor.currentGPU
        let util = gpu.utilizationPercent
        let color: Color = {
            if util < 40 { return Theme.gpuColor }
            if util < 75 { return Theme.warning }
            return Theme.critical
        }()

        let vramFormatted = ByteCountFormatter.string(fromByteCount: gpu.memoryBytes, countStyle: .memory)

        return interactiveCard(
            category: .gpu,
            accent: color,
            helpText: "Apple Silicon / Metal GPU Utilization"
        ) {
            HStack(spacing: 10) {
                RingGauge(
                    fraction: util / 100.0,
                    color: color,
                    diameter: 28
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(String(format: "GPU %.0f%%", util))
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.ink1)

                        if util >= 70 {
                            Text("HEAVY")
                                .font(Theme.mono(8, weight: .bold))
                                .foregroundStyle(Theme.critical)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.critical.opacity(0.18), in: RoundedRectangle(cornerRadius: 2.5))
                        }
                    }

                    Text(gpu.memoryBytes > 0 ? "VRAM: \(vramFormatted)" : "METAL ENGINE ACTIVE")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
            }
        }
    }

    // MARK: - 3. Swap Memory & Pressure Card

    private var swapCard: some View {
        let s = vitals.swap
        let isHeavy = s.isHeavy
        let color = isHeavy ? Theme.warning : Theme.copilotColor
        let usedFormatted = ByteCountFormatter.string(fromByteCount: s.usedBytes, countStyle: .memory)

        return interactiveCard(
            category: .swap,
            accent: color,
            helpText: "macOS Virtual Memory Swap File"
        ) {
            HStack(spacing: 10) {
                Image(systemName: "memorychip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("SWAP: \(usedFormatted)")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.ink1)

                        Text(s.pressureLevel)
                            .font(Theme.mono(8, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 2.5))
                    }

                    Text(s.usedBytes == 0 ? "ZERO DISK THRASHING" : "\(ByteCountFormatter.string(fromByteCount: s.totalBytes, countStyle: .memory)) allocated")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
            }
        }
    }

    // MARK: - 4. Apple Silicon & Uptime Card

    private var chipCard: some View {
        let c = vitals.chip

        return interactiveCard(
            category: .chip,
            accent: Theme.accent,
            helpText: "Hardware Processor and System Uptime"
        ) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(c.name)
                            .font(Theme.ui(12.5, weight: .semibold))
                            .foregroundStyle(Theme.ink1)
                            .lineLimit(1)

                        Text("· \(c.cores)C")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.accent)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 8))
                        Text("UPTIME: \(c.uptimeString)")
                            .font(Theme.mono(9.5))
                    }
                    .foregroundStyle(Theme.ink3)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
            }
        }
    }

    // MARK: - 5. Local Network & Interface Card

    private var networkCard: some View {
        let n = vitals.network

        return interactiveCard(
            category: .network,
            accent: Theme.accentSecondary,
            helpText: "Local Network IP and Primary Interface"
        ) {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(n.interface)
                        .font(Theme.ui(12.5, weight: .semibold))
                        .foregroundStyle(Theme.ink1)
                        .lineLimit(1)

                    Text(n.ipAddress)
                        .font(Theme.mono(9.5, weight: .medium))
                        .foregroundStyle(Theme.accentSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
            }
        }
    }
}
