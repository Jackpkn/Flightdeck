import SwiftUI
import AppKit

/// Comprehensive Claude Code Mission Control & Telemetry Panel.
/// Provides a searchable master-detail cockpit displaying real-time session titles (aiTitle),
/// execution modes (plan vs normal), code velocity (+/- lines), latency split (API vs Tools),
/// detailed token breakdowns, and connected MCP servers.
struct SessionsTelemetryPanel: View {
    @Environment(DashboardStore.self) private var store

    @State private var selectedSessionId: String? = nil
    @State private var searchQuery: String = ""
    @State private var selectedFilter: SessionFilter = .all
    @State private var copiedId = false

    enum InspectorTab: String, CaseIterable {
        case metrics = "METRICS & TELEMETRY"
        case turns = "CONVERSATION TURNS"
    }

    @State private var inspectorTab: InspectorTab = .metrics
    @State private var loadedTurns: [ConversationTurn] = []
    @State private var isLoadingTurns: Bool = false

    enum SessionFilter: String, CaseIterable {
        case all = "ALL SESSIONS"
        case active = "ACTIVE"
        case planMode = "PLAN MODE"
        case highContext = "HIGH CONTEXT (>70%)"
    }

    private var allSessions: [SessionAgg] {
        store.activeSessions
    }

    private var filteredSessions: [SessionAgg] {
        allSessions.filter { session in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = session.isActive
            case .planMode:
                matchesFilter = session.mode.lowercased() == "plan"
            case .highContext:
                matchesFilter = session.contextFraction > 0.7
            }

            guard matchesFilter else { return false }
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            let q = searchQuery.lowercased()
            return session.project.lowercased().contains(q)
                || session.aiTitle.lowercased().contains(q)
                || session.displayModel.lowercased().contains(q)
                || session.branch.lowercased().contains(q)
                || session.lastPrompt.lowercased().contains(q)
                || session.id.lowercased().contains(q)
        }
    }

    private var currentSession: SessionAgg? {
        if let id = selectedSessionId, let match = allSessions.first(where: { $0.id == id }) {
            return match
        }
        return filteredSessions.first ?? allSessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            kpiRibbon
            mainMasterDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedSessionId == nil {
                selectedSessionId = allSessions.first?.id
            }
            if let id = currentSession?.id {
                fetchTranscript(sessionId: id)
            }
        }
        .onChange(of: currentSession?.id) { _, newId in
            if let newId {
                fetchTranscript(sessionId: newId)
            }
        }
    }

    // MARK: - Top KPI Ribbon

    private var kpiRibbon: some View {
        HStack(spacing: 12) {
            // 1. Total Sessions
            kpiCard(
                title: "TOTAL SESSIONS",
                value: "\(allSessions.count)",
                subtitle: "\(store.activeCount) active · \(allSessions.count - store.activeCount) idle",
                accent: Theme.accent
            )

            // 2. Global Spend
            kpiCard(
                title: "GLOBAL SPEND (USD)",
                value: Formatters.usd(allSessions.reduce(0) { $0 + $1.totalCost }),
                subtitle: "live across all projects",
                accent: Theme.good
            )

            // 3. Tokens Consumed
            let totalTokens = allSessions.reduce(0) { $0 + $1.totalTokens }
            kpiCard(
                title: "TOTAL TOKENS",
                value: Formatters.tokens(totalTokens),
                subtitle: "input, output, think, cache",
                accent: Theme.claudeColor
            )

            // 4. Code Velocity or Tracked Projects
            let netLinesAdded = allSessions.reduce(0) { $0 + $1.linesAdded }
            let netLinesRemoved = allSessions.reduce(0) { $0 + $1.linesRemoved }
            if netLinesAdded > 0 || netLinesRemoved > 0 {
                kpiCard(
                    title: "CODE VELOCITY",
                    value: "+\(netLinesAdded) / -\(netLinesRemoved)",
                    subtitle: "lines of code impacted",
                    accent: Theme.accentSecondary
                )
            } else {
                let projectCount = Set(allSessions.map { $0.project }).count
                kpiCard(
                    title: "TRACKED PROJECTS",
                    value: "\(projectCount)",
                    subtitle: "across all local workspaces",
                    accent: Theme.accentSecondary
                )
            }
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.mono(9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.mono(18, weight: .bold))
                .foregroundStyle(Theme.ink1)
            Text(subtitle)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Master Detail Layout

    private var mainMasterDetail: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Pane: Session List
            sessionListPane
                .frame(width: 380)
                .frame(maxHeight: .infinity)

            // Right Pane: Telemetry Inspector
            sessionInspectorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Pane (Session List)

    private var sessionListPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                TextField("Search sessions, titles, models...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(12))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline, lineWidth: 1))

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SessionFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(Theme.mono(9.5, weight: .semibold))
                                .foregroundStyle(selectedFilter == filter ? Theme.ink1 : Theme.ink3)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selectedFilter == filter ? Theme.accent.opacity(0.2) : Color.white.opacity(0.03),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(selectedFilter == filter ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // List of Sessions
            if filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.ink3)
                    Text("No matching Claude Code sessions")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 10, accent: Theme.accent)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSessions) { session in
                            sessionListItem(session)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: 12, accent: Theme.accent)
    }

    private func sessionListItem(_ session: SessionAgg) -> some View {
        let isSelected = currentSession?.id == session.id
        let projectColor = Theme.colorForProject(session.project)

        return Button {
            CockpitAudio.playPing()
            selectedSessionId = session.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Project + AI Title
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(projectColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayTitle)
                            .font(Theme.ui(13, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.ink1 : Theme.ink2)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(session.project)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.ink3)
                            if !session.branch.isEmpty {
                                Text("· ⎇ \(session.branch)")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                    }

                    Spacer()

                    if session.mode.lowercased() == "plan" {
                        Text("PLAN")
                            .font(Theme.mono(8.5, weight: .bold))
                            .foregroundStyle(Color.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.16), in: Capsule())
                    } else if session.permissionMode.lowercased() == "auto" {
                        Text("AUTO")
                            .font(Theme.mono(8.5, weight: .bold))
                            .foregroundStyle(Theme.good)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.good.opacity(0.16), in: Capsule())
                    }

                    Circle()
                        .fill(session.isActive ? Theme.good : Theme.ink3.opacity(0.5))
                        .frame(width: 6, height: 6)
                }

                // Model + Tokens + Cost
                HStack {
                    Text(session.displayModel)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.claudeColor)
                        .lineLimit(1)

                    Spacer()

                    if session.totalTokens > 0 {
                        Text("\(Formatters.tokens(session.totalTokens)) tok")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                    }

                    Text(Formatters.usd(session.totalCost))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.good)
                }

                // Mini Context Bar
                if session.contextTokens > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule()
                                .fill(session.contextFraction > 0.7 ? Theme.warning : Theme.claudeColor)
                                .frame(width: max(2, geo.size.width * CGFloat(session.contextFraction)))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(10)
            .background(
                isSelected ? projectColor.opacity(0.1) : Color.white.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? projectColor.opacity(0.6) : Theme.hairline2, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Pane (Deep Telemetry Inspector)

    private var sessionInspectorPane: some View {
        Group {
            if let session = currentSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        inspectorHeader(session)
                        actionButtonsBar(session)

                        // Mode switcher between metrics and transcript turns
                        HStack(spacing: 8) {
                            ForEach(InspectorTab.allCases, id: \.self) { tab in
                                Button {
                                    inspectorTab = tab
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: tab == .metrics ? "chart.xyaxis.line" : "bubble.left.and.bubble.right.fill")
                                            .font(.system(size: 9.5))
                                        Text(tab.rawValue)
                                            .font(Theme.mono(10, weight: .semibold))
                                    }
                                    .foregroundStyle(inspectorTab == tab ? Theme.ink1 : Theme.ink3)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(
                                        inspectorTab == tab ? Theme.accent.opacity(0.18) : Color.white.opacity(0.02),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(inspectorTab == tab ? Theme.accent.opacity(0.5) : Theme.hairline2, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }

                        if inspectorTab == .metrics {
                            inspectorHeroGrid(session)
                            tokenTelemetryCard(session)
                            if session.apiDurationMs > 0 || session.toolDurationMs > 0 {
                                latencySplitCard(session)
                            }
                            if !session.lastPrompt.isEmpty {
                                lastPromptCard(session)
                            }
                            if !session.prUrl.isEmpty {
                                pullRequestCard(session)
                            }
                            if !session.modelUsages.isEmpty {
                                modelsUtilizedCard(session)
                            }
                            if !session.mcpServers.isEmpty {
                                mcpServersCard(session)
                            }
                            contextAndEnvCard(session)
                        } else {
                            SessionTranscriptView(
                                session: session,
                                turns: loadedTurns,
                                isLoading: isLoadingTurns
                            )
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 12, accent: Theme.colorForProject(session.project))
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.ink3)
                    Text("Select a session to inspect detailed telemetry")
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 12, accent: Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector Sub-Components

    private func inspectorHeader(_ session: SessionAgg) -> some View {
        let color = Theme.colorForProject(session.project)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                Text(session.displayTitle)
                    .font(Theme.ui(18, weight: .bold))
                    .foregroundStyle(Theme.ink1)
                Spacer()
                StatusPill(active: session.isActive)
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(session.displayModel)
                        .font(Theme.mono(11, weight: .semibold))
                }
                .foregroundStyle(Theme.claudeColor)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.claudeColor.opacity(0.12), in: Capsule())

                if !session.mode.isEmpty {
                    Text("MODE: \(session.mode.uppercased())")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Color.purple)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }

                if !session.permissionMode.isEmpty {
                    Text("APPROVAL: \(session.permissionMode.uppercased())")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }

                if !session.versionBase.isEmpty {
                    Text("CLAUDE v\(session.versionBase)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private func actionButtonsBar(_ session: SessionAgg) -> some View {
        HStack(spacing: 10) {
            // 1. One-Click Resume in Terminal (Primary Action)
            Button {
                resumeSessionInTerminal(session)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("RESUME SESSION")
                }
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.good, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // 2. Start New Session in Project
            Button {
                launchNewSessionInTerminal(session)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                    Text("NEW SESSION")
                }
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // 3. Copy Session ID / Path
            Button {
                let toCopy = session.id.hasPrefix("proj-") ? (session.cwd.isEmpty ? session.id : session.cwd) : session.id
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(toCopy, forType: .string)
                CockpitAudio.playPing()
                copiedId = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedId = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedId ? "checkmark" : "doc.on.doc")
                    if session.id.hasPrefix("proj-") {
                        Text(copiedId ? "COPIED PATH" : "PROJECT WORKSPACE")
                    } else {
                        Text(copiedId ? "COPIED" : "UUID: \(session.id.prefix(8))...")
                    }
                }
                .font(Theme.mono(10.5))
                .foregroundStyle(copiedId ? Theme.good : Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // 4. Open Folder in Finder
            if !session.cwd.isEmpty {
                Button {
                    let url = URL(fileURLWithPath: session.cwd)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text("REVEAL FOLDER")
                    }
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private func resumeSessionInTerminal(_ session: SessionAgg) {
        CockpitAudio.playPing()
        let cwd = session.cwd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : session.cwd
        let cmd: String
        if session.id.hasPrefix("proj-") || session.id.isEmpty {
            cmd = "cd \"\(cwd)\" && claude"
        } else {
            cmd = "cd \"\(cwd)\" && claude --resume \(session.id)"
        }
        executeTerminalCommand(cmd)
    }

    private func launchNewSessionInTerminal(_ session: SessionAgg) {
        CockpitAudio.playPing()
        let cwd = session.cwd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : session.cwd
        executeTerminalCommand("cd \"\(cwd)\" && claude")
    }

    private func executeTerminalCommand(_ cmd: String) {
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
        }
    }

    private func fetchTranscript(sessionId: String) {
        guard !sessionId.isEmpty else {
            loadedTurns = []
            return
        }
        isLoadingTurns = true
        Task {
            let turns = await store.loadTranscript(for: sessionId)
            await MainActor.run {
                if selectedSessionId == sessionId || currentSession?.id == sessionId {
                    self.loadedTurns = turns
                    self.isLoadingTurns = false
                }
            }
        }
    }

    private func inspectorHeroGrid(_ session: SessionAgg) -> some View {
        HStack(spacing: 12) {
            // Spend
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION SPEND")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                Text(Formatters.usd(session.totalCost))
                    .font(Theme.mono(22, weight: .bold))
                    .foregroundStyle(Theme.good)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // Burn Rate
            VStack(alignment: .leading, spacing: 4) {
                Text("BURN RATE")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                if session.burnRatePerMin > 0 {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(Formatters.usd(session.burnRatePerMin))
                            .font(Theme.mono(22, weight: .bold))
                            .foregroundStyle(Theme.ink1)
                        Text("/min")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.ink3)
                    }
                } else {
                    Text(session.isActive ? "measuring..." : "idle")
                        .font(Theme.mono(18, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // Code Velocity
            VStack(alignment: .leading, spacing: 4) {
                Text("CODE IMPACT")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                if session.linesAdded > 0 || session.linesRemoved > 0 {
                    HStack(spacing: 6) {
                        Text("+\(session.linesAdded)")
                            .font(Theme.mono(18, weight: .bold))
                            .foregroundStyle(Theme.good)
                        Text("-\(session.linesRemoved)")
                            .font(Theme.mono(18, weight: .bold))
                            .foregroundStyle(Theme.critical)
                    }
                } else {
                    Text("none")
                        .font(Theme.mono(18, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func tokenTelemetryCard(_ session: SessionAgg) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TOKEN CONSUMPTION DEEP-DIVE")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if session.cacheHitRatio > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 9))
                        Text("\(Int(session.cacheHitRatio * 100))% CACHE HIT")
                            .font(Theme.mono(10, weight: .bold))
                    }
                    .foregroundStyle(Theme.good)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.good.opacity(0.12), in: Capsule())
                }
            }

            if session.totalTokens > 0 {
                // Proportional Token Bar
                GeometryReader { proxy in
                    let total = max(1, Double(session.totalTokens))
                    let inW = (Double(session.inputTokens) / total) * proxy.size.width
                    let outW = (Double(session.outputTokens) / total) * proxy.size.width
                    let thinkW = (Double(session.thinkingTokens) / total) * proxy.size.width
                    let readW = (Double(session.cacheReadTokens) / total) * proxy.size.width
                    let createW = (Double(session.cacheCreationTokens) / total) * proxy.size.width

                    HStack(spacing: 2) {
                        if inW > 0 { Rectangle().fill(Color.blue).frame(width: max(2, inW)) }
                        if outW > 0 { Rectangle().fill(Color.purple).frame(width: max(2, outW)) }
                        if thinkW > 0 { Rectangle().fill(Color.pink).frame(width: max(2, thinkW)) }
                        if readW > 0 { Rectangle().fill(Color.teal).frame(width: max(2, readW)) }
                        if createW > 0 { Rectangle().fill(Color.orange).frame(width: max(2, createW)) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 7)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tokenGridCell(title: "INPUT TOKENS", value: session.inputTokens, color: Color.blue)
                    tokenGridCell(title: "OUTPUT TOKENS", value: session.outputTokens, color: Color.purple)
                    tokenGridCell(title: "THINKING TOKENS", value: session.thinkingTokens, color: Color.pink)
                    tokenGridCell(title: "CACHE READ", value: session.cacheReadTokens, color: Color.teal)
                    tokenGridCell(title: "CACHE WRITE", value: session.cacheCreationTokens, color: Color.orange)
                    tokenGridCell(title: "TOTAL TOKENS", value: session.totalTokens, color: Theme.accent)
                }
            } else {
                Text("No token consumption telemetry recorded for this session.")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    private func tokenGridCell(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(title)
                    .font(Theme.mono(9, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            }
            Text(Formatters.tokens(value))
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
    }

    // MARK: - Latency Split Card

    private func latencySplitCard(_ session: SessionAgg) -> some View {
        let apiSec = Double(session.apiDurationMs) / 1000.0
        let toolSec = Double(session.toolDurationMs) / 1000.0
        let total = max(0.1, apiSec + toolSec)
        let apiPct = Int((apiSec / total) * 100)
        let toolPct = 100 - apiPct

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXECUTION LATENCY SPLIT")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Text("Total: \(String(format: "%.1fs", total))")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.claudeColor)
                        .frame(width: max(4, geo.size.width * CGFloat(apiSec / total)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accentSecondary)
                }
            }
            .frame(height: 7)

            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Theme.claudeColor).frame(width: 6, height: 6)
                    Text("AI Reasoning Time: \(String(format: "%.1fs", apiSec)) (\(apiPct)%)")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Theme.accentSecondary).frame(width: 6, height: 6)
                    Text("Tool Execution Time: \(String(format: "%.1fs", toolSec)) (\(toolPct)%)")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Last Prompt Card

    private func lastPromptCard(_ session: SessionAgg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text("LAST USER INSTRUCTION")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }

            Text(session.lastPrompt)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.ink1)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Pull Request Card

    private func pullRequestCard(_ session: SessionAgg) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("GITHUB PULL REQUEST #\(session.prNumber ?? 1)")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.ink1)
                Text(session.prRepository.isEmpty ? session.prUrl : session.prRepository)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            }

            Spacer()

            if let url = URL(string: session.prUrl) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 4) {
                        Text("VIEW ON GITHUB")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Models Utilized Card

    private func modelsUtilizedCard(_ session: SessionAgg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PER-MODEL UTILIZATION")
                .font(Theme.mono(10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.ink3)

            VStack(spacing: 6) {
                ForEach(session.modelUsages.keys.sorted(), id: \.self) { modelKey in
                    if let usage = session.modelUsages[modelKey] {
                        HStack(spacing: 8) {
                            Text(modelKey)
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.ink1)
                            Spacer()
                            Text("\(Formatters.tokens(usage.totalTokens)) tokens")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.ink2)
                            if usage.costUSD > 0 {
                                Text(Formatters.usd(usage.costUSD))
                                    .font(Theme.mono(11, weight: .semibold))
                                    .foregroundStyle(Theme.good)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Connected MCP Servers

    private func mcpServersCard(_ session: SessionAgg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text("CONNECTED MCP SERVERS (\(session.mcpServers.count))")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
            }

            HStack(spacing: 8) {
                ForEach(session.mcpServers, id: \.self) { server in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(server)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Context & Environment Card

    private func contextAndEnvCard(_ session: SessionAgg) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONTEXT WINDOW & ENVIRONMENT")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
            if session.contextTokens > 0 {
                Text("\(Formatters.tokens(session.contextTokens)) / \(Formatters.tokens(session.contextTotalTokens)) · \(Int(session.contextFraction * 100))%")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(session.contextFraction > 0.7 ? Theme.warning : Theme.claudeColor)
            }
        }

        if session.contextTokens > 0 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(session.contextFraction > 0.7 ? Theme.warning : Theme.claudeColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(session.contextFraction)))
                }
            }
            .frame(height: 7)
        }

            Divider().background(Theme.hairline2)

            HStack(spacing: 16) {
                if !session.lastFile.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(URL(fileURLWithPath: session.lastFile).lastPathComponent)
                    }
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink2)
                }

                if session.toolUseCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                        Text("\(session.toolUseCount) actions executed")
                    }
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
                }

                Spacer()

                if let seen = session.lastSeen {
                    Text("Last active \(seen.formatted(date: .omitted, time: .standard))")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Subviews

private struct StatusPill: View {
    let active: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Theme.good : Theme.ink3)
                .frame(width: 6, height: 6)
                .shadow(color: active ? Theme.good.opacity(0.85) : .clear, radius: 4)
            Text(active ? "ACTIVE" : "IDLE")
                .font(Theme.mono(10, weight: .semibold))
        }
        .foregroundStyle(active ? Theme.good : Theme.ink3)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((active ? Theme.good : Color.white).opacity(active ? 0.13 : 0.05), in: Capsule())
    }
}
