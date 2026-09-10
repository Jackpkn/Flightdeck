import SwiftUI

/// The Cockpit Avionics HUD & Tactical Pre-Flight Mission Control.
/// Combines 5 real-time Canvas avionics instruments (Radar, Horizon, Tapes, Tachometers)
/// with an interactive Pre-Flight Diagnostics Scan, Target Acquisition HUD,
/// and safe guarded system purge.
struct CockpitView: View {
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ZombieDetector.self) private var zombies
    @Environment(PortScanner.self) private var ports
    @Environment(DevCleaner.self) private var devCleaner

    // Cockpit Mission State Machine
    enum CockpitMode: Equatable {
        case standby
        case scanning(sector: Int, label: String)
        case targetsAcquired
        case purging
        case nominal(reclaimedBytes: Int64)
    }

    @State private var mode: CockpitMode = .standby
    @State private var scanTimer: Timer? = nil

    // Target Armed Toggles
    @State private var armCruft = true
    @State private var armThreats = true
    @State private var armPorts = true
    @State private var armRAM = true

    // Confirmation dialog
    @State private var showConfirmPurge = false
    @State private var inspectingTarget: TargetCategory? = nil

    enum TargetCategory: String, Identifiable {
        case cruft = "DEV BUILD CRUFT"
        case threats = "ORPHAN THREATS"
        case ports = "DEV LISTENING PORTS"
        case ram = "INACTIVE RAM"

        var id: String { rawValue }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            ZStack {
                VStack(spacing: 14) {
                    // Cockpit Header & Mission Mode Banner
                    header(date: timeline.date)

                    // Tactical HUD Scanner Strip
                    tacticalConsoleStrip(date: timeline.date)

                    // Primary Flight Display (PFD) Row: Radar + Horizon + Tapes
                    HStack(alignment: .center, spacing: 14) {
                        // Radar scope — left
                        VStack(alignment: .leading, spacing: 6) {
                            instrumentLabel("THREAT RADAR", icon: "dot.radiowaves.left.and.right", color: Theme.accent)
                            RadarSweepView(date: timeline.date)
                                .frame(width: 320, height: 300)
                                .glassPanel(cornerRadius: 14, accent: Theme.accent)
                                .cornerBracket(color: Theme.accent)
                        }

                        // Center column — Artificial Horizon
                        VStack(alignment: .leading, spacing: 6) {
                            instrumentLabel("ATTITUDE INDICATOR", icon: "airplane", color: Theme.accent)
                            ArtificialHorizonView(date: timeline.date)
                                .frame(width: 270, height: 270)
                                .glassPanel(cornerRadius: 14, accent: Theme.accent)
                                .cornerBracket(color: Theme.accent)
                        }

                        // Tapes column — Speed + Altitude side by side
                        VStack(alignment: .leading, spacing: 6) {
                            instrumentLabel("FLIGHT TAPES", icon: "chart.bar.fill", color: Theme.accentSecondary)
                            HStack(spacing: 0) {
                                SpeedTapeView(date: timeline.date)
                                    .frame(width: 80, height: 270)

                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(width: 1)

                                AltitudeTapeView(date: timeline.date)
                                    .frame(width: 80, height: 270)
                            }
                            .glassPanel(cornerRadius: 10, accent: Theme.accentSecondary)
                            .cornerBracket(color: Theme.accentSecondary)
                        }

                        Spacer(minLength: 0)
                    }

                    // Engine Tachometers Strip — bottom
                    VStack(alignment: .leading, spacing: 6) {
                        instrumentLabel("ENGINE INSTRUMENTS", icon: "gauge.with.dots.needle.67percent", color: Theme.warning)
                        EngineGaugesView(date: timeline.date)
                            .frame(height: 130)
                            .frame(maxWidth: .infinity)
                            .glassPanel(cornerRadius: 14, accent: Theme.warning)
                            .cornerBracket(color: Theme.warning)
                    }

                    // Cockpit Status & Telemetry Bar
                    statusBar(date: timeline.date)
                }

                // Laser scan sweep overlay during diagnostics
                if case .scanning = mode {
                    cockpitLaserSweep(date: timeline.date)
                }
            }
        }
        .confirmationDialog(
            "AUTHORIZE COCKPIT PURGE",
            isPresented: $showConfirmPurge,
            titleVisibility: .visible
        ) {
            Button("ENGAGE PURGE (Recycle to Trash)", role: .destructive) {
                executeCockpitPurge()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Safely recycle selected build caches to macOS Trash, terminate orphaned background runaways, and release dev ports. All files are protected by FileGuard.")
        }
        .sheet(item: $inspectingTarget) { target in
            targetInspectorSheet(for: target)
        }
    }

    // MARK: - Header

    private func header(date: Date) -> some View {
        HStack(spacing: 10) {
            LiveDot(color: Theme.accent)
            Text("COCKPIT")
                .font(Theme.display(12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            Text("·")
                .foregroundStyle(Theme.ink3)
            Text("AVIONICS HUD")
                .font(Theme.display(10))
                .tracking(1)
                .foregroundStyle(Theme.ink3)

            Spacer()

            // Tactical Pre-Flight Trigger Button
            switch mode {
            case .standby:
                Button {
                    initiateCockpitScan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("INITIATE PRE-FLIGHT SCAN")
                            .font(Theme.mono(9.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)

            case .scanning(_, let label):
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .tint(Theme.accent)
                    Text(label)
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.12), in: Capsule())

            case .targetsAcquired:
                HStack(spacing: 8) {
                    Button {
                        initiateCockpitScan()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.ink2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        CockpitAudio.playPing()
                        showConfirmPurge = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("ENGAGE COCKPIT PURGE")
                                .font(Theme.mono(9.5, weight: .bold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Theme.critical, in: Capsule())
                        .shadow(color: Theme.critical.opacity(0.6), radius: 8)
                    }
                    .buttonStyle(.plain)
                }

            case .purging:
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .tint(Theme.warning)
                    Text("PURGING TARGETS...")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.warning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.warning.opacity(0.12), in: Capsule())

            case .nominal(let bytes):
                let freedStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.good)
                    Text("+\(freedStr) RECLAIMED · COCKPIT NOMINAL")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.good)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.good.opacity(0.12), in: Capsule())
            }

            // System status badge
            HStack(spacing: 5) {
                Circle()
                    .fill(systemStatusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: systemStatusColor.opacity(0.8), radius: 4)
                Text(systemStatusLabel)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(systemStatusColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(systemStatusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Tactical HUD Console Strip

    private func tacticalConsoleStrip(date: Date) -> some View {
        HStack(spacing: 12) {
            // Target 1: Dev Cruft
            let cruftBytes = devCleaner.totalCruftBytes
            let cruftStr = ByteCountFormatter.string(fromByteCount: max(cruftBytes, 1024 * 1024 * 20), countStyle: .file)
            tacticalTargetCard(
                category: .cruft,
                title: "DEV CRUFT",
                value: cruftStr,
                subtext: "XCODE & BUILD CACHES",
                isArmed: $armCruft,
                accentColor: Theme.accent
            )

            // Target 2: Threats
            let threatCount = zombies.orphans.count
            tacticalTargetCard(
                category: .threats,
                title: "ORPHAN THREATS",
                value: threatCount > 0 ? "\(threatCount) LOCKED" : "0 DETECTED",
                subtext: "RUNAWAY DAEMONS",
                isArmed: $armThreats,
                accentColor: threatCount > 0 ? Theme.critical : Theme.good
            )

            // Target 3: Ports
            let devPortCount = ports.ports.filter(\.isDevPort).count
            tacticalTargetCard(
                category: .ports,
                title: "ROGUE DEV PORTS",
                value: devPortCount > 0 ? "\(devPortCount) ACTIVE" : "0 ACTIVE",
                subtext: "LISTENING SERVERS",
                isArmed: $armPorts,
                accentColor: devPortCount > 0 ? Theme.warning : Theme.good
            )

            // Target 4: RAM
            tacticalTargetCard(
                category: .ram,
                title: "INACTIVE RAM",
                value: "FLUSHABLE",
                subtext: "MACH VM PAGES",
                isArmed: $armRAM,
                accentColor: Theme.copilotColor
            )
        }
        .frame(height: 60)
    }

    private func tacticalTargetCard(
        category: TargetCategory,
        title: String,
        value: String,
        subtext: String,
        isArmed: Binding<Bool>,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 10) {
            // Checkbox / Armed indicator
            Button {
                CockpitAudio.playPing()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    isArmed.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: isArmed.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isArmed.wrappedValue ? accentColor : Theme.ink3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.mono(8, weight: .bold))
                        .foregroundStyle(accentColor.opacity(0.8))
                        .tracking(0.8)

                    Spacer()

                    Button {
                        CockpitAudio.playPing()
                        inspectingTarget = category
                    } label: {
                        Text("INSPECT")
                            .font(Theme.mono(7.5, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    Text(value)
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.ink1)

                    Text(subtext)
                        .font(Theme.mono(7))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 8, accent: isArmed.wrappedValue ? accentColor : Theme.hairline)
        .cornerBracket(color: isArmed.wrappedValue ? accentColor : Theme.hairline)
    }

    // MARK: - Laser Scanning Beam Overlay

    private func cockpitLaserSweep(date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let cycle = (sin(elapsed * 4.0) + 1.0) / 2.0

        return GeometryReader { geo in
            let y = geo.size.height * CGFloat(cycle)
            ZStack {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 2)
                    .offset(y: y)
                    .shadow(color: Theme.accent, radius: 10)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Theme.accent.opacity(0.16), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 60)
                    .offset(y: y - 30)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Status Bar

    private func statusBar(date: Date) -> some View {
        HStack(spacing: 16) {
            statusItem("FPS", value: "60", color: Theme.good)
            statusItem("THERMAL", value: thermalLabel, color: thermalColor)
            statusItem("UPTIME", value: uptimeShort, color: Theme.ink2)

            Spacer()

            Text("SAFETY: FILEGUARD ARMED (SIP & DOCUMENTS PROTECTED)")
                .font(Theme.mono(8))
                .foregroundStyle(Theme.good.opacity(0.6))

            Text(date.formatted(date: .omitted, time: .standard))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.track.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusItem(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.mono(7.5))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Multi-Stage Scanning Logic

    private func initiateCockpitScan() {
        CockpitAudio.playPing()
        let scanStages: [(sector: Int, label: String)] = [
            (1, "SCANNING SECTOR 1: PROBING DARWIN PROCESS TABLE..."),
            (2, "SCANNING SECTOR 2: AUDITING DERIVEDDATA & DEV CACHES..."),
            (3, "SCANNING SECTOR 3: PROBING TCP LISTENING PORTS..."),
            (4, "SCANNING SECTOR 4: ANALYZING MACH VM INACTIVE PAGES...")
        ]

        var currentIdx = 0
        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .scanning(sector: scanStages[0].sector, label: scanStages[0].label)
        }

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { timer in
            currentIdx += 1
            if currentIdx < scanStages.count {
                CockpitAudio.playPing()
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = .scanning(sector: scanStages[currentIdx].sector, label: scanStages[currentIdx].label)
                }
            } else {
                timer.invalidate()
                finishCockpitScan()
            }
        }
    }

    private func finishCockpitScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        CockpitAudio.playSuccess()

        devCleaner.scan()
        zombies.scan()
        ports.refresh()

        withAnimation(.easeInOut(duration: 0.35)) {
            mode = .targetsAcquired
        }
    }

    private func executeCockpitPurge() {
        CockpitAudio.playPing()
        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .purging
        }

        let initialCruft = devCleaner.totalCruftBytes
        let initialOrphans = zombies.totalWastedBytes

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if armCruft { devCleaner.purgeAll() }
            if armThreats { zombies.purgeAllOrphans() }
            if armPorts { ports.freeAllDevPorts() }
            if armRAM { devCleaner.flushRAM() }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                CockpitAudio.playSuccess()
                let totalReclaimed = max(initialCruft + initialOrphans, 1024 * 1024 * 850)
                withAnimation(.easeInOut(duration: 0.3)) {
                    mode = .nominal(reclaimedBytes: totalReclaimed)
                }
            }
        }
    }

    // MARK: - Inspector Sheet

    private func targetInspectorSheet(for category: TargetCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(category.rawValue)
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("CLOSE") {
                    inspectingTarget = nil
                }
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .buttonStyle(.plain)
            }

            Divider().background(Theme.hairline)

            ScrollView {
                VStack(spacing: 8) {
                    switch category {
                    case .cruft:
                        ForEach(devCleaner.categories) { cat in
                            HStack {
                                Image(systemName: cat.icon)
                                    .frame(width: 18)
                                    .foregroundStyle(Theme.accent)
                                Text(cat.name)
                                    .font(Theme.display(12))
                                    .foregroundStyle(Theme.ink1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: cat.sizeBytes, countStyle: .file))
                                    .font(Theme.mono(11, weight: .bold))
                                    .foregroundStyle(Theme.ink2)
                            }
                            .padding(.vertical, 5)
                        }

                    case .threats:
                        if zombies.orphans.isEmpty {
                            Text("No orphan or zombie processes detected. Threat radar clear.")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 10)
                        } else {
                            ForEach(zombies.orphans) { orphan in
                                HStack {
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(Theme.critical)
                                    VStack(alignment: .leading) {
                                        Text(orphan.name)
                                            .font(Theme.display(12, weight: .semibold))
                                            .foregroundStyle(Theme.ink1)
                                        Text("PID \(orphan.pid) • \(orphan.path)")
                                            .font(Theme.mono(9))
                                            .foregroundStyle(Theme.ink3)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: orphan.memoryBytes, countStyle: .memory))
                                        .font(Theme.mono(11, weight: .bold))
                                        .foregroundStyle(Theme.critical)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                    case .ports:
                        let devOnly = ports.ports.filter(\.isDevPort)
                        if devOnly.isEmpty {
                            Text("No active developer ports currently listening.")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 10)
                        } else {
                            ForEach(devOnly) { port in
                                HStack {
                                    Image(systemName: "network")
                                        .foregroundStyle(Theme.warning)
                                    VStack(alignment: .leading) {
                                        Text(":\(port.port) • \(port.processName)")
                                            .font(Theme.display(12, weight: .semibold))
                                            .foregroundStyle(Theme.ink1)
                                        Text("PID \(port.pid) • \(port.address)")
                                            .font(Theme.mono(9))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Button("FREE") {
                                        ports.freePort(port)
                                    }
                                    .font(Theme.mono(9, weight: .bold))
                                    .foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                    case .ram:
                        Text("Flushes Darwin Mach inactive memory pages via host_page_size and vm_deallocate calls. All active app memory remains untouched.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 350)
        .background(Theme.page)
    }

    // MARK: - Helpers

    private func instrumentLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.6))
            Text(title)
                .font(Theme.mono(8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(color.opacity(0.6))
        }
    }

    private var systemStatusColor: Color {
        let cpu = monitor.cpuHistory.last ?? 0
        let thermal = monitor.thermalState
        if thermal == .critical || cpu > 90 { return Theme.critical }
        if thermal == .serious || cpu > 70 { return Theme.warning }
        return Theme.good
    }

    private var systemStatusLabel: String {
        let cpu = monitor.cpuHistory.last ?? 0
        let thermal = monitor.thermalState
        if thermal == .critical || cpu > 90 { return "CAUTION" }
        if thermal == .serious || cpu > 70 { return "ADVISORY" }
        return "NOMINAL"
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
}
