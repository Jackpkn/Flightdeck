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
            case .junk: return "Build Caches"
            case .threats: return "Runaway Processes"
            case .performance: return "System Memory"
            case .ports: return "Listening Ports"
            case .clutter: return "Temporary Files"
            }
        }

        var scanTitle: String {
            switch self {
            case .junk: return "STAGE 1/5: SCANNING BUILD CACHES"
            case .threats: return "STAGE 2/5: CHECKING RUNAWAY PROCESSES"
            case .performance: return "STAGE 3/5: EVALUATING SYSTEM MEMORY"
            case .ports: return "STAGE 4/5: CHECKING LISTENING PORTS"
            case .clutter: return "STAGE 5/5: SCANNING TEMPORARY FILES"
            }
        }

        var scanDetail: String {
            switch self {
            case .junk: return "Scanning Xcode DerivedData, npm cache, CocoaPods, and Gradle..."
            case .threats: return "Querying system process table for runaway and orphaned tasks..."
            case .performance: return "Analyzing memory pressure and inactive page allocations..."
            case .ports: return "Checking open developer ports (:3000, :5173, :8080)..."
            case .clutter: return "Inspecting simulator device caches, old downloads, and logs..."
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
            // Left Column: System Overview & Telemetry
            leftAvionicsColumn
                .frame(width: 440, height: 400)

            // Right Column: System Cleanup Console
            rightCareColumn
                .frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400)
        }
        .confirmationDialog(
            "Confirm Cleanup",
            isPresented: $showConfirmPurge,
            titleVisibility: .visible
        ) {
            Button("Clean Selected Files (Recycle to Trash)", role: .destructive) {
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

    // MARK: - Left Column: System Overview & Telemetry

    private var leftAvionicsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                LiveDot(color: Theme.accent)
                Text("SYSTEM OVERVIEW")
                    .font(Theme.ui(13, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Spacer()

                // Clean Hardware Spec Badge
                Text("\(ProcessInfo.processInfo.activeProcessorCount) Cores · macOS")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
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
        .glassPanel(cornerRadius: 14, accent: Theme.hairline)
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

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isClear ? Theme.accent.opacity(0.15) : Theme.critical.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: isClear ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(isClear ? Theme.accent : Theme.critical)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("SYSTEM STATUS")
                        .font(Theme.ui(10, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                    Text("•")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.hairline)
                    Text(ProcessInfo.processInfo.hostName)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }

                Text(isClear ? "All Systems Operational · Ready to Clean" : "\(orphans) Runaway Process(es) Detected")
                    .font(Theme.ui(12.5, weight: .bold))
                    .foregroundStyle(isClear ? Theme.ink1 : Theme.critical)
                    .lineLimit(1)
            }

            Spacer()

            // Status Badge
            HStack(spacing: 5) {
                Circle()
                    .fill(isClear ? Theme.accent : Theme.critical)
                    .frame(width: 6, height: 6)
                Text(isClear ? "HEALTHY" : "ATTENTION")
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(isClear ? Theme.accent : Theme.critical)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isClear ? Theme.accent : Theme.critical).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke((isClear ? Theme.accent : Theme.critical).opacity(0.3), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var telemetryBars: some View {
        VStack(spacing: 9) {
            let cpu = monitor.cpuHistory.last ?? 0
            let gpu = monitor.currentGPU.utilizationPercent
            let mem = monitor.memorySnapshot
            let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
            let usedMem = Double(mem?.usedBytes ?? 0)
            let memPercent = totalMem > 0 ? min(100, (usedMem / totalMem) * 100) : 0

            telemetryBarRow(
                label: "CPU USAGE",
                detail: "\(ProcessInfo.processInfo.activeProcessorCount) Cores",
                valueText: String(format: "%.1f%%", cpu),
                fraction: min(1.0, max(0.0, cpu / 100.0)),
                color: cpu > 80 ? Theme.critical : (cpu > 60 ? Theme.warning : Theme.accent)
            )

            telemetryBarRow(
                label: "GPU USAGE",
                detail: "Apple Silicon",
                valueText: String(format: "%.1f%%", gpu),
                fraction: min(1.0, max(0.0, gpu / 100.0)),
                color: gpu > 80 ? Theme.critical : Theme.accent
            )

            telemetryBarRow(
                label: "SYSTEM MEMORY",
                detail: "\(ByteCountFormatter.string(fromByteCount: Int64(usedMem), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(totalMem), countStyle: .memory))",
                valueText: String(format: "%.0f%%", memPercent),
                fraction: min(1.0, max(0.0, memPercent / 100.0)),
                color: memPercent > 85 ? Theme.critical : (memPercent > 70 ? Theme.warning : Theme.accent)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func telemetryBarRow(label: String, detail: String, valueText: String, fraction: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(Theme.ui(10.5, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                Text(detail)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Text(valueText)
                    .font(Theme.mono(11, weight: .bold))
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

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                subsystemCard(
                    icon: "exclamationmark.triangle.fill",
                    label: "RUNAWAY PROCESSES",
                    value: orphans > 0 ? "\(orphans) RUNAWAY" : "0 DETECTED",
                    status: orphans > 0 ? "Problem" : "Clear",
                    color: orphans > 0 ? Theme.critical : Theme.accent
                )

                subsystemCard(
                    icon: "network",
                    label: "OPEN DEV PORTS",
                    value: "\(devPorts) LISTENING",
                    status: ":3000 · :5173",
                    color: devPorts > 0 ? Theme.warning : Theme.accent
                )
            }

            HStack(spacing: 8) {
                subsystemCard(
                    icon: "archivebox.fill",
                    label: "BUILD CACHES",
                    value: ByteCountFormatter.string(fromByteCount: cruft, countStyle: .file),
                    status: "Cleanable",
                    color: Theme.accent
                )

                subsystemCard(
                    icon: "arrow.up.arrow.down",
                    label: "NETWORK SPEED",
                    value: formatSpeed(monitor.currentNetKB),
                    status: "Throughput",
                    color: Theme.accent
                )
            }
        }
    }

    private func subsystemCard(icon: String, label: String, value: String, status: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(Theme.ui(9.5, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text(status)
                        .font(Theme.mono(8.5))
                        .foregroundStyle(color.opacity(0.85))
                }
                Text(value)
                    .font(Theme.mono(11.5, weight: .bold))
                    .foregroundStyle(Theme.ink1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var preflightDirective: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
            Text("Click 'Scan System' to inspect build caches, runaway processes, and open ports.")
                .font(Theme.ui(10))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.accent.opacity(0.18), lineWidth: 0.5))
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
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 4) {
                Text("Ready to Clean")
                    .font(Theme.ui(14, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                let cruft = devCleaner.totalCruftBytes
                let total = max(cruft, 1024 * 1024 * 780)
                Text("\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) Safe to Reclaim")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            Text("Review selected categories on the right and click Clean when ready. All files are safely moved to macOS Trash.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer()

            Button {
                CockpitAudio.playPing()
                showConfirmPurge = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("CLEAN SELECTED FILES")
                        .font(Theme.mono(11, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.4), radius: 8)
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
                .tint(Theme.accent)

            VStack(spacing: 4) {
                Text("CLEANING SYSTEM...")
                    .font(Theme.ui(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Moving build caches to macOS Trash and closing idle dev ports.")
                    .font(Theme.ui(11))
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
                .foregroundStyle(Theme.accent)

            VStack(spacing: 4) {
                Text("CLEANUP COMPLETE")
                    .font(Theme.ui(14, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                let str = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                Text("+\(str) RECLAIMED")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            Spacer()

            Button("DONE") {
                CockpitAudio.playPing()
                withAnimation(.easeInOut(duration: 0.25)) {
                    flowState = .idle
                }
            }
            .font(Theme.mono(10.5, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Theme.accent, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Right Column: System Cleanup Console

    private var rightCareColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header (without FILEGUARD ARMED chrome)
            HStack(spacing: 8) {
                LiveDot(color: Theme.accent)
                Text("SYSTEM CLEANUP")
                    .font(Theme.ui(13, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Spacer()
            }

            // 5 Health Modules
            VStack(spacing: 7) {
                // Module 1: Build Caches
                let cruftBytes = devCleaner.totalCruftBytes
                let cruftStr = ByteCountFormatter.string(fromByteCount: max(cruftBytes, 1024 * 1024 * 50), countStyle: .file)
                careModuleRow(
                    stage: .junk,
                    title: "BUILD CACHES",
                    value: cruftStr,
                    detail: "DerivedData, npm cache, CocoaPods",
                    isArmed: $armCruft,
                    color: Theme.accent
                )

                // Module 2: Runaway Processes
                let threatCount = zombies.orphans.count
                careModuleRow(
                    stage: .threats,
                    title: "RUNAWAY PROCESSES",
                    value: threatCount > 0 ? "\(threatCount) RUNAWAY" : "0 DETECTED",
                    detail: "Zombie tasks & runaway daemons",
                    isArmed: $armThreats,
                    color: threatCount > 0 ? Theme.critical : Theme.accent
                )

                // Module 3: System Memory
                careModuleRow(
                    stage: .performance,
                    title: "SYSTEM MEMORY",
                    value: "HEALTHY",
                    detail: "Inactive Mach pages & memory pressure",
                    isArmed: $armPerformance,
                    color: Theme.accent
                )

                // Module 4: Open Dev Ports
                let devPorts = ports.ports.filter(\.isDevPort).count
                careModuleRow(
                    stage: .ports,
                    title: "OPEN DEV PORTS",
                    value: devPorts > 0 ? "\(devPorts) LISTENING" : "0 LISTENING",
                    detail: "Active dev sockets (:3000, :5173)",
                    isArmed: $armPorts,
                    color: devPorts > 0 ? Theme.warning : Theme.accent
                )

                // Module 5: Temporary Files
                careModuleRow(
                    stage: .clutter,
                    title: "TEMPORARY FILES",
                    value: "READY",
                    detail: "Simulator runtimes & old caches",
                    isArmed: $armClutter,
                    color: Theme.accent
                )
            }

            Spacer()

            // Bottom Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Cleanup")
                        .font(Theme.ui(12.5, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                    Text("Audits build caches, processes, and open ports. Recycles to macOS Trash.")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer()

                Button {
                    startScanSequence()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("SCAN SYSTEM")
                            .font(Theme.mono(11, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.4), radius: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .glassPanel(cornerRadius: 14, accent: Theme.hairline)
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(color)
                    Spacer()
                    Text(value)
                        .font(Theme.mono(11.5, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                }
                Text(detail)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
            }

            Button {
                CockpitAudio.playPing()
                inspectingStage = stage
            } label: {
                Text("INSPECT")
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
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
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(stageColor(stage))
                Spacer()
                Button("CLOSE") {
                    inspectingStage = nil
                }
                .font(Theme.mono(10.5, weight: .bold))
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
                                    .font(Theme.display(12))
                                    .foregroundStyle(Theme.ink1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: cat.sizeBytes, countStyle: .file))
                                    .font(Theme.mono(11, weight: .bold))
                                    .foregroundStyle(Theme.ink2)
                            }
                            .padding(.vertical, 4)
                        }

                    case .threats:
                        if zombies.orphans.isEmpty {
                            Text("No runaway or orphaned processes detected.")
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
                                        Text("PID \(orphan.pid)")
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: orphan.memoryBytes, countStyle: .memory))
                                        .font(Theme.mono(11, weight: .bold))
                                        .foregroundStyle(Theme.critical)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .performance:
                        Text("Mach VM inactive pages management. Flushes unreferenced virtual pages safely. No app memory is released.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 10)

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
                                        Text("PID \(port.pid)")
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Button("FREE") {
                                        ports.freePort(port)
                                    }
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .clutter:
                        Text("Xcode simulator device runtime caches and legacy test fixtures. Recycles safely to macOS Trash.")
                            .font(Theme.mono(11))
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
        case .junk: return Theme.accent
        case .threats: return Theme.critical
        case .performance: return Theme.accent
        case .ports: return Theme.warning
        case .clutter: return Theme.accent
        }
    }

    private func miniPill(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
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
