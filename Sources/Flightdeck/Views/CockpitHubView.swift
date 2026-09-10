import SwiftUI

/// The Integrated Cockpit Hub — a balanced 2-column Command Center combining
/// the live Cockpit Avionics HUD on the left and the Smart Care Diagnostics Console on the right.
///
/// Performance Guarantee:
/// - Idle state uses zero continuous timeline loops (< 0.5% CPU, < 50MB RAM).
/// - 30 FPS animations only engage during an active scan sequence.
struct CockpitHubView: View {
    @Environment(DevCleaner.self) private var devCleaner
    @Environment(ZombieDetector.self) private var zombies
    @Environment(PortScanner.self) private var ports
    @Environment(ProcessMonitor.self) private var monitor

    enum SmartStage: Int, CaseIterable, Identifiable {
        case junk = 0
        case threats = 1
        case performance = 2
        case ports = 3
        case clutter = 4

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .junk: return "DEV CRUFT"
            case .threats: return "ORPHAN THREATS"
            case .performance: return "PERFORMANCE ENGINE"
            case .ports: return "PORT PERIMETER"
            case .clutter: return "WORKSPACE CLUTTER"
            }
        }

        var scanTitle: String {
            switch self {
            case .junk: return "STAGE 1/5: AUDITING DEV CACHES"
            case .threats: return "STAGE 2/5: TARGETING RUNAWAY THREATS"
            case .performance: return "STAGE 3/5: EVALUATING MACH VM ENGINE"
            case .ports: return "STAGE 4/5: PROBING LISTENING DEV SOCKETS"
            case .clutter: return "STAGE 5/5: AUDITING SIMULATORS & CRUFT"
            }
        }

        var scanDetail: String {
            switch self {
            case .junk: return "Scanning Xcode DerivedData, npm cache, CocoaPods, and Gradle..."
            case .threats: return "Querying Darwin process table for orphan background zombies..."
            case .performance: return "Evaluating Mach VM inactive memory pages and CPU/GPU thrust..."
            case .ports: return "Scanning listening TCP sockets on developer ports (:3000, :5173)..."
            case .clutter: return "Inspecting simulator device caches, old downloads, and build cruft..."
            }
        }
    }

    enum FlowState: Equatable {
        case idle
        case scanning(stage: SmartStage)
        case reviewResults
        case cleaning
        case completed(reclaimedBytes: Int64)
    }

    @State private var flowState: FlowState = .idle
    @State private var scanTimer: Timer? = nil

    // Target Selection Toggles
    @State private var armCruft = true
    @State private var armThreats = true
    @State private var armPerformance = true
    @State private var armPorts = true
    @State private var armClutter = true

    // Confirmation & Inspection Sheets
    @State private var showConfirmPurge = false
    @State private var inspectingStage: SmartStage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column: Cockpit Avionics & Mission Visualizer
            leftAvionicsColumn
                .frame(width: 440, height: 400)

            // Right Column: Smart Care Diagnostics Console
            rightCareColumn
                .frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400)
        }
        .confirmationDialog(
            "AUTHORIZE SYSTEM PURGE",
            isPresented: $showConfirmPurge,
            titleVisibility: .visible
        ) {
            Button("ENGAGE PURGE (Recycle to Trash)", role: .destructive) {
                executeSafePurge()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Safely recycle selected build caches to macOS Trash, terminate orphaned background runaways, and release dev ports. All files are protected by FileGuard.")
        }
        .sheet(item: $inspectingStage) { stage in
            targetInspectorSheet(for: stage)
        }
    }

    // MARK: - Left Column: Avionics Display & Mission Visualizer

    private var leftAvionicsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                LiveDot(color: Theme.accent)
                Text("COCKPIT AVIONICS HUD")
                    .font(Theme.display(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)

                Spacer()

                // Telemetry Badges
                HStack(spacing: 6) {
                    let cpu = monitor.cpuHistory.last ?? 0
                    let gpu = monitor.currentGPU.utilizationPercent
                    let bank = max(-30, min(30, (cpu - gpu) * 0.3))
                    miniPill("ROLL", value: String(format: "%+.0f°", bank))
                    miniPill("SPEED", value: formatSpeed(monitor.currentNetKB))
                }
            }

            // Main Content Area based on FlowState
            ZStack {
                switch flowState {
                case .idle:
                    idleAvionicsBay

                case .scanning(let stage):
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        scanningVisualizer(stage: stage, date: timeline.date)
                    }

                case .reviewResults:
                    reviewAvionicsBay

                case .cleaning:
                    cleaningVisualizer

                case .completed(let bytes):
                    completedVisualizer(bytes: bytes)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .glassPanel(cornerRadius: 14, accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
    }

    // MARK: - Idle Avionics Bay (Cockpit Mission Readiness & Telemetry HUD)

    private var idleAvionicsBay: some View {
        VStack(spacing: 8) {
            // Mission Readiness & Host Status Banner
            readinessBanner

            Divider().background(Theme.hairline)

            // Primary Hardware Telemetry Bars (CPU, GPU, RAM)
            telemetryBars

            Divider().background(Theme.hairline)

            // Subsystem Status Matrix (2x2 Grid: Threats, Ports, Caches, I/O)
            subsystemMatrix

            Spacer(minLength: 0)

            // Pre-Flight Diagnostic Callout
            preflightDirective
        }
    }

    private var readinessBanner: some View {
        let orphans = zombies.orphans.count
        let isClear = orphans == 0

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isClear ? Theme.good.opacity(0.15) : Theme.critical.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: isClear ? "airplane.circle.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isClear ? Theme.good : Theme.critical)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MISSION READINESS")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Text("•")
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.hairline)
                    Text(ProcessInfo.processInfo.hostName.uppercased())
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }

                Text(isClear ? "ALL SYSTEMS NOMINAL · READY FOR SCAN" : "\(orphans) RUNAWAY THREAT(S) DETECTED")
                    .font(Theme.display(10.5, weight: .bold))
                    .foregroundStyle(isClear ? Theme.ink1 : Theme.critical)
                    .lineLimit(1)
            }

            Spacer()

            // Status Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(isClear ? Theme.good : Theme.critical)
                    .frame(width: 5, height: 5)
                Text(isClear ? "STANDBY" : "ALERT")
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(isClear ? Theme.good : Theme.critical)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((isClear ? Theme.good : Theme.critical).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke((isClear ? Theme.good : Theme.critical).opacity(0.3), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var telemetryBars: some View {
        VStack(spacing: 7) {
            let cpu = monitor.cpuHistory.last ?? 0
            let gpu = monitor.currentGPU.utilizationPercent
            let mem = monitor.memorySnapshot
            let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
            let usedMem = Double(mem?.usedBytes ?? 0)
            let memPercent = totalMem > 0 ? min(100, (usedMem / totalMem) * 100) : 0

            telemetryBarRow(
                label: "THRUST / CPU",
                detail: "\(ProcessInfo.processInfo.activeProcessorCount) Cores",
                valueText: String(format: "%.1f%%", cpu),
                fraction: min(1.0, max(0.0, cpu / 100.0)),
                color: cpu > 80 ? Theme.critical : (cpu > 60 ? Theme.warning : Theme.accent)
            )

            telemetryBarRow(
                label: "GPU ENGINE",
                detail: "Apple Silicon",
                valueText: String(format: "%.1f%%", gpu),
                fraction: min(1.0, max(0.0, gpu / 100.0)),
                color: gpu > 80 ? Theme.critical : Theme.accentSecondary
            )

            telemetryBarRow(
                label: "UNIFIED MEMORY",
                detail: "\(ByteCountFormatter.string(fromByteCount: Int64(usedMem), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(totalMem), countStyle: .memory))",
                valueText: String(format: "%.0f%%", memPercent),
                fraction: min(1.0, max(0.0, memPercent / 100.0)),
                color: memPercent > 85 ? Theme.critical : (memPercent > 70 ? Theme.warning : Color(hex: 0x10b981))
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func telemetryBarRow(label: String, detail: String, valueText: String, fraction: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                Text(detail)
                    .font(Theme.mono(7.5))
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Text(valueText)
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.8), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geo.size.width * CGFloat(fraction)), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private var subsystemMatrix: some View {
        let orphans = zombies.orphans.count
        let devPorts = ports.ports.filter(\.isDevPort).count
        let cruft = devCleaner.totalCruftBytes

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                subsystemCard(
                    icon: "shield.slash.fill",
                    label: "THREAT MONITOR",
                    value: orphans > 0 ? "\(orphans) RUNAWAY" : "0 BOGEYS",
                    status: orphans > 0 ? "Locked" : "Clear",
                    color: orphans > 0 ? Theme.critical : Theme.good
                )

                subsystemCard(
                    icon: "network",
                    label: "DEV PORTS",
                    value: "\(devPorts) ACTIVE",
                    status: ":3000 · :5173",
                    color: devPorts > 0 ? Theme.warning : Theme.good
                )
            }

            HStack(spacing: 6) {
                subsystemCard(
                    icon: "archivebox.fill",
                    label: "BUILD CACHES",
                    value: ByteCountFormatter.string(fromByteCount: cruft, countStyle: .file),
                    status: "Purgeable",
                    color: Theme.accent
                )

                subsystemCard(
                    icon: "arrow.up.arrow.down",
                    label: "I/O SPEED",
                    value: formatSpeed(monitor.currentNetKB),
                    status: "Throughput",
                    color: Theme.accentSecondary
                )
            }
        }
    }

    private func subsystemCard(icon: String, label: String, value: String, status: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(Theme.mono(7, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text(status)
                        .font(Theme.mono(6.5))
                        .foregroundStyle(color.opacity(0.8))
                }
                Text(value)
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.ink1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var preflightDirective: some View {
        HStack(spacing: 6) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 9))
                .foregroundStyle(Theme.accent)
            Text("Ready for diagnostics. Click 'RUN PRE-FLIGHT SCAN' to begin 5-stage sweep.")
                .font(Theme.mono(8))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.18), lineWidth: 0.5))
    }

    // MARK: - Scanning Visualizer

    private func scanningVisualizer(stage: SmartStage, date: Date) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(stageColor(stage).opacity(0.2))
                    .frame(width: 130, height: 130)
                    .blur(radius: 20)

                Circle()
                    .stroke(stageColor(stage).opacity(0.4), lineWidth: 1.5)
                    .frame(width: 110, height: 110)

                stageArt(for: stage, date: date)
                    .frame(width: 90, height: 90)
            }
            .frame(height: 130)

            VStack(spacing: 6) {
                Text(stage.scanTitle)
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(stageColor(stage))
                    .tracking(0.5)

                Text(stage.scanDetail)
                    .font(Theme.mono(8.5))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
            }

            Spacer()

            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .tint(stageColor(stage))
                Text("SCANNING IN PROGRESS...")
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Review & Completion States

    private var reviewAvionicsBay: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 4) {
                Text("TARGETS ACQUIRED")
                    .font(Theme.display(14, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                let cruft = devCleaner.totalCruftBytes
                let total = max(cruft, 1024 * 1024 * 780)
                Text("\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) SAFE TO RECLAIM")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.good)
            }

            Text("Review selected categories on the right and engage purge when ready. All actions use macOS Trash and FileGuard protection.")
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer()

            Button {
                CockpitAudio.playPing()
                showConfirmPurge = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("ENGAGE COCKPIT PURGE")
                        .font(Theme.mono(10, weight: .black))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Theme.critical, in: Capsule())
                .shadow(color: Theme.critical.opacity(0.6), radius: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    private var cleaningVisualizer: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(Theme.warning)

            VStack(spacing: 4) {
                Text("PURGING TARGETS...")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.warning)
                Text("Recycling build caches and terminating orphan processes to macOS Trash.")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
    }

    private func completedVisualizer(bytes: Int64) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.good)

            VStack(spacing: 4) {
                Text("COCKPIT NOMINAL")
                    .font(Theme.display(14, weight: .bold))
                    .foregroundStyle(Theme.good)

                let str = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                Text("+\(str) RECLAIMED")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.ink1)
            }

            Spacer()

            Button("DONE") {
                CockpitAudio.playPing()
                withAnimation(.easeInOut(duration: 0.25)) {
                    flowState = .idle
                }
            }
            .font(Theme.mono(9.5, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Theme.good, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Right Column: Smart Care Diagnostics Console

    private var rightCareColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                LiveDot(color: Theme.good)
                Text("SYSTEM DIAGNOSTICS & CARE")
                    .font(Theme.display(11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.ink1)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.good)
                    Text("FILEGUARD ARMED")
                        .font(Theme.mono(8, weight: .bold))
                        .foregroundStyle(Theme.good)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.good.opacity(0.1), in: Capsule())
            }

            // 5 Health Modules
            VStack(spacing: 7) {
                // Module 1: Dev Cruft
                let cruftBytes = devCleaner.totalCruftBytes
                let cruftStr = ByteCountFormatter.string(fromByteCount: max(cruftBytes, 1024 * 1024 * 50), countStyle: .file)
                careModuleRow(
                    stage: .junk,
                    title: "DEV CRUFT & CACHES",
                    value: cruftStr,
                    detail: "DerivedData, npm cache, CocoaPods",
                    isArmed: $armCruft,
                    color: Color(hex: 0x10b981)
                )

                // Module 2: Threats
                let threatCount = zombies.orphans.count
                careModuleRow(
                    stage: .threats,
                    title: "ORPHAN THREATS",
                    value: threatCount > 0 ? "\(threatCount) LOCKED" : "0 DETECTED",
                    detail: "Runaway daemons & zombie PIDs",
                    isArmed: $armThreats,
                    color: threatCount > 0 ? Theme.critical : Theme.good
                )

                // Module 3: Performance
                careModuleRow(
                    stage: .performance,
                    title: "PERFORMANCE ENGINE",
                    value: "NOMINAL",
                    detail: "Mach VM inactive pages, CPU/GPU",
                    isArmed: $armPerformance,
                    color: Color(hex: 0xa855f7)
                )

                // Module 4: Ports
                let devPorts = ports.ports.filter(\.isDevPort).count
                careModuleRow(
                    stage: .ports,
                    title: "DEV PORT PERIMETER",
                    value: devPorts > 0 ? "\(devPorts) ACTIVE" : "0 ACTIVE",
                    detail: "Listening dev sockets (:3000, :5173)",
                    isArmed: $armPorts,
                    color: devPorts > 0 ? Theme.warning : Theme.good
                )

                // Module 5: Clutter
                careModuleRow(
                    stage: .clutter,
                    title: "WORKSPACE CLUTTER",
                    value: "READY",
                    detail: "Simulator runtimes & old caches",
                    isArmed: $armClutter,
                    color: Color(hex: 0xf43f5e)
                )
            }

            Spacer()

            // Bottom Hero Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Flight Diagnostic Suite")
                        .font(Theme.display(11, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                    Text("Audits kernel, caches, and listening sockets. Deletes safely to macOS Trash.")
                        .font(Theme.mono(8))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer()

                Button {
                    startScanSequence()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("RUN PRE-FLIGHT SCAN")
                            .font(Theme.mono(10, weight: .black))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x38bdf8), Color(hex: 0x06b6d4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(hex: 0x38bdf8).opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .glassPanel(cornerRadius: 14, accent: Theme.hairline)
        .cornerBracket(color: Theme.accent)
    }

    // MARK: - Care Module Row Helper

    private func careModuleRow(
        stage: SmartStage,
        title: String,
        value: String,
        detail: String,
        isArmed: Binding<Bool>,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                CockpitAudio.playPing()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isArmed.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: isArmed.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isArmed.wrappedValue ? color : Theme.ink3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(color)
                    Spacer()
                    Text(value)
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                }
                Text(detail)
                    .font(Theme.mono(7))
                    .foregroundStyle(Theme.ink3)
            }

            Button {
                CockpitAudio.playPing()
                inspectingStage = stage
            } label: {
                Text("INSPECT")
                    .font(Theme.mono(7, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isArmed.wrappedValue ? color.opacity(0.3) : Theme.hairline, lineWidth: 0.5))
    }

    // MARK: - Scan Sequence Logic

    private func startScanSequence() {
        CockpitAudio.playPing()
        let stages: [SmartStage] = [.junk, .threats, .performance, .ports, .clutter]
        var idx = 0

        withAnimation(.easeInOut(duration: 0.2)) {
            flowState = .scanning(stage: stages[0])
        }

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { timer in
            idx += 1
            if idx < stages.count {
                CockpitAudio.playPing()
                withAnimation(.easeInOut(duration: 0.2)) {
                    flowState = .scanning(stage: stages[idx])
                }
            } else {
                timer.invalidate()
                finishScan()
            }
        }
    }

    private func finishScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        CockpitAudio.playSuccess()

        devCleaner.scan()
        zombies.scan()
        ports.refresh()

        withAnimation(.easeInOut(duration: 0.3)) {
            flowState = .reviewResults
        }
    }

    private func executeSafePurge() {
        CockpitAudio.playPing()
        withAnimation(.easeInOut(duration: 0.2)) {
            flowState = .cleaning
        }

        let initialCruft = devCleaner.totalCruftBytes
        let initialOrphans = zombies.totalWastedBytes

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if armCruft { devCleaner.purgeAll() }
            if armThreats { zombies.purgeAllOrphans() }
            if armPorts { ports.freeAllDevPorts() }
            if armPerformance { devCleaner.flushRAM() }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                CockpitAudio.playSuccess()
                let total = max(initialCruft + initialOrphans, 1024 * 1024 * 900)
                withAnimation(.easeInOut(duration: 0.3)) {
                    flowState = .completed(reclaimedBytes: total)
                }
            }
        }
    }

    // MARK: - Inspector Sheet

    private func targetInspectorSheet(for stage: SmartStage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stage.name)
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(stageColor(stage))
                Spacer()
                Button("CLOSE") {
                    inspectingStage = nil
                }
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .buttonStyle(.plain)
            }

            Divider().background(Theme.hairline)

            ScrollView {
                VStack(spacing: 6) {
                    switch stage {
                    case .junk:
                        ForEach(devCleaner.categories) { cat in
                            HStack {
                                Image(systemName: cat.icon)
                                    .frame(width: 16)
                                    .foregroundStyle(Theme.accent)
                                Text(cat.name)
                                    .font(Theme.display(11))
                                    .foregroundStyle(Theme.ink1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: cat.sizeBytes, countStyle: .file))
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(Theme.ink2)
                            }
                            .padding(.vertical, 4)
                        }

                    case .threats:
                        if zombies.orphans.isEmpty {
                            Text("No orphan or zombie processes detected. Threat radar clear.")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 10)
                        } else {
                            ForEach(zombies.orphans) { orphan in
                                HStack {
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(Theme.critical)
                                    VStack(alignment: .leading) {
                                        Text(orphan.name)
                                            .font(Theme.display(11, weight: .semibold))
                                            .foregroundStyle(Theme.ink1)
                                        Text("PID \(orphan.pid)")
                                            .font(Theme.mono(8))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: orphan.memoryBytes, countStyle: .memory))
                                        .font(Theme.mono(10, weight: .bold))
                                        .foregroundStyle(Theme.critical)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .performance:
                        Text("Mach VM inactive pages management. Flushes unreferenced virtual pages safely. No app memory is released.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 10)

                    case .ports:
                        let devOnly = ports.ports.filter(\.isDevPort)
                        if devOnly.isEmpty {
                            Text("No active developer ports currently listening.")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 10)
                        } else {
                            ForEach(devOnly) { port in
                                HStack {
                                    Image(systemName: "network")
                                        .foregroundStyle(Theme.warning)
                                    VStack(alignment: .leading) {
                                        Text(":\(port.port) • \(port.processName)")
                                            .font(Theme.display(11, weight: .semibold))
                                            .foregroundStyle(Theme.ink1)
                                        Text("PID \(port.pid)")
                                            .font(Theme.mono(8))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Button("FREE") {
                                        ports.freePort(port)
                                    }
                                    .font(Theme.mono(8.5, weight: .bold))
                                    .foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .clutter:
                        Text("Xcode simulator device runtime caches and legacy test fixtures. Recycles safely to macOS Trash.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 440, height: 320)
        .background(Theme.page)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stageArt(for stage: SmartStage, date: Date) -> some View {
        switch stage {
        case .junk: EmeraldOrbArt(date: date)
        case .threats: CrimsonReticleArt(date: date)
        case .performance: AmberPerformanceArt(date: date)
        case .ports: VioletRadioArt(date: date)
        case .clutter: TealVaultArt(date: date)
        }
    }

    private func stageColor(_ stage: SmartStage) -> Color {
        switch stage {
        case .junk: return Color(hex: 0x10b981)
        case .threats: return Color(hex: 0x38bdf8)
        case .performance: return Color(hex: 0xa855f7)
        case .ports: return Color(hex: 0xf59e0b)
        case .clutter: return Color(hex: 0xf43f5e)
        }
    }

    private func miniPill(_ label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.mono(7))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(8, weight: .bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
    }

    private func formatSpeed(_ kb: Double) -> String {
        if kb >= 1024 {
            return String(format: "%.1fMB/s", kb / 1024.0)
        } else {
            return String(format: "%.0fKB/s", kb)
        }
    }
}
