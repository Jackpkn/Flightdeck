import SwiftUI
import AppKit

struct ProcessMonitorPanel: View {
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ActivityWatcher.self) private var activityWatcher

    private var hottest: ProcessUsage? {
        monitor.usages.max(by: { $0.cpuPercent < $1.cpuPercent })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.warning)
                Text("RESOURCE USAGE · LIVE").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                ThermalChip(state: monitor.thermalState)
                Text("\(monitor.usages.count) apps").font(Theme.mono(11)).foregroundStyle(Theme.ink3)
            }

            if monitor.usages.isEmpty {
                VStack(spacing: 8) {
                    SkeletonBar(height: 50)
                    SkeletonBar(height: 16)
                    SkeletonBar(height: 16)
                }
                .padding(.vertical, 10)
            } else {
                if let hottest {
                    let peakColor = gaugeColor(for: hottest.cpuPercent)
                    HStack(spacing: 16) {
                        RingGauge(
                            fraction: hottest.cpuPercent / 100,
                            color: peakColor,
                            lineWidth: 4,
                            diameter: 72,
                            showTicks: true,
                            centerLabel: String(format: "%.0f", hottest.cpuPercent)
                        )
                        .shadow(color: hottest.cpuPercent >= 70 ? Theme.critical.opacity(0.6) : Color.clear, radius: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text("PEAK CPU").font(Theme.mono(10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.ink3)
                                if hottest.cpuPercent >= 70 {
                                    Text("HIGH LOAD")
                                        .font(Theme.mono(8, weight: .bold))
                                        .foregroundStyle(Theme.critical)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Theme.critical.opacity(0.18), in: RoundedRectangle(cornerRadius: 2.5))
                                }
                            }
                            Text(hottest.name).font(Theme.ui(14, weight: .semibold)).foregroundStyle(Theme.ink1)
                            Text("PID·\(hottest.id)").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)
                }

                let maxMemory = monitor.usages.map(\.memoryBytes).max() ?? 1
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(monitor.usages) { row in
                            let killable = row.id != ProcessInfo.processInfo.processIdentifier
                            ProcessRow(
                                usage: row,
                                memoryFraction: Double(row.memoryBytes) / Double(maxMemory),
                                onQuit: killable ? { monitor.killProcess(pid: row.id, bundleId: row.bundleId) } : nil,
                                onForceQuit: killable ? { monitor.killProcess(pid: row.id, bundleId: row.bundleId) } : nil
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.warning)
        .cornerBracket(color: Theme.warning)
    }

    private func gaugeColor(for percent: Double) -> Color {
        if percent < 30 { return Theme.accent }
        if percent < 70 { return Theme.accentSecondary }
        return Theme.critical
    }
}

private struct ThermalChip: View {
    let state: ProcessInfo.ThermalState

    private var label: String {
        switch state {
        case .nominal: return "NOMINAL"
        case .fair: return "FAIR"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        @unknown default: return "UNKNOWN"
        }
    }

    private var color: Color {
        switch state {
        case .nominal: return Theme.good
        case .fair: return Theme.warning
        case .serious, .critical: return Theme.critical
        @unknown default: return Theme.ink3
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "thermometer.medium").font(.system(size: 9))
            Text(label).font(Theme.mono(9.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .help("System thermal pressure")
    }
}

private struct ProcessRow: View {
    let usage: ProcessUsage
    let memoryFraction: Double
    let onQuit: (() -> Void)?
    let onForceQuit: (() -> Void)?

    private var energyColor: Color {
        if usage.cpuPercent < 15 { return Theme.good }
        if usage.cpuPercent < 50 { return Theme.warning }
        return Theme.critical
    }

    private var rowGaugeColor: Color {
        if usage.cpuPercent < 30 { return Theme.accent }
        if usage.cpuPercent < 70 { return Theme.accentSecondary }
        return Theme.critical
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(usage.name)
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.ink1)
                    .lineLimit(1)
                Text("PID·\(usage.id)")
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3.opacity(0.6))
            }
            .frame(width: 126, alignment: .leading)

            // Dynamic load gauge + CPU % + Energy leaf
            HStack(spacing: 4) {
                RingGauge(
                    fraction: usage.cpuPercent / 100,
                    color: rowGaugeColor,
                    diameter: 20
                )
                Text(String(format: "%.0f%%", usage.cpuPercent))
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.ink2)

                // Energy impact leaf
                Image(systemName: "leaf.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(energyColor)
                    .help(usage.cpuPercent < 15 ? "Low Energy Drain" : (usage.cpuPercent < 50 ? "Moderate Energy Drain" : "High Energy Drain"))
            }
            .frame(width: 74, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accentSecondary.opacity(0.8))
                        .frame(width: max(4, geo.size.width * memoryFraction))
                }
            }
            .frame(height: 14)

            Text(Self.memoryString(usage.memoryBytes))
                .font(Theme.mono(11)).foregroundStyle(Theme.ink1)
                .frame(width: 62, alignment: .trailing)

            // 1-Click Kill Button
            if let onQuit {
                Button {
                    CockpitAudio.playAlert()
                    onForceQuit?() ?? onQuit()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark").font(.system(size: 7.5, weight: .black))
                        Text("KILL").font(Theme.mono(8, weight: .bold))
                    }
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 4.5).padding(.vertical, 2)
                    .background(Theme.critical.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Force terminate \(usage.name)")
            } else {
                Color.clear.frame(width: 36, height: 12)
            }
        }
    }

    private static func memoryString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
