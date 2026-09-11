import SwiftUI
import AppKit

struct DashboardView: View {
    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case cleanup = "Cleanup"
        case processes = "Processes"
        case ports = "Ports"
        case activity = "Activity"
        case files = "Files"
        case sessions = "Sessions"
        case mcp = "MCP Hub"
        case spend = "Spend"
    }

    @Environment(DashboardStore.self) private var store
    @Environment(DiskScanner.self) private var diskScanner
    @Environment(ActionCenter.self) private var actions
    @Environment(FileBrowser.self) private var browser
    @Environment(ProcessMonitor.self) private var processMonitor
    @State private var showGraph = false
    @State private var showPalette = false
    @State private var tab: Tab = .overview
    private final class FrameBox {
        var map: [String: CGRect] = [:]
    }
    @State private var frameBox = FrameBox()
    @State private var particles: [FountainParticle] = []
    @State private var editing: FileEditTarget?
    @State private var processActionTarget: ProcessUsage?
    enum FilesSubMode: String, CaseIterable {
        case files = "Disk Space"
        case duplicates = "Duplicates"
        case uninstaller = "Uninstaller"

        var icon: String {
            switch self {
            case .files: return "folder.fill"
            case .duplicates: return "doc.on.doc.fill"
            case .uninstaller: return "trash.fill"
            }
        }
    }

    @State private var filesSubMode: FilesSubMode = .files
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
            if let session = store.inspectedSession {
                SessionDetailModal(session: session, onDismiss: { store.inspectedSession = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: processActionTarget?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedVitalCategory?.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: store.inspectedSession?.id)
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

            if tab == .sessions || tab == .mcp {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    tabContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coordinateSpace(name: "dashboard")
                        .overlay(EmitterTrailOverlay(particles: particles, color: Theme.accent).allowsHitTesting(false))
                        .onPreferenceChange(FramePreferenceKey.self) { newFrames in
                            frameBox.map = newFrames
                        }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 28, trailing: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ambientGround)
        .foregroundStyle(Theme.ink1)
        .onChange(of: store.costEvents.count) { _, _ in spawnParticle() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .overview:
            VStack(alignment: .leading, spacing: 18) {
                CockpitHubView()
                StatRow()
                SessionBoard()
            }
        case .cleanup:
            DevCleanerPanel()
        case .processes:
            ProcessMonitorPanel(actionTarget: $processActionTarget)
        case .ports:
            PortHunterPanel()
        case .activity:
            VStack(spacing: 14) {
                UsageGraphPanel()
                SystemVitalsStrip(selectedCategory: $selectedVitalCategory)
                ActivityWatcherPanel()
                ActivityFeedPanel()
            }
        case .files:
            VStack(spacing: 14) {
                // Sub-mode segmented selector
                HStack(spacing: 4) {
                    ForEach(FilesSubMode.allCases, id: \.self) { subMode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                filesSubMode = subMode
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: subMode.icon)
                                    .font(.system(size: 11))
                                Text(subMode.rawValue)
                                    .font(Theme.ui(11.5, weight: filesSubMode == subMode ? .semibold : .regular))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(filesSubMode == subMode ? Theme.accent.opacity(0.18) : Color.white.opacity(0.03))
                            .foregroundStyle(filesSubMode == subMode ? Theme.accent : Theme.ink2)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(3)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                switch filesSubMode {
                case .files:
                    HStack(alignment: .top, spacing: 14) {
                        FilesPanel(editing: $editing)
                            .frame(maxWidth: .infinity)
                        DiskRadarPanel()
                            .frame(width: 500)
                    }
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
                case .duplicates:
                    DuplicateHunterPanel()
                        .frame(minHeight: 640)
                case .uninstaller:
                    AppUninstallerPanel()
                        .frame(minHeight: 640)
                }
            }
        case .sessions:
            SessionsTelemetryPanel()
        case .mcp:
            MCPHubPanel()
        case .spend:
            SpendByProjectPanel()
        }
    }

    private func spawnParticle() {
        guard let event = store.costEvents.last,
              let end = frameBox.map["__ticker__"] else { return }
        guard let start = frameBox.map[event.sessionId] ?? frameBox.map["__board__"] else { return }
        particles.append(FountainParticle(
            start: CGPoint(x: start.midX, y: start.midY),
            end: CGPoint(x: end.midX, y: end.midY),
            spawnedAt: Date()
        ))
        let cutoff = Date().addingTimeInterval(-1.2)
        particles.removeAll { $0.spawnedAt < cutoff }
    }

    /// Calm, subtle dark backdrop with single cyan ambient tint.
    private var ambientGround: some View {
        ZStack {
            Theme.page
            RadialGradient(
                colors: [Theme.accent.opacity(0.04), Theme.page.opacity(0)],
                center: .init(x: 0.1, y: 0.0),
                startRadius: 0,
                endRadius: 600
            )
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

            // Spend so far today. Claude Code reports cumulative session cost, not a
            // rate — anything per-minute here would be invented, so it is not shown.
            if store.todaySpend > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Theme.warning).frame(width: 5, height: 5)
                        .shadow(color: Theme.warning.opacity(0.8), radius: 3)
                    Text((store.todaySpendIsExact ? "" : "≤ ") + Formatters.usd(store.todaySpend) + " today")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.warning)
                }
                .help(store.todaySpendIsExact
                      ? "Spend attributed to today from Claude Code's own cost checkpoints"
                      : "Upper bound — a session was already running before midnight, so part of this may be yesterday's spend")
                .reportFrame("__ticker__")
            }

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
                label: "Today's spend",
                value: (store.todaySpendIsExact ? "" : "≤ ") + Formatters.usd(store.todaySpend),
                delta: store.todaySpendIsExact ? "since midnight" : "upper bound",
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
        .glassPanel(cornerRadius: 10, accent: Theme.accent)
    }
}
