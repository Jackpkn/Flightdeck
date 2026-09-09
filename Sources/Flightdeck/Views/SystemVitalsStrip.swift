import SwiftUI

/// A hyper-dense, horizontal Cyberpunk instrument strip displaying native
/// macOS hardware vitals: Battery health & power, memory swap usage,
/// Apple Silicon chip identity, system uptime, and local network status.
struct SystemVitalsStrip: View {
    @Environment(HardwareVitals.self) private var vitals

    var body: some View {
        HStack(spacing: 12) {
            batteryCard
            swapCard
            chipCard
            networkCard
        }
        .frame(maxWidth: .infinity)
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

        return HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassPanel(accent: color)
        .cornerBracket(color: color)
        .help("Battery Condition: \(b.condition)")
    }

    // MARK: - 2. Swap Memory & Pressure Card

    private var swapCard: some View {
        let s = vitals.swap
        let isHeavy = s.isHeavy
        let color = isHeavy ? Theme.warning : Theme.copilotColor
        let usedFormatted = ByteCountFormatter.string(fromByteCount: s.usedBytes, countStyle: .memory)

        return HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassPanel(accent: color)
        .cornerBracket(color: color)
        .help("macOS Virtual Memory Swap File")
    }

    // MARK: - 3. Apple Silicon & Uptime Card

    private var chipCard: some View {
        let c = vitals.chip

        return HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .help("Hardware Processor and System Uptime")
    }

    // MARK: - 4. Local Network & Interface Card

    private var networkCard: some View {
        let n = vitals.network

        return HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassPanel(accent: Theme.accentSecondary)
        .cornerBracket(color: Theme.accentSecondary)
        .help("Local Network IP and Primary Interface")
    }
}
