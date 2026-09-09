import SwiftUI
import AppKit

struct DashboardView: View {
    enum Tab: String, CaseIterable { case overview = "Overview", sessions = "Sessions", activity = "Activity", timeline = "Timeline", files = "Files", spend = "Spend" }

    @Environment(DashboardStore.self) private var store
    @Environment(DiskScanner.self) private var diskScanner
    @Environment(ActionCenter.self) private var actions
    @Environment(FileBrowser.self) private var browser
    @Environment(ProcessMonitor.self) private var processMonitor
    @State private var showGraph = false
    @State private var showPalette = false
    @State private var tab: Tab = .overview
    @State private var frames: [String: CGRect] = [:]
    @State private var particles: [FountainParticle] = []
    @State private var editing: FileEditTarget?
    @State private var processActionTarget: ProcessUsage?
    @State private var selectedVitalCategory: VitalCategory?

    var body: some View {
        ZStack {
            if showGraph {
                GraphView(isPresented: $showGraph)
            } else {
                dashboard
            }
            if showPalette {
                CommandPalette(isPresented: $showPalette, showGraph: $showGraph)
            }
            if let editing {
                DownloadEditOverlay(target: editing, onDismiss: { self.editing = nil })
            }
            if let preview = browser.previewEntry {
                FilePreviewOverlay(entry: preview, onDismiss: { browser.previewEntry = nil })
            }
            if let process = processActionTarget {
                ProcessActionModal(
                    usage: process,
                    onDismiss: { processActionTarget = nil },
                    onGracefulQuit: {
                        if let app = NSRunningApplication(processIdentifier: process.id) {
                            app.terminate()
                        } else {
                            kill(process.id, SIGTERM)
                        }
                    },
                    onForceKill: {
                        processMonitor.killProcess(pid: process.id, bundleId: process.bundleId)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let cat = selectedVitalCategory {
                VitalsDetailModal(category: cat, onDismiss: { selectedVitalCategory = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: processActionTarget?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedVitalCategory?.id)
        // Window level, not panel level: a delete triggered from any list gets
        // the same confirmation in the same place.
        .overlay(alignment: .bottom) {
            if let banner = actions.banner {
                ActionToast(
                    banner: banner,
                    onUndo: { actions.undo() },
                    onSettings: { actions.openSettings() },
                    onDismiss: { actions.dismiss() }
                )
                .id(banner.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: actions.banner?.id)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            TopBar(showGraph: $showGraph, showPalette: $showPalette)
            TabPicker(selected: $tab)

            ScrollView {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coordinateSpace(name: "dashboard")
                    .overlay(EmitterTrailOverlay(particles: particles, color: Theme.accent).allowsHitTesting(false))
                    .onPreferenceChange(FramePreferenceKey.self) { frames = $0 }
            }
            .scrollIndicators(.hidden)
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 28, trailing: 28))
        .background(ambientGround)
        .foregroundStyle(Theme.ink1)
        .onChange(of: store.costEvents.count) { _, _ in spawnParticle() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .overview:
            VStack(alignment: .leading, spacing: 18) {
                StatRow()
                SessionBoard()
            }
        case .sessions:
            SessionBoard()
        case .activity:
            VStack(spacing: 14) {
                UsageGraphPanel()
                SystemVitalsStrip(selectedCategory: $selectedVitalCategory)
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        ActivityFeedPanel()
                            .frame(height: 340)
                        PortHunterPanel()
                            .frame(height: 340)
                        DownloadsPanel(editing: $editing)
                            .frame(height: 340)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 14) {
                        ActivityWatcherPanel()
                            .frame(height: 340)
                        ProcessMonitorPanel(actionTarget: $processActionTarget)
                            .frame(height: 340)
                    }
                    .frame(width: 500)
                }
            }
        case .timeline:
            VStack(spacing: 14) {
                TimelinePanel()
                TimelineScrubber()
            }
        case .files:
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    FilesPanel(editing: $editing)
                        .frame(maxWidth: .infinity)
                    DiskRadarPanel()
                        .frame(width: 500)
                }
                // Only meaningful once a scan has produced numbers. Three
                // separate instruments rather than one crowded strip.
                if diskScanner.result.filesScanned > 0 {
                    DiskExplorerPanel()
                    HStack(alignment: .top, spacing: 14) {
                        DiskTypePanel()
                            .frame(maxWidth: .infinity)
                        DiskDistributionPanel()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 252)
                }
            }
        case .spend:
            SpendByProjectPanel()
        }
    }

    private func spawnParticle() {
        guard let event = store.costEvents.last,
              let end = frames["__ticker__"] else { return }
        // Fall back to the board's own frame when this event's session isn't
        // one of the 3 currently displayed cards — the effect should still be
        // visible for any real cost event, not just ones tied to a rendered card.
        guard let start = frames[event.sessionId] ?? frames["__board__"] else { return }
        particles.append(FountainParticle(
            start: CGPoint(x: start.midX, y: start.midY),
            end: CGPoint(x: end.midX, y: end.midY),
            spawnedAt: Date()
        ))
        let cutoff = Date().addingTimeInterval(-1.2)
        particles.removeAll { $0.spawnedAt < cutoff }
    }

    /// A faint accent-tinted glow anchored top-leading, over the void-black page —
    /// the one piece of atmosphere the flat version was missing.
    private var ambientGround: some View {
        ZStack {
            Theme.page
            Canvas { context, size in
                let spacing: CGFloat = 20
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(Color.white.opacity(0.06)))
                        y += spacing
                    }
                    x += spacing
                }
            }
            // HUD coordinate-ruler ticks along the top and left edges.
            Canvas { context, size in
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: 7)), with: .color(Theme.accent.opacity(0.3)))
                    x += 40
                }
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: 7, height: 1)), with: .color(Theme.accent.opacity(0.3)))
                    y += 40
                }
            }
            .allowsHitTesting(false)
            RadialGradient(
                colors: [Theme.accent.opacity(0.10), Theme.page.opacity(0)],
                center: .init(x: 0.08, y: 0.0),
                startRadius: 0,
                endRadius: 640
            )
            RadialGradient(
                colors: [Theme.claudeColor.opacity(0.06), Theme.page.opacity(0)],
                center: .init(x: 1.0, y: 0.15),
                startRadius: 0,
                endRadius: 560
            )
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.045)))
                    y += 3
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tab picker

private struct TabPicker: View {
    @Binding var selected: DashboardView.Tab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DashboardView.Tab.allCases, id: \.self) { t in
                Button {
                    selected = t
                } label: {
                    Text(t.rawValue)
                        .font(Theme.ui(12.5, weight: selected == t ? .semibold : .regular))
                        .foregroundStyle(selected == t ? Theme.ink1 : Theme.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            selected == t ? Theme.panel : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(DashboardStore.self) private var store
    @Environment(DiskScanner.self) private var diskScanner
    @Environment(ActionCenter.self) private var actions
    @Environment(ProcessMonitor.self) private var processMonitor
    @Binding var showGraph: Bool
    @Binding var showPalette: Bool
    @State private var now = Date()
    @State private var errorFlash = false
    @State private var showAlerts = false
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var activeAlerts: [SystemAlertItem] {
        var alerts: [SystemAlertItem] = []
        let currentCPU = processMonitor.cpuHistory.last ?? 0
        if currentCPU >= 90 {
            alerts.append(SystemAlertItem(
                title: "CPU Spike Detected",
                detail: String(format: "System CPU load reached %.0f%%", currentCPU),
                severity: .critical
            ))
        }
        if processMonitor.thermalState == .serious || processMonitor.thermalState == .critical {
            alerts.append(SystemAlertItem(
                title: "Thermal Throttling",
                detail: "Hardware thermal pressure is \(processMonitor.thermalState == .critical ? "CRITICAL" : "SERIOUS")",
                severity: .critical
            ))
        }
        if store.contextAlertCount > 0 {
            alerts.append(SystemAlertItem(
                title: "Context Window Alert",
                detail: "\(store.contextAlertCount) session(s) over 70% context limit",
                severity: .warning
            ))
        }
        if let lastErr = store.lastErrorAt, lastErr.timeIntervalSinceNow > -300 {
            alerts.append(SystemAlertItem(
                title: "Tool Execution Failed",
                detail: "An AI agent tool execution reported an error in session",
                severity: .critical
            ))
        }
        return alerts
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 5)
                Text("FLIGHTDECK").font(Theme.display(14)).tracking(1.2)
                Text("· live workspace").font(Theme.ui(12)).foregroundStyle(Theme.ink3)
            }

            Button {
                showGraph.toggle()
            } label: {
                Text(showGraph ? "Dashboard" : "Session graph")
                    .font(Theme.mono(11.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassPanel(cornerRadius: 7)
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button {
                showPalette = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "command").font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text("Command Palette").font(Theme.mono(11.5))
                    Text("⌘K")
                        .font(Theme.mono(9.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassPanel(cornerRadius: 7)
            .keyboardShortcut("k", modifiers: [.command])
            .help("Open Command Palette (⌘K)")

            if errorFlash {
                Text("⚠ tool call failed").font(Theme.mono(11.5)).foregroundStyle(Theme.critical)
                    .transition(.opacity)
            }

            Spacer()

            // Alerts notification bell
            Button {
                showAlerts.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activeAlerts.isEmpty ? "bell" : "bell.badge.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(activeAlerts.isEmpty ? Theme.ink3 : Theme.critical)
                        .shadow(color: activeAlerts.isEmpty ? Color.clear : Theme.critical.opacity(0.7), radius: activeAlerts.isEmpty ? 0 : 6)

                    if !activeAlerts.isEmpty {
                        Circle()
                            .fill(Theme.critical)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .padding(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAlerts, arrowEdge: .bottom) {
                alertsDropdown
            }
            .help(activeAlerts.isEmpty ? "No active alerts" : "\(activeAlerts.count) system alert(s)")

            // Burn Rate with projection tooltip
            let dailyEstimate = store.burnRatePerMin * 60 * 24
            HStack(spacing: 6) {
                Circle().fill(Theme.warning).frame(width: 5, height: 5)
                    .shadow(color: Theme.warning.opacity(0.8), radius: 3)
                Text(Formatters.usd(store.burnRatePerMin) + "/min burning")
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.warning)
            }
            .help("At this rate: \(Formatters.usd(dailyEstimate))/day")
            .reportFrame("__ticker__")

            Text(now.formatted(date: .omitted, time: .standard))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink2)
                .monospacedDigit()
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .onReceive(clockTimer) { now = $0 }
        .onChange(of: store.lastErrorAt) { _, newValue in
            guard let newValue, newValue.timeIntervalSinceNow > -4 else { return }
            withAnimation { errorFlash = true }
            CockpitAudio.playAlert()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { errorFlash = false }
            }
        }
    }

    private var alertsDropdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SYSTEM ALERTS")
                    .font(Theme.display(10, weight: .bold))
                    .foregroundStyle(Theme.ink1)
                Spacer()
                Text("\(activeAlerts.count) ACTIVE")
                    .font(Theme.mono(9, weight: .bold))
                    .foregroundStyle(activeAlerts.isEmpty ? Theme.good : Theme.critical)
            }

            Divider().background(Theme.hairline2)

            if activeAlerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.good)
                    Text("All systems nominal · Zero warnings")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeAlerts) { alert in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: alert.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(alert.severity == .critical ? Theme.critical : Theme.warning)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title)
                                    .font(Theme.mono(11, weight: .bold))
                                    .foregroundStyle(Theme.ink1)
                                Text(alert.detail)
                                    .font(Theme.ui(10.5))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.panel)
    }
}

struct SystemAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity

    enum Severity {
        case warning, critical
    }
}


// MARK: - Stat row

private struct StatRow: View {
    @Environment(DashboardStore.self) private var store
    @Environment(DiskScanner.self) private var diskScanner
    @Environment(ActionCenter.self) private var actions

    var body: some View {
        HStack(spacing: 14) {
            StatTile(
                label: "Last 24h spend",
                value: Formatters.usd(store.last24hSpend),
                delta: "live · cost engine",
                deltaColor: Theme.ink3
            )
            StatTile(
                label: "Active sessions",
                value: "\(store.activeCount)",
                delta: "\(store.sessions.count) tracked total",
                deltaColor: Theme.ink3
            )
            StatTile(
                label: "Avg burn rate",
                value: Formatters.usd(store.burnRatePerMin) + "/min",
                delta: "last 2 min",
                deltaColor: Theme.ink3
            )
            StatTile(
                label: "Context alerts",
                value: "\(store.contextAlertCount)",
                delta: store.contextAlertCount > 0 ? "over 70% full" : "all clear",
                deltaColor: store.contextAlertCount > 0 ? Theme.warning : Theme.good
            )
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let delta: String
    let deltaColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.mono(10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.ui(33, weight: .bold))
                .tracking(-0.3)
            Text(delta)
                .font(Theme.ui(12))
                .foregroundStyle(deltaColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 10)
    }
}
