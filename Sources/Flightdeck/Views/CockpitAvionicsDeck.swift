import SwiftUI

/// Cockpit Avionics Flight Deck — symmetrically aligned Primary Flight Display (PFD),
/// Threat Radar, and Engine Instruments cluster embedded directly on the Overview page.
///
/// Layout geometry:
/// - Bay 1 (Left): Threat Radar PPI Display (zombie bogeys & listening dev ports)
/// - Bay 2 (Center): Aviation "Basic T" Primary Flight Display (Speed Tape + Horizon + Altitude Tape)
/// - Bay 3 (Right): 2x2 Engine Tachometers (CPU, GPU, RAM, Disk I/O)
///
/// All 3 bays share an identical 260pt height for a clean, intentional baseline.
struct CockpitAvionicsDeck: View {
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ZombieDetector.self) private var zombies
    @Environment(PortScanner.self) private var ports

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                // Cockpit Deck Header
                deckHeader(date: timeline.date)

                // 3-Bay Symmetrical Instrument Deck (Height: 260pt each)
                HStack(alignment: .top, spacing: 14) {
                    // Bay 1: Threat Radar
                    radarBay(date: timeline.date)
                        .frame(maxWidth: .infinity)

                    // Bay 2: Primary Flight Display (PFD)
                    pfdBay(date: timeline.date)
                        .frame(width: 390)

                    // Bay 3: Engine Tachometers
                    engineBay(date: timeline.date)
                        .frame(maxWidth: .infinity)
                }

                // Cockpit Deck Telemetry & Safety Status Bar
                deckStatusBar(date: timeline.date)
            }
            .padding(16)
            .glassPanel(cornerRadius: 14, accent: Theme.accent)
            .cornerBracket(color: Theme.accent)
        }
    }

    // MARK: - Deck Header

    private func deckHeader(date: Date) -> some View {
        HStack(spacing: 10) {
            LiveDot(color: Theme.accent)

            Text("COCKPIT AVIONICS HUD")
                .font(Theme.display(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)

            Text("·")
                .foregroundStyle(Theme.ink3)

            Text("PRIMARY FLIGHT DISPLAY & RADAR")
                .font(Theme.mono(9, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.ink3)

            Spacer()

            // Telemetry badges
            telemetryPills
        }
    }

    private var telemetryPills: some View {
        let cpu = monitor.cpuHistory.last ?? 0
        let gpu = monitor.currentGPU.utilizationPercent
        let bank = max(-30, min(30, (cpu - gpu) * 0.3))
        let pitch = min(100, (cpu + gpu) / 2) * 0.4

        return HStack(spacing: 8) {
            pillItem(label: "PITCH", value: String(format: "%+.1f°", -pitch))
            pillItem(label: "ROLL", value: String(format: "%+.1f°", bank))
            pillItem(label: "AIRSPEED", value: formatSpeed(monitor.currentNetKB))
            pillItem(label: "RADAR", value: "SWEEPING", color: Theme.accent)
        }
    }

    private func pillItem(label: String, value: String, color: Color = Theme.ink2) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.mono(7.5))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline, lineWidth: 0.5))
    }

    // MARK: - Bay 1: Threat Radar

    private func radarBay(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            bayTitle(
                title: "THREAT RADAR",
                subtitle: "ORPHAN BOGEYS & PORT PERIMETER",
                icon: "dot.radiowaves.left.and.right",
                color: Theme.accent
            )

            ZStack {
                RadarSweepView(date: date)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .glassPanel(cornerRadius: 10, accent: Theme.accent)
            .cornerBracket(color: Theme.accent)
        }
    }

    // MARK: - Bay 2: Primary Flight Display (PFD)

    private func pfdBay(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            bayTitle(
                title: "PRIMARY FLIGHT DISPLAY (PFD)",
                subtitle: "AIRSPEED · HORIZON · ALTITUDE",
                icon: "airplane",
                color: Theme.accent
            )

            HStack(spacing: 0) {
                // Airspeed Tape — Left
                SpeedTapeView(date: date)
                    .frame(width: 70, height: 220)

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 220)

                // Artificial Horizon / Attitude Director — Center
                ArtificialHorizonView(date: date)
                    .frame(width: 248, height: 220)

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 220)

                // Altitude Tape — Right
                AltitudeTapeView(date: date)
                    .frame(width: 70, height: 220)
            }
            .frame(width: 390, height: 220)
            .glassPanel(cornerRadius: 10, accent: Theme.accent)
            .cornerBracket(color: Theme.accent)
        }
    }

    // MARK: - Bay 3: Engine Tachometers (EIS)

    private func engineBay(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            bayTitle(
                title: "ENGINE INSTRUMENTS",
                subtitle: "CPU · GPU · RAM · DISK THRUST",
                icon: "gauge.with.dots.needle.67percent",
                color: Theme.warning
            )

            ZStack {
                EngineGaugesView(date: date, layout: .grid2x2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .glassPanel(cornerRadius: 10, accent: Theme.warning)
            .cornerBracket(color: Theme.warning)
        }
    }

    // MARK: - Bay Title Helper

    private func bayTitle(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.mono(8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ink1)

                Text(subtitle)
                    .font(Theme.mono(6.8))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer()
        }
        .frame(height: 26)
    }

    // MARK: - Status Bar

    private func deckStatusBar(date: Date) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.good)
                Text("SAFETY: FILEGUARD ARMED (SIP & CODE PROTECTED)")
                    .font(Theme.mono(8, weight: .semibold))
                    .foregroundStyle(Theme.good)
            }

            Spacer()

            statusItem("FPS", value: "60", color: Theme.good)
            statusItem("THERMAL", value: thermalLabel, color: thermalColor)
            statusItem("UPTIME", value: uptimeShort, color: Theme.ink2)

            Text(date.formatted(date: .omitted, time: .standard))
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusItem(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.mono(7))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(8.5, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var thermalLabel: String {
        switch monitor.thermalState {
        case .nominal: return "NOM"
        case .fair: return "FAIR"
        case .serious: return "HOT"
        case .critical: return "CRIT"
        @unknown default: return "UNK"
        }
    }

    private var thermalColor: Color {
        switch monitor.thermalState {
        case .nominal: return Theme.good
        case .fair: return Theme.ink2
        case .serious: return Theme.warning
        case .critical: return Theme.critical
        @unknown default: return Theme.ink3
        }
    }

    private var uptimeShort: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h\(String(format: "%02d", minutes))m"
    }

    private func formatSpeed(_ kb: Double) -> String {
        if kb >= 1024 {
            return String(format: "%.1f MB/s", kb / 1024.0)
        } else {
            return String(format: "%.0f KB/s", kb)
        }
    }
}
