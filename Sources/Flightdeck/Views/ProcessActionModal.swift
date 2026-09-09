import SwiftUI
import AppKit

/// Cyberpunk confirmation & inspection modal for safe process termination,
/// app activation, and Finder inspection.
struct ProcessActionModal: View {
    let usage: ProcessUsage
    let onDismiss: () -> Void
    let onGracefulQuit: () -> Void
    let onForceKill: () -> Void

    @Environment(ProcessMonitor.self) private var monitor

    private var runningApp: NSRunningApplication? {
        NSRunningApplication(processIdentifier: usage.id)
    }

    private var appIcon: NSImage? {
        runningApp?.icon
    }

    private var energyColor: Color {
        if usage.cpuPercent < 15 { return Theme.good }
        if usage.cpuPercent < 50 { return Theme.warning }
        return Theme.critical
    }

    private var gaugeColor: Color {
        if usage.cpuPercent < 30 { return Theme.accent }
        if usage.cpuPercent < 70 { return Theme.accentSecondary }
        return Theme.critical
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    CockpitAudio.playPing()
                    onDismiss()
                }

            // Modal Card
            VStack(alignment: .leading, spacing: 16) {
                header
                processCard
                telemetryCard
                warningBanner
                redirectButtons
                Divider().background(Theme.hairline2)
                actionsFooter
            }
            .padding(22)
            .frame(width: 480)
            .background(Theme.panel.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.critical.opacity(0.4), lineWidth: 1.5)
            )
            .cornerBracket(color: Theme.critical)
            .shadow(color: Theme.critical.opacity(0.2), radius: 24)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.critical)

            Text("PROCESS CONTROLLER · PID \(usage.id)")
                .font(Theme.display(11)).tracking(0.8)
                .foregroundStyle(Theme.critical)

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
        }
    }

    private var processCard: some View {
        HStack(spacing: 14) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline2, lineWidth: 1))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.track)
                        .frame(width: 44, height: 44)
                    Image(systemName: "macwindow")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accentSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(usage.name)
                    .font(Theme.ui(16, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Text(usage.bundleId.isEmpty ? "Native Unix Executable" : usage.bundleId)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var telemetryCard: some View {
        HStack(spacing: 14) {
            // CPU Gauge
            HStack(spacing: 8) {
                RingGauge(
                    fraction: usage.cpuPercent / 100,
                    color: gaugeColor,
                    diameter: 32
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("CPU LOAD")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Text(String(format: "%.1f%%", usage.cpuPercent))
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(gaugeColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 28).background(Theme.hairline2)

            // Memory Footprint
            VStack(alignment: .leading, spacing: 1) {
                Text("RESIDENT MEMORY")
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(Theme.ink3)
                Text(ByteCountFormatter.string(fromByteCount: usage.memoryBytes, countStyle: .memory))
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.copilotColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 28).background(Theme.hairline2)

            // Energy Drain
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(energyColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ENERGY IMPACT")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Text(usage.cpuPercent < 15 ? "Low Drain" : (usage.cpuPercent < 50 ? "Moderate" : "High Drain"))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(energyColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.track.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.warning)
            Text("Terminating will halt all execution threads immediately. Make sure to save any unsaved work.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var redirectButtons: some View {
        HStack(spacing: 10) {
            // Activate Window
            Button {
                CockpitAudio.playPing()
                runningApp?.activate()
                onDismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                    Text("ACTIVATE APP")
                        .font(Theme.mono(9.5, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(runningApp == nil)

            // Reveal in Finder
            Button {
                CockpitAudio.playPing()
                if let url = runningApp?.bundleURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("REVEAL IN FINDER")
                        .font(Theme.mono(9.5, weight: .bold))
                }
                .foregroundStyle(Theme.accentSecondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.accentSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(runningApp?.bundleURL == nil)

            Spacer()
        }
    }

    private var actionsFooter: some View {
        HStack(spacing: 10) {
            Button("CANCEL") {
                CockpitAudio.playPing()
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(Theme.mono(10.5, weight: .semibold))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))

            Spacer()

            // Graceful Quit
            Button {
                CockpitAudio.playAlert()
                onGracefulQuit()
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eject.fill").font(.system(size: 9))
                    Text("QUIT GRACEFULLY")
                        .font(Theme.mono(10, weight: .bold))
                }
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Sends standard SIGTERM / Quit signal allowing app to save files")

            // Force Kill
            Button {
                CockpitAudio.playAlert()
                onForceKill()
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .black))
                    Text("FORCE KILL")
                        .font(Theme.mono(10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.critical, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Sends immediate POSIX SIGKILL -9")
        }
    }
}
