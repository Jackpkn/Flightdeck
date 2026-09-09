import SwiftUI
import AppKit
import ServiceManagement

/// The menu bar popover — the whole point of it is that Flightdeck can sit
/// running all day (so tracking is continuous and the SQLite history is
/// unbroken) without a dashboard window taking up a screen.
///
/// Observables are passed in directly rather than through the environment:
/// scene-level environment propagation into a MenuBarExtra label is fiddly,
/// and @Observable tracking works the same either way.
struct MenuBarPanel: View {
    let store: DashboardStore
    let watcher: ActivityWatcher
    let monitor: ProcessMonitor

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var topApp: (name: String, seconds: TimeInterval, bundleId: String)? {
        watcher.timeByApp.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.accent)
                Text("FLIGHTDECK").font(Theme.display(11)).tracking(1).foregroundStyle(Theme.ink2)
                Spacer()
                if watcher.isIdle {
                    Text("IDLE").font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().background(Theme.hairline)

            VStack(spacing: 9) {
                row(label: "24H SPEND", value: Formatters.usd(store.last24hSpend), color: Theme.ink1)
                row(label: "BURN RATE", value: Formatters.usd(store.burnRatePerMin) + "/min", color: Theme.warning)
                row(label: "ACTIVE SESSIONS", value: "\(store.activeCount)", color: Theme.ink1)
                row(
                    label: "SYSTEM CPU",
                    value: String(format: "%.0f%%", monitor.cpuHistory.last ?? 0),
                    color: Theme.accent
                )
                if let topApp {
                    row(label: "TOP APP TODAY", value: "\(topApp.name) · \(Self.format(topApp.seconds))", color: Theme.copilotColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Theme.hairline)

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
        .frame(width: 268)
        .background(Theme.panel)
        .foregroundStyle(Theme.ink1)
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(Theme.mono(9.5, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.ink3)
            Spacer()
            Text(value).font(Theme.mono(11.5, weight: .semibold)).foregroundStyle(color).lineLimit(1)
        }
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 14)
                Text(title).font(Theme.ui(12.5))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink2)
    }

    /// Continuous tracking only works if the app is actually running, so this
    /// belongs next to the persistence work. Registration can legitimately fail
    /// for an ad-hoc-signed debug build — the state is re-read either way
    /// rather than assumed.
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

    /// The menu bar popover is itself an NSWindow, so pick the titled one.
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
