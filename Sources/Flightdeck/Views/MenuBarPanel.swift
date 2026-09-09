import SwiftUI
import AppKit
import ServiceManagement

/// The menu bar popover — allows Flightdeck to sit running all day in the macOS menu bar
/// with instant quick-access telemetry, dev port management, cruft purging, and RAM flushing.
struct MenuBarPanel: View {
    let store: DashboardStore
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
                LiveDot(color: Theme.accent)
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

            // System & Dev Telemetry
            VStack(spacing: 8) {
                row(label: "24H SPEND", value: Formatters.usd(store.last24hSpend), color: Theme.ink1)
                row(label: "BURN RATE", value: Formatters.usd(store.burnRatePerMin) + "/min", color: Theme.warning)
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

                if !devPorts.isEmpty {
                    let portsSummary = devPorts.prefix(3).map { ":\($0.port)" }.joined(separator: " ")
                    row(
                        label: "LISTENING PORTS",
                        value: "\(devPorts.count) (\(portsSummary))",
                        color: Theme.accent
                    )
                }

                if devCleaner.totalCruftBytes > 0 {
                    let cruftStr = ByteCountFormatter.string(fromByteCount: devCleaner.totalCruftBytes, countStyle: .file)
                    row(
                        label: "DEV BUILD CRUFT",
                        value: cruftStr,
                        color: Theme.warning
                    )
                }

                if !zombieDetector.orphans.isEmpty {
                    let wasted = ByteCountFormatter.string(fromByteCount: zombieDetector.totalWastedBytes, countStyle: .memory)
                    row(
                        label: "ORPHAN RUNAWAYS",
                        value: "\(zombieDetector.orphans.count) (\(wasted))",
                        color: Theme.critical
                    )
                }

                if let topApp {
                    row(label: "TOP APP TODAY", value: "\(topApp.name) · \(Self.format(topApp.seconds))", color: Theme.ink2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            // Quick Actions Cockpit Strip
            if devCleaner.totalCruftBytes > 0 || !devPorts.isEmpty || !zombieDetector.orphans.isEmpty {
                Divider().background(Theme.hairline)

                VStack(spacing: 4) {
                    if devCleaner.totalCruftBytes > 0 {
                        let cruftStr = ByteCountFormatter.string(fromByteCount: devCleaner.totalCruftBytes, countStyle: .file)
                        quickActionButton(
                            title: "Purge All Dev Cruft (\(cruftStr))",
                            icon: "trash.fill",
                            color: Theme.critical
                        ) {
                            devCleaner.purgeAll()
                        }
                    }

                    if !devPorts.isEmpty {
                        quickActionButton(
                            title: "Free All Dev Ports (\(devPorts.count) Active)",
                            icon: "xmark.octagon.fill",
                            color: Theme.warning
                        ) {
                            portScanner.freeAllDevPorts()
                        }
                    }

                    if !zombieDetector.orphans.isEmpty {
                        quickActionButton(
                            title: "Purge All Orphans (\(zombieDetector.orphans.count) Runaway)",
                            icon: "flame.fill",
                            color: Theme.critical
                        ) {
                            zombieDetector.purgeAllOrphans()
                        }
                    }

                    quickActionButton(
                        title: "Flush Inactive RAM",
                        icon: "memorychip",
                        color: Theme.accent
                    ) {
                        devCleaner.flushRAM()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

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

    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            CockpitAudio.playPing()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(color.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.25), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
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
