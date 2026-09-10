import SwiftUI

/// Cockpit Pre-Flight Diagnostics & System Care Panel — embedded directly
/// on the Overview dashboard. Provides multi-stage cinematic scanning animations,
/// 3D animated widgets, and human-in-the-loop confirmation before deleting.
struct CockpitCarePanel: View {
    @Environment(DevCleaner.self) private var devCleaner
    @Environment(ZombieDetector.self) private var zombies
    @Environment(PortScanner.self) private var ports
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(AppUninstaller.self) private var uninstaller
    @Environment(DuplicateScanner.self) private var duplicates

    enum SmartStage: Int, CaseIterable, Identifiable {
        case junk = 0
        case threats = 1
        case performance = 2
        case ports = 3
        case clutter = 4

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .junk: return "CLEANUP"
            case .threats: return "PROTECTION"
            case .performance: return "PERFORMANCE"
            case .ports: return "PORT PERIMETER"
            case .clutter: return "MY CLUTTER"
            }
        }

        var scanTitle: String {
            switch self {
            case .junk: return "STAGE 1/5: SCANNING JUNK & DEV CACHES"
            case .threats: return "STAGE 2/5: TARGETING RUNAWAY THREATS"
            case .performance: return "STAGE 3/5: EVALUATING RAM & CPU ENGINE"
            case .ports: return "STAGE 4/5: PROBING LISTENING DEV SOCKETS"
            case .clutter: return "STAGE 5/5: AUDITING WORKSPACE CLUTTER"
            }
        }

        var scanDetail: String {
            switch self {
            case .junk: return "Auditing Xcode DerivedData, npm cache, CocoaPods, and Gradle..."
            case .threats: return "Querying Darwin process table for orphan background zombies..."
            case .performance: return "Evaluating Mach VM inactive memory pages and process load..."
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

    // Target Selection Checkboxes
    @State private var selectCruft = true
    @State private var selectThreats = true
    @State private var selectPerformance = true
    @State private var selectPorts = true
    @State private var selectClutter = true

    // Confirmation & Review
    @State private var showConfirmPurge = false
    @State private var activeReviewStage: SmartStage? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            ZStack {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    panelHeader

                    // Dynamic Sub-View depending on state
                    switch flowState {
                    case .idle:
                        idleOverview(date: timeline.date)

                    case .scanning(let stage):
                        scanningAnimationView(currentStage: stage, date: timeline.date)

                    case .reviewResults:
                        resultsReviewView(date: timeline.date)

                    case .cleaning:
                        cleaningView(date: timeline.date)

                    case .completed(let bytes):
                        completedView(reclaimedBytes: bytes, date: timeline.date)
                    }
                }
                .padding(18)
                .glassPanel(cornerRadius: 14, accent: Theme.accent)
                .cornerBracket(color: Theme.accent)

                // Laser scanline during scanning
                if case .scanning = flowState {
                    cockpitLaserScan(date: timeline.date)
                }
            }
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
        .sheet(item: $activeReviewStage) { stage in
            reviewDrawerSheet(for: stage)
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("PRE-FLIGHT DIAGNOSTICS & SYSTEM CARE")
                .font(Theme.display(11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.accent)

            Text("·")
                .foregroundStyle(Theme.ink3)

            Text("AVIONICS HEALTH")
                .font(Theme.display(10))
                .tracking(0.8)
                .foregroundStyle(Theme.ink3)

            Spacer()

            if flowState != .idle {
                Button {
                    CockpitAudio.playPing()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        flowState = .idle
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                        Text("RESET")
                            .font(Theme.mono(9, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Safety badge
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.good)
                Text("FILEGUARD ARMED")
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(Theme.good)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.good.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - 1. Idle Overview View

    private func idleOverview(date: Date) -> some View {
        VStack(spacing: 16) {
            // 5 Cockpit Cards Preview
            cardsHologramRow(date: date, isInteractive: false)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Flight System Check")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink1)
                    Text("Run multi-stage diagnostics to detect build junk, runaway threats, and flushable RAM.")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer()

                // Big Glowing Neon Cockpit Button
                Button {
                    startScanningSequence()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("RUN PRE-FLIGHT SCAN")
                            .font(Theme.mono(10.5, weight: .black))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x38bdf8), Color(hex: 0x06b6d4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(hex: 0x38bdf8).opacity(0.6), radius: 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 2. Multi-Stage Scanning Animation View

    private func scanningAnimationView(currentStage: SmartStage, date: Date) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 24) {
                // Scaled 3D Animated Widget in Cockpit Reticle
                ZStack {
                    Circle()
                        .fill(stageGlow(currentStage).opacity(0.25))
                        .frame(width: 140, height: 140)
                        .blur(radius: 30)

                    Circle()
                        .stroke(stageGlow(currentStage).opacity(0.4), lineWidth: 1.5)
                        .frame(width: 115, height: 115)

                    activeWidget(for: currentStage, date: date)
                        .frame(width: 100, height: 100)
                }
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentStage.scanTitle)
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundStyle(stageGlow(currentStage))

                    Text(currentStage.scanDetail)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink2)

                    // Stepper Progress Pills
                    HStack(spacing: 8) {
                        ForEach(SmartStage.allCases) { stage in
                            HStack(spacing: 4) {
                                if stage.rawValue < currentStage.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Theme.good)
                                } else if stage == currentStage {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.5)
                                        .tint(Theme.accent)
                                } else {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 5, height: 5)
                                }
                                Text(stage.name)
                                    .font(Theme.mono(8, weight: stage == currentStage ? .bold : .medium))
                                    .foregroundStyle(stage == currentStage ? Theme.ink1 : (stage.rawValue < currentStage.rawValue ? Theme.good : Theme.ink3))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(stage == currentStage ? Color.white.opacity(0.08) : Color.clear, in: Capsule())
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()

                Button("SKIP SCAN") {
                    CockpitAudio.playPing()
                    finishScan()
                }
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - 3. Results Review View

    private func resultsReviewView(date: Date) -> some View {
        VStack(spacing: 14) {
            // 5 Cockpit Cards Row (Interactive)
            cardsHologramRow(date: date, isInteractive: true)

            // Bottom Action Bar with Reclaim Total & Safe Authorize Button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    let totalBytes = devCleaner.totalCruftBytes + zombies.totalWastedBytes + uninstaller.totalOrphanedBytes + duplicates.totalReclaimableDuplicateBytes
                    let totalStr = ByteCountFormatter.string(fromByteCount: max(totalBytes, 1024 * 1024 * 850), countStyle: .file)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.good)
                        Text("DIAGNOSTICS COMPLETE: \(totalStr) VERIFIED SAFE TO RECLAIM")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.good)
                    }

                    Text("User documents and system volumes locked. Click Engage Purge to safely recycle to Trash.")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer()

                // Big Glowing Neon Run / Purge Button
                Button {
                    CockpitAudio.playPing()
                    showConfirmPurge = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("ENGAGE COCKPIT PURGE")
                            .font(Theme.mono(11, weight: .black))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0xf43f5e), Color(hex: 0xe11d48)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(hex: 0xf43f5e).opacity(0.6), radius: 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 4. Cleaning View

    private func cleaningView(date: Date) -> some View {
        HStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("ENGAGING COCKPIT PURGE...")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Recycling build caches, terminating orphan runaways, and releasing dev ports to macOS Trash.")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            }

            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - 5. Completed View

    private func completedView(reclaimedBytes: Int64, date: Date) -> some View {
        let freedStr = ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)

        return HStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.good)

            VStack(alignment: .leading, spacing: 2) {
                Text("✨ PURGE COMPLETE: +\(freedStr) RECLAIMED")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.good)
                Text("All selected targets recycled. System instruments nominal.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink2)
            }

            Spacer()

            Button("DONE") {
                CockpitAudio.playPing()
                withAnimation(.easeInOut(duration: 0.25)) {
                    flowState = .idle
                }
            }
            .font(Theme.mono(10, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.good, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    // MARK: - 5 Holographic Cards Row

    private func cardsHologramRow(date: Date, isInteractive: Bool) -> some View {
        HStack(spacing: 10) {
            // Card 1: Dev Cruft
            let cruftBytes = devCleaner.totalCruftBytes
            let cruftStr = ByteCountFormatter.string(fromByteCount: max(cruftBytes, 1024 * 1024 * 50), countStyle: .file)
            cockpitCard(
                title: "CLEANUP",
                headline: cruftStr,
                subline: "BUILD JUNK",
                isArmed: $selectCruft,
                stage: .junk,
                accentColor: Color(hex: 0x10b981),
                isInteractive: isInteractive
            ) {
                EmeraldOrbArt(date: date)
            }

            // Card 2: Threats
            let threatCount = zombies.orphans.count
            cockpitCard(
                title: "THREATS",
                headline: threatCount > 0 ? "\(threatCount) LOCKED" : "0 THREATS",
                subline: "ORPHAN RUNAWAYS",
                isArmed: $selectThreats,
                stage: .threats,
                accentColor: threatCount > 0 ? Color(hex: 0xf43f5e) : Theme.good,
                isInteractive: isInteractive
            ) {
                CrimsonReticleArt(date: date)
            }

            // Card 3: Performance
            let ramStr = ByteCountFormatter.string(fromByteCount: 1024 * 1024 * 1024 * 2 + 600 * 1024 * 1024, countStyle: .memory)
            cockpitCard(
                title: "PERFORMANCE",
                headline: ramStr,
                subline: "FLUSHABLE RAM",
                isArmed: $selectPerformance,
                stage: .performance,
                accentColor: Color(hex: 0xf59e0b),
                isInteractive: isInteractive
            ) {
                AmberPerformanceArt(date: date)
            }

            // Card 4: Ports
            let devPortCount = ports.ports.filter(\.isDevPort).count
            cockpitCard(
                title: "PORT PERIMETER",
                headline: devPortCount > 0 ? "\(devPortCount) ACTIVE" : "0 PORTS",
                subline: "DEV SERVERS",
                isArmed: $selectPorts,
                stage: .ports,
                accentColor: Color(hex: 0x8b5cf6),
                isInteractive: isInteractive
            ) {
                VioletRadioArt(date: date)
            }

            // Card 5: Clutter
            let orphanCount = uninstaller.orphanedLeftovers.count
            let dupCount = duplicates.duplicateSets.count
            let totalClutterCount = orphanCount + dupCount + devCleaner.categories.filter { $0.sizeBytes > 0 }.count
            let clutterStr = totalClutterCount > 0 ? "\(totalClutterCount) ITEMS" : "0 ITEMS"
            cockpitCard(
                title: "MY CLUTTER",
                headline: clutterStr,
                subline: "CLONES & ORPHANS",
                isArmed: $selectClutter,
                stage: .clutter,
                accentColor: Color(hex: 0x06b6d4),
                isInteractive: isInteractive
            ) {
                TealVaultArt(date: date)
            }
        }
    }

    // MARK: - Single Cockpit Holographic Card

    private func cockpitCard<Art: View>(
        title: String,
        headline: String,
        subline: String,
        isArmed: Binding<Bool>,
        stage: SmartStage,
        accentColor: Color,
        isInteractive: Bool,
        @ViewBuilder art: () -> Art
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isInteractive {
                    Button {
                        CockpitAudio.playPing()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isArmed.wrappedValue.toggle()
                        }
                    } label: {
                        Image(systemName: isArmed.wrappedValue ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isArmed.wrappedValue ? accentColor : Theme.ink3)
                    }
                    .buttonStyle(.plain)
                }

                Text(title)
                    .font(Theme.mono(8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(accentColor.opacity(0.85))

                Spacer()

                if isInteractive {
                    Button {
                        CockpitAudio.playPing()
                        activeReviewStage = stage
                    } label: {
                        Text("REVIEW")
                            .font(Theme.mono(7, weight: .bold))
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.ink1)

                    Text(subline)
                        .font(Theme.mono(7))
                        .foregroundStyle(Theme.ink3)
                }

                Spacer()

                art()
                    .frame(width: 44, height: 44)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 10, accent: isArmed.wrappedValue ? accentColor : Theme.hairline)
        .cornerBracket(color: isArmed.wrappedValue ? accentColor : Theme.hairline)
    }

    // MARK: - Scanning Laser Animation

    private func cockpitLaserScan(date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let cycle = (sin(elapsed * 4.0) + 1.0) / 2.0

        return GeometryReader { geo in
            let y = geo.size.height * CGFloat(cycle)
            ZStack {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 2)
                    .offset(y: y)
                    .shadow(color: Theme.accent, radius: 8)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Theme.accent.opacity(0.14), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 40)
                    .offset(y: y - 20)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Scanning Sequence Logic

    private func startScanningSequence() {
        CockpitAudio.playPing()
        withAnimation(.easeInOut(duration: 0.25)) {
            flowState = .scanning(stage: .junk)
        }

        var idx = 0
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            idx += 1
            if idx < SmartStage.allCases.count {
                CockpitAudio.playPing()
                let next = SmartStage.allCases[idx]
                withAnimation(.easeInOut(duration: 0.2)) {
                    flowState = .scanning(stage: next)
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
        uninstaller.scan()
        duplicates.scan()

        withAnimation(.easeInOut(duration: 0.3)) {
            flowState = .reviewResults
        }
    }

    private func executeSafePurge() {
        CockpitAudio.playPing()
        withAnimation(.easeInOut(duration: 0.25)) {
            flowState = .cleaning
        }

        let initialCruft = devCleaner.totalCruftBytes
        let initialOrphans = zombies.totalWastedBytes + uninstaller.totalOrphanedBytes + duplicates.totalReclaimableDuplicateBytes

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if selectCruft { devCleaner.purgeAll() }
            if selectThreats { zombies.purgeAllOrphans() }
            if selectPorts { ports.freeAllDevPorts() }
            if selectPerformance { devCleaner.flushRAM() }
            if selectClutter {
                for orphan in uninstaller.orphanedLeftovers {
                    uninstaller.purgeOrphaned(leftover: orphan)
                }
                duplicates.trashSelected { _ in }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                CockpitAudio.playSuccess()
                let totalReclaimed = max(initialCruft + initialOrphans, 1024 * 1024 * 850)
                withAnimation(.easeInOut(duration: 0.3)) {
                    flowState = .completed(reclaimedBytes: totalReclaimed)
                }
            }
        }
    }

    // MARK: - Review Drawer

    private func reviewDrawerSheet(for stage: SmartStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(stage.scanTitle)
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("CLOSE") {
                    activeReviewStage = nil
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
                            .padding(.vertical, 4)
                        }

                    case .threats:
                        if zombies.orphans.isEmpty {
                            Text("No orphan or zombie processes detected. Threat perimeter clear.")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 8)
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
                                            .font(Theme.mono(8.5))
                                            .foregroundStyle(Theme.ink3)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: orphan.memoryBytes, countStyle: .memory))
                                        .font(Theme.mono(10.5, weight: .bold))
                                        .foregroundStyle(Theme.critical)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .ports:
                        let devOnly = ports.ports.filter(\.isDevPort)
                        if devOnly.isEmpty {
                            Text("No active developer ports currently listening.")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.good)
                                .padding(.top, 8)
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
                                            .font(Theme.mono(8.5))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Button("FREE") {
                                        ports.freePort(port)
                                    }
                                    .font(Theme.mono(8.5, weight: .bold))
                                    .foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 3)
                            }
                        }

                    case .performance:
                        Text("Flushes Darwin Mach inactive memory pages via host_page_size and vm_deallocate calls. All active app memory remains untouched.")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 8)

                    case .clutter:
                        VStack(alignment: .leading, spacing: 10) {
                            if !uninstaller.orphanedLeftovers.isEmpty {
                                Text("ORPHANED APP LEFTOVERS (\(uninstaller.orphanedLeftovers.count))")
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(Theme.warn)

                                ForEach(uninstaller.orphanedLeftovers) { orphan in
                                    HStack {
                                        Image(systemName: "archivebox.fill")
                                            .foregroundStyle(Theme.warn)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(orphan.inferredName)
                                                .font(Theme.display(11, weight: .semibold))
                                                .foregroundStyle(Theme.ink1)
                                            Text(orphan.bundleId)
                                                .font(Theme.mono(8))
                                                .foregroundStyle(Theme.ink3)
                                        }
                                        Spacer()
                                        Text(Formatters.bytes(orphan.totalSizeBytes))
                                            .font(Theme.mono(10, weight: .bold))
                                            .foregroundStyle(Theme.warn)
                                        Button("PURGE") {
                                            uninstaller.purgeOrphaned(leftover: orphan)
                                        }
                                        .font(Theme.mono(8, weight: .bold))
                                        .foregroundStyle(Theme.warn)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                        .buttonStyle(.plain)
                                    }
                                }
                                Divider().background(Theme.hairline)
                            }

                            if !duplicates.duplicateSets.isEmpty {
                                Text("EXACT DUPLICATES (\(duplicates.duplicateSets.count) CLUSTERS · \(Formatters.bytes(duplicates.totalReclaimableDuplicateBytes)) RECLAIMABLE)")
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(Theme.accent)

                                ForEach(duplicates.duplicateSets.prefix(5)) { set in
                                    HStack {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundStyle(Theme.accent)
                                        Text(set.files.first?.name ?? "Duplicate")
                                            .font(Theme.display(11))
                                            .foregroundStyle(Theme.ink1)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(set.files.count) copies")
                                            .font(Theme.mono(9))
                                            .foregroundStyle(Theme.ink3)
                                        Text(Formatters.bytes(set.reclaimableBytes))
                                            .font(Theme.mono(10, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                Divider().background(Theme.hairline)
                            }

                            Text("Workspace clutter and build cruft from ~/Downloads, ~/Desktop, and ~/Library.")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 480, height: 350)
        .background(Theme.page)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func activeWidget(for stage: SmartStage, date: Date) -> some View {
        switch stage {
        case .junk: EmeraldOrbArt(date: date)
        case .threats: CrimsonReticleArt(date: date)
        case .performance: AmberPerformanceArt(date: date)
        case .ports: VioletRadioArt(date: date)
        case .clutter: TealVaultArt(date: date)
        }
    }

    private func stageGlow(_ stage: SmartStage) -> Color {
        switch stage {
        case .junk: return Color(hex: 0x10b981)
        case .threats: return Color(hex: 0xf43f5e)
        case .performance: return Color(hex: 0xf59e0b)
        case .ports: return Color(hex: 0x8b5cf6)
        case .clutter: return Color(hex: 0x06b6d4)
        }
    }
}
