import SwiftUI
import AppKit

struct ProcessMonitorPanel: View {
    @Binding var actionTarget: ProcessUsage?
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ActivityWatcher.self) private var activityWatcher
    @Environment(ZombieDetector.self) private var zombieDetector

    enum ProcessFilter: String, CaseIterable {
        case apps = "APPS"
        case energy = "ENERGY"
        case hogs = "HEAVY"
        case orphans = "ORPHANS"
        case all = "ALL"
    }

    @State private var filter: ProcessFilter = .apps
    @State private var bannerDismissed = false

    init(actionTarget: Binding<ProcessUsage?> = .constant(nil)) {
        self._actionTarget = actionTarget
    }

    private var hottest: ProcessUsage? {
        monitor.usages.max(by: { $0.cpuPercent < $1.cpuPercent })
    }

    private var filteredUsages: [ProcessUsage] {
        switch filter {
        case .apps:
            return monitor.usages.filter { !$0.bundleId.isEmpty }
        case .energy:
            let list = monitor.usages.filter { $0.energyImpact > 0.5 }
            return list.isEmpty ? monitor.usages : list.sorted { $0.energyImpact > $1.energyImpact }
        case .hogs:
            return monitor.usages.filter { $0.cpuPercent >= 10.0 || $0.memoryBytes >= 500_000_000 || $0.isNotResponding }
        case .orphans:
            return []
        case .all:
            return monitor.usages
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.accent)
                Text("PROCESS MONITOR").font(Theme.display(12, weight: .bold)).tracking(0.6).foregroundStyle(Theme.ink2)
                Spacer()
                ThermalChip(state: monitor.thermalState)

                // Quick Launcher: Open macOS Activity Monitor
                Button {
                    CockpitAudio.playPing()
                    DevAppLauncher.openSystemActivityMonitor()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9.5))
                        Text("SYSTEM MONITOR")
                            .font(Theme.mono(10.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 3.5)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Launch native macOS Activity Monitor")
            }

            // Process View Filters
            HStack(spacing: 5) {
                ForEach(ProcessFilter.allCases, id: \.self) { f in
                    Button {
                        CockpitAudio.playPing()
                        filter = f
                    } label: {
                        let badge = (f == .orphans && !zombieDetector.orphans.isEmpty) ? " (\(zombieDetector.orphans.count))" : ""
                        Text("\(f.rawValue)\(badge)")
                            .font(Theme.mono(10, weight: filter == f ? .bold : .medium))
                            .foregroundStyle(filter == f ? (f == .orphans && !zombieDetector.orphans.isEmpty ? Theme.warning : Theme.ink1) : (f == .orphans && !zombieDetector.orphans.isEmpty ? Theme.warning.opacity(0.85) : Theme.ink3))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(filter == f ? Theme.track.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 3.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .stroke(filter == f ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if filter == .orphans {
                    Text("\(zombieDetector.orphans.count) orphans")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.warning)
                } else {
                    Text("\(filteredUsages.count) of \(monitor.usages.count)")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                }
            }

            // Orphan Alert Banner
            if !zombieDetector.orphans.isEmpty && !bannerDismissed && filter != .orphans {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.warning)

                    let wasted = ByteCountFormatter.string(fromByteCount: zombieDetector.totalWastedBytes, countStyle: .memory)
                    Text("\(zombieDetector.orphans.count) ORPHANS DETECTED · \(wasted)")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(Theme.warning)

                    Spacer()

                    Button {
                        CockpitAudio.playPing()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filter = .orphans
                        }
                    } label: {
                        Text("INSPECT")
                            .font(Theme.mono(8, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        CockpitAudio.playPing()
                        zombieDetector.purgeAllOrphans()
                    } label: {
                        HStack(spacing: 3) {
                            if zombieDetector.isPurging {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 8, height: 8)
                                Text("PURGING...").font(Theme.mono(8, weight: .bold))
                            } else {
                                Image(systemName: "flame.fill").font(.system(size: 7.5))
                                Text("PURGE").font(Theme.mono(8, weight: .bold))
                            }
                        }
                        .foregroundStyle(Theme.critical)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.critical.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(zombieDetector.isPurging)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            bannerDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss alert banner")
                }
                .padding(.horizontal, 7).padding(.vertical, 3.5)
                .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.warning.opacity(0.25), lineWidth: 0.8))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if filter == .orphans {
                if zombieDetector.orphans.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.good)
                        Text("NO ORPHAN PROCESSES")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.ink1)
                        Text("All running developer tools have active controlling terminals.")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.ink3)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack {
                        let wasted = ByteCountFormatter.string(fromByteCount: zombieDetector.totalWastedBytes, countStyle: .memory)
                        Text("TOTAL WASTED: \(wasted)")
                            .font(Theme.mono(8.5, weight: .bold))
                            .foregroundStyle(Theme.warning)
                        Spacer()
                        Button {
                            CockpitAudio.playPing()
                            zombieDetector.purgeAllOrphans()
                        } label: {
                            HStack(spacing: 4) {
                                if zombieDetector.isPurging {
                                    ProgressView()
                                        .scaleEffect(0.55)
                                        .frame(width: 10, height: 10)
                                    Text("PURGING...").font(Theme.mono(8.5, weight: .bold))
                                } else {
                                    Image(systemName: "flame.fill").font(.system(size: 8))
                                    Text("PURGE ALL ORPHANS").font(Theme.mono(8.5, weight: .bold))
                                }
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8).padding(.vertical, 3.5)
                            .background(Theme.critical.opacity(zombieDetector.isPurging ? 0.5 : 0.85), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(zombieDetector.isPurging)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(zombieDetector.orphans) { orphan in
                                OrphanRow(orphan: orphan) {
                                    zombieDetector.killOrphan(pid: orphan.pid)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
                }
            } else if monitor.usages.isEmpty {
                VStack(spacing: 8) {
                    SkeletonBar(height: 50)
                    SkeletonBar(height: 16)
                    SkeletonBar(height: 16)
                }
                .padding(.vertical, 10)
            } else {
                if let hottest, filter != .apps || !hottest.bundleId.isEmpty {
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

                let maxMemory = filteredUsages.map(\.memoryBytes).max() ?? 1
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredUsages) { row in
                            let killable = row.id != ProcessInfo.processInfo.processIdentifier
                            ProcessRow(
                                usage: row,
                                memoryFraction: Double(row.memoryBytes) / Double(maxMemory),
                                onKill: killable ? {
                                    if NSEvent.modifierFlags.contains(.option) {
                                        CockpitAudio.playAlert()
                                        monitor.killProcess(pid: row.id, bundleId: row.bundleId)
                                    } else {
                                        CockpitAudio.playPing()
                                        actionTarget = row
                                    }
                                } : nil
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
    }

    private func gaugeColor(for percent: Double) -> Color {
        if percent < 70 { return Theme.accent }
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
            Image(systemName: "thermometer.medium").font(.system(size: 10))
            Text(label).font(Theme.mono(10.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(color.opacity(0.14), in: Capsule())
        .help("System thermal pressure")
    }
}

private struct ProcessRow: View {
    let usage: ProcessUsage
    let memoryFraction: Double
    let onKill: (() -> Void)?

    private var energyColor: Color {
        if usage.cpuPercent < 15 { return Theme.good }
        if usage.cpuPercent < 50 { return Theme.warning }
        return Theme.critical
    }

    private var rowGaugeColor: Color {
        if usage.cpuPercent < 70 { return Theme.accent }
        return Theme.critical
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(usage.name)
                        .font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink1)
                        .lineLimit(1)
                    if usage.isNotResponding {
                        Text("HUNG")
                            .font(Theme.mono(8.5, weight: .black))
                            .foregroundStyle(Theme.critical)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.critical.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                    }
                }
                Text("PID·\(usage.id)")
                    .font(Theme.mono(10)).foregroundStyle(Theme.ink3.opacity(0.6))
            }
            .frame(width: 130, alignment: .leading)

            // Dynamic load gauge + CPU % + Energy score
            HStack(spacing: 4) {
                RingGauge(
                    fraction: usage.cpuPercent / 100,
                    color: usage.isNotResponding ? Theme.critical : rowGaugeColor,
                    diameter: 20
                )
                Text(String(format: "%.0f%%", usage.cpuPercent))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.ink2)

                // Energy impact badge
                if usage.energyImpact > 0.5 {
                    HStack(spacing: 1.5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text(String(format: "%.0f", usage.energyImpact))
                            .font(Theme.mono(9, weight: .bold))
                    }
                    .foregroundStyle(energyColor)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(energyColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 2))
                    .help("Energy Impact score: \(String(format: "%.1f", usage.energyImpact))")
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(energyColor)
                        .help("Low Energy Drain")
                }
            }
            .frame(width: 86, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: max(4, geo.size.width * memoryFraction))
                }
            }
            .frame(height: 14)

            Text(Self.memoryString(usage.memoryBytes))
                .font(Theme.mono(11.5)).foregroundStyle(Theme.ink1)
                .frame(width: 66, alignment: .trailing)

            // 1-Click Kill Button (opens safe controller dialog; ⌥-click for instant force kill)
            if let onKill {
                Button {
                    onKill()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .black))
                        Text("KILL").font(Theme.mono(10, weight: .bold))
                    }
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 5.5).padding(.vertical, 2.5)
                    .background(Theme.critical.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Inspect & terminate \(usage.name) (⌥-click for instant force kill)")
            } else {
                Color.clear.frame(width: 38, height: 12)
            }
        }
    }

    private static func memoryString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

private struct OrphanRow: View {
    let orphan: OrphanProcess
    let onKill: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(orphan.name)
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.ink1)

                    Text("PID \(orphan.pid)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Theme.track.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))

                    Text(orphan.isZombie ? "ZOMBIE" : "ORPHAN")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(orphan.isZombie ? Theme.critical : Theme.warning)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background((orphan.isZombie ? Theme.critical : Theme.warning).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }

                Text(orphan.path)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: orphan.memoryBytes, countStyle: .memory))
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(Theme.ink2)

            Button {
                CockpitAudio.playPing()
                onKill()
            } label: {
                Text("KILL")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : Theme.critical)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(isHovered ? Theme.critical : Theme.critical.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.critical.opacity(0.4), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help("Terminate orphaned PID \(orphan.pid)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isHovered ? Theme.track.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline2, lineWidth: 0.5))
        .onHover { isHovered = $0 }
    }
}
