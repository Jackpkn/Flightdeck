import SwiftUI
import AppKit

/// Comprehensive Model Context Protocol (MCP) Health & Tool Hub.
/// Monitors active MCP server daemon processes, configured tools, sockets, and resource footprints.
struct MCPHubPanel: View {
    @Environment(MCPServerScanner.self) private var scanner

    @State private var selectedServerId: String? = nil
    @State private var searchQuery: String = ""
    @State private var selectedFilter: ServerFilter = .all
    @State private var copiedCommand = false

    enum ServerFilter: String, CaseIterable {
        case all = "ALL SERVERS"
        case running = "RUNNING"
        case configured = "CONFIGURED"
    }

    private var allServers: [MCPServerItem] {
        scanner.servers
    }

    private var filteredServers: [MCPServerItem] {
        allServers.filter { s in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .running: matchesFilter = s.isRunning
            case .configured: matchesFilter = s.status == .configured
            }

            guard matchesFilter else { return false }
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            let q = searchQuery.lowercased()
            return s.name.lowercased().contains(q) ||
                   s.command.lowercased().contains(q) ||
                   s.source.rawValue.lowercased().contains(q) ||
                   s.toolsExposed.contains { $0.lowercased().contains(q) }
        }
    }

    private var currentServer: MCPServerItem? {
        if let id = selectedServerId, let match = allServers.first(where: { $0.id == id }) {
            return match
        }
        return filteredServers.first ?? allServers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            kpiRibbon
            masterDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            scanner.refresh()
            if selectedServerId == nil {
                selectedServerId = allServers.first?.id
            }
        }
    }

    // MARK: - Top KPI Ribbon

    private var kpiRibbon: some View {
        HStack(spacing: 12) {
            // 1. Running Daemons
            let runningCount = allServers.filter(\.isRunning).count
            kpiCard(
                title: "ACTIVE MCP PROCESSES",
                value: "\(runningCount)",
                subtitle: "\(allServers.count) total registered",
                accent: Theme.good
            )

            // 2. Tools Exposed
            let totalTools = allServers.reduce(0) { $0 + $1.toolsExposed.count }
            kpiCard(
                title: "TOOLS EXPOSED",
                value: "\(totalTools)",
                subtitle: "available to AI agents",
                accent: Theme.accent
            )

            // 3. Memory Footprint
            let totalBytes = allServers.reduce(Int64(0)) { $0 + $1.memoryBytes }
            kpiCard(
                title: "TOTAL MEMORY",
                value: Formatters.bytes(totalBytes),
                subtitle: "RSS across active daemons",
                accent: Theme.claudeColor
            )

            // 4. Host Environments
            let hosts = Set(allServers.map(\.source.rawValue)).count
            kpiCard(
                title: "CLIENT HOSTS",
                value: "\(hosts)",
                subtitle: "Claude, Codex, Workspaces",
                accent: Theme.accentSecondary
            )
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

    private var masterDetail: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Pane: Server List
            serverListPane
                .frame(width: 380)
                .frame(maxHeight: .infinity)

            // Right Pane: Deep Inspector
            serverInspectorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Pane: Server List

    private var serverListPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                TextField("Search MCP servers, tools, commands...", text: $searchQuery)
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
            HStack(spacing: 6) {
                ForEach(ServerFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(Theme.mono(9.5, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? Theme.ink1 : Theme.ink3)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                selectedFilter == filter ? Theme.accent.opacity(0.2) : Color.white.opacity(0.03),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(selectedFilter == filter ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                // Refresh Button
                Button {
                    CockpitAudio.playPing()
                    scanner.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }

            // List
            if filteredServers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.ink3)
                    Text("No MCP servers found")
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 10, accent: Theme.accent)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredServers) { s in
                            serverListItem(s)
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

    private func serverListItem(_ s: MCPServerItem) -> some View {
        let isSelected = currentServer?.id == s.id

        return Button {
            CockpitAudio.playPing()
            selectedServerId = s.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(s.isRunning ? Theme.good : Theme.accent.opacity(0.7))
                        .frame(width: 7, height: 7)

                    Text(s.name)
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.ink1 : Theme.ink2)
                        .lineLimit(1)

                    Spacer()

                    Text(s.source.rawValue)
                        .font(Theme.mono(8.5, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.04), in: Capsule())
                }

                HStack {
                    if let pid = s.pid {
                        Text("PID \(pid)")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                        Text("· \(String(format: "%.1f%%", s.cpuPercent)) CPU")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                        Text("· \(Formatters.bytes(s.memoryBytes))")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                    } else {
                        Text("Configured")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                    }

                    Spacer()

                    if !s.toolsExposed.isEmpty {
                        Text("\(s.toolsExposed.count) tools")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.claudeColor)
                    }
                }
            }
            .padding(10)
            .background(
                isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.hairline2, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Pane: Deep Inspector

    private var serverInspectorPane: some View {
        Group {
            if let s = currentServer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        inspectorHeader(s)
                        actionButtons(s)
                        resourceHeroGrid(s)

                        if let sock = s.socketOrPipePath, !sock.isEmpty {
                            socketCard(sock)
                        }

                        commandCard(s)

                        if !s.toolsExposed.isEmpty {
                            toolsCatalogueCard(s)
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 12, accent: Theme.accent)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.ink3)
                    Text("Select an MCP server to inspect health and tools")
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

    private func inspectorHeader(_ s: MCPServerItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)

                Text(s.name)
                    .font(Theme.ui(18, weight: .bold))
                    .foregroundStyle(Theme.ink1)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(s.isRunning ? Theme.good : Theme.accent)
                        .frame(width: 6, height: 6)
                    Text(s.status.rawValue)
                        .font(Theme.mono(10, weight: .bold))
                }
                .foregroundStyle(s.isRunning ? Theme.good : Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((s.isRunning ? Theme.good : Theme.accent).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 8) {
                Text("HOST: \(s.source.rawValue.uppercased())")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.04), in: Capsule())

                if !s.uptime.isEmpty {
                    Text("UPTIME: \(s.uptime)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private func actionButtons(_ s: MCPServerItem) -> some View {
        HStack(spacing: 10) {
            if let pid = s.pid {
                Button {
                    CockpitAudio.playPing()
                    scanner.stopServer(pid: pid)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.circle.fill")
                        Text("STOP PROCESS")
                    }
                    .font(Theme.mono(10.5, weight: .bold))
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.critical.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.critical.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s.command, forType: .string)
                CockpitAudio.playPing()
                copiedCommand = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedCommand = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                    Text(copiedCommand ? "COPIED" : "COPY COMMAND")
                }
                .font(Theme.mono(10.5))
                .foregroundStyle(copiedCommand ? Theme.good : Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func resourceHeroGrid(_ s: MCPServerItem) -> some View {
        HStack(spacing: 12) {
            // Memory
            VStack(alignment: .leading, spacing: 4) {
                Text("RAM USAGE")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                Text(s.isRunning ? Formatters.bytes(s.memoryBytes) : "—")
                    .font(Theme.mono(20, weight: .bold))
                    .foregroundStyle(Theme.ink1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // CPU Load
            VStack(alignment: .leading, spacing: 4) {
                Text("CPU LOAD")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                Text(s.isRunning ? String(format: "%.1f%%", s.cpuPercent) : "—")
                    .font(Theme.mono(20, weight: .bold))
                    .foregroundStyle(s.cpuPercent > 10 ? Theme.warning : Theme.good)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // Process ID
            VStack(alignment: .leading, spacing: 4) {
                Text("PROCESS ID")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                Text(s.pid != nil ? "\(s.pid!)" : "Static")
                    .font(Theme.mono(20, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func socketCard(_ sock: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text("UNIX DOMAIN SOCKET / IPC PIPE")
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }

            Text(sock)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.accent)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    private func commandCard(_ s: MCPServerItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAUNCH INVOCATION & COMMAND LINE")
                .font(Theme.mono(9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)

            Text(s.command)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.ink2)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    private func toolsCatalogueCard(_ s: MCPServerItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPOSED TOOLS CATALOGUE (\(s.toolsExposed.count))")
                    .font(Theme.mono(9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(s.toolsExposed, id: \.self) { tool in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.claudeColor).frame(width: 5, height: 5)
                        Text(tool)
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.ink1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }
}
