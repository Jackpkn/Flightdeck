import SwiftUI
import AppKit
import ServiceManagement

/// The menu bar popover — allows Flightdeck to sit running all day in the macOS menu bar
/// with instant quick-access telemetry, dev port management, cruft purging, and RAM flushing.
struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    let store: DashboardStore
    let usage: ClaudeUsageMonitor
    let watcher: ActivityWatcher
    let monitor: ProcessMonitor
    let portScanner: PortScanner
    let zombieDetector: ZombieDetector
    let devCleaner: DevCleaner

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var topApp: (name: String, seconds: TimeInterval, bundleId: String)? {
        watcher.timeByApp.first
    }

    private var devPorts: [ListeningPort] {
        portScanner.ports.filter(\.isDevPort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(watcher.isIdle ? Theme.ink3 : Theme.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: (watcher.isIdle ? Theme.ink3 : Theme.accent).opacity(0.8), radius: 3)
                Text("FLIGHTDECK").font(Theme.display(11)).tracking(1).foregroundStyle(Theme.ink2)
                Spacer()
                if watcher.isIdle {
                    Text("IDLE").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                } else {
                    Text("ACTIVE").font(Theme.mono(9, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().background(Theme.hairline)

            // System & Dev Telemetry (Fixed slots — zero layout jumping)
            VStack(spacing: 8) {
                row(label: "24H SPEND", value: Formatters.usd(store.last24hSpend), color: Theme.ink1)
                row(
                    label: "TODAY",
                    value: (store.todaySpendIsExact ? "" : "≤ ") + Formatters.usd(store.todaySpend),
                    color: Theme.warning
                )
                // The plan window closest to its ceiling — the limit that bites first.
                if let headline = usage.snapshot?.headline(now: usage.tick) {
                    row(
                        label: headline.label,
                        value: "\(headline.percent)% · \(Formatters.countdown(headline.timeUntilReset(now: usage.tick)))",
                        color: headline.effectiveSeverity == .critical ? Theme.critical
                             : headline.effectiveSeverity == .warning ? Theme.warning : Theme.good
                    )
                }
                row(
                    label: "SYSTEM CPU",
                    value: String(format: "%.0f%%", monitor.cpuHistory.last ?? 0),
                    color: Theme.accent
                )
                if let mem = monitor.memorySnapshot {
                    row(
                        label: "SYSTEM RAM",
                        value: "\(ByteCountFormatter.string(fromByteCount: mem.usedBytes, countStyle: .memory)) (\(String(format: "%.0f%%", mem.fraction * 100)))",
                        color: Theme.copilotColor
                    )
                }

                // Listening Ports row (never vanishes)
                if !devPorts.isEmpty {
                    let portsSummary = devPorts.prefix(3).map { ":\($0.port)" }.joined(separator: " ")
                    row(
                        label: "LISTENING PORTS",
                        value: "\(devPorts.count) (\(portsSummary))",
                        color: Theme.accent
                    )
                } else {
                    row(label: "LISTENING PORTS", value: "0 ACTIVE", color: Theme.ink3)
                }

                // Dev Build Cruft row (never vanishes)
                if devCleaner.totalCruftBytes > 0 {
                    let cruftStr = ByteCountFormatter.string(fromByteCount: devCleaner.totalCruftBytes, countStyle: .file)
                    row(label: "DEV BUILD CRUFT", value: cruftStr, color: Theme.warning)
                } else {
                    row(label: "DEV BUILD CRUFT", value: "0 B (CLEAN)", color: Theme.good)
                }

                // Orphan Runaways row (never vanishes)
                if !zombieDetector.orphans.isEmpty {
                    let wasted = ByteCountFormatter.string(fromByteCount: zombieDetector.totalWastedBytes, countStyle: .memory)
                    row(
                        label: "ORPHAN RUNAWAYS",
                        value: "\(zombieDetector.orphans.count) (\(wasted))",
                        color: Theme.critical
                    )
                } else {
                    row(label: "ORPHAN RUNAWAYS", value: "0 (CLEAN)", color: Theme.good)
                }

                if let topApp {
                    row(label: "TOP APP TODAY", value: "\(topApp.name) · \(Self.format(topApp.seconds))", color: Theme.ink2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider().background(Theme.hairline)

            // Quick Actions Cockpit Strip (Always present, fixed slots with dynamic status)
            VStack(spacing: 5) {
                // Orphan Purge Action
                if zombieDetector.isPurging {
                    quickActionButton(
                        title: "Purging Runaways...",
                        icon: "flame.fill",
                        color: Theme.critical,
                        isLoading: true,
                        isEnabled: false
                    ) {}
                } else if !zombieDetector.orphans.isEmpty {
                    quickActionButton(
                        title: "Purge All Orphans (\(zombieDetector.orphans.count) Runaway)",
                        icon: "flame.fill",
                        color: Theme.critical,
                        isEnabled: true
                    ) {
                        zombieDetector.purgeAllOrphans()
                    }
                } else {
                    quickActionButton(
                        title: "No Orphan Runaways",
                        icon: "checkmark.shield.fill",
                        color: Theme.good,
                        isEnabled: false
                    ) {}
                }

                // Dev Cruft Purge Action
                if devCleaner.isPurging {
                    quickActionButton(
                        title: "Purging Dev Cruft...",
                        icon: "trash.fill",
                        color: Theme.critical,
                        isLoading: true,
                        isEnabled: false
                    ) {}
                } else if devCleaner.totalCruftBytes > 0 {
                    let cruftStr = ByteCountFormatter.string(fromByteCount: devCleaner.totalCruftBytes, countStyle: .file)
                    quickActionButton(
                        title: "Purge All Dev Cruft (\(cruftStr))",
                        icon: "trash.fill",
                        color: Theme.critical,
                        isEnabled: true
                    ) {
                        devCleaner.purgeAll()
                    }
                } else {
                    quickActionButton(
                        title: "Dev Cruft Clean",
                        icon: "checkmark.circle.fill",
                        color: Theme.good,
                        isEnabled: false
                    ) {}
                }

                // Free Dev Ports Action
                if !devPorts.isEmpty {
                    quickActionButton(
                        title: "Free All Dev Ports (\(devPorts.count) Active)",
                        icon: "xmark.octagon.fill",
                        color: Theme.warning,
                        isEnabled: true
                    ) {
                        portScanner.freeAllDevPorts()
                    }
                } else {
                    quickActionButton(
                        title: "No Active Dev Ports",
                        icon: "network",
                        color: Theme.ink3,
                        isEnabled: false
                    ) {}
                }

                // RAM Flush Action
                quickActionButton(
                    title: "Flush Inactive RAM",
                    icon: "memorychip",
                    color: Theme.accent,
                    isEnabled: true
                ) {
                    devCleaner.flushRAM()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            Divider().background(Theme.hairline)

            // Navigation & App Lifecycle
            VStack(spacing: 2) {
                menuButton("Open Dashboard", icon: "macwindow", action: openDashboard)
                menuButton(
                    launchAtLogin ? "Disable Launch at Login" : "Launch at Login",
                    icon: launchAtLogin ? "checkmark.circle" : "circle",
                    action: toggleLaunchAtLogin
                )
                menuButton("Quit Flightdeck", icon: "power") { NSApp.terminate(nil) }
            }
            .padding(8)
        }
        .frame(width: 290)
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.panel)
        .foregroundStyle(Theme.ink1)
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(Theme.mono(9, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.ink3)
            Spacer()
            Text(value).font(Theme.mono(11, weight: .semibold)).foregroundStyle(color).lineLimit(1)
        }
    }

    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            CockpitAudio.playPing()
            action()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(isEnabled ? color : Theme.ink3)
                        .frame(width: 14)
                }
                Text(title)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(isEnabled ? Theme.ink1 : Theme.ink3)
                Spacer()
                if isEnabled && !isLoading {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(isEnabled ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(isEnabled ? 0.25 : 0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 14)
                Text(title).font(Theme.ui(12))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink2)
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("MenuBarPanel: launch-at-login toggle failed — \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "dashboard")
        NSApp.windows
            .first { $0.styleMask.contains(.titled) && $0.canBecomeKey }?
            .makeKeyAndOrderFront(nil)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
