import SwiftUI

struct SpendByProjectPanel: View {
    @Environment(DashboardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SPEND BY PROJECT · 7D").font(Theme.mono(11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                Text(Formatters.usd(store.spendByProject.reduce(0) { $0 + $1.cost }))
                    .font(Theme.mono(11)).foregroundStyle(Theme.ink3)
            }

            if store.spendByProject.isEmpty {
                Text("No spend recorded in the last 7 days.")
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
            } else {
                let maxCost = store.spendByProject.map(\.cost).max() ?? 1
                VStack(spacing: 11) {
                    ForEach(store.spendByProject.prefix(6), id: \.name) { row in
                        BarRow(name: row.name, cost: row.cost, fraction: row.cost / maxCost)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

private struct BarRow: View {
    let name: String
    let cost: Double
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(Theme.ui(12.5)).foregroundStyle(Theme.ink2)
                .frame(width: 104, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.claudeColor.opacity(0.85))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 18)
            Text(Formatters.usd(cost))
                .font(Theme.mono(12)).foregroundStyle(Theme.ink1)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

struct ActivityFeedPanel: View {
    @Environment(DashboardStore.self) private var store
    @State private var query = ""
    @State private var kindFilter: ActivityEntry.Kind?
    @State private var groupBySession = false
    @FocusState private var searchFocused: Bool

    private var filtered: [ActivityEntry] {
        store.activity.filter { entry in
            let matchesKind = kindFilter == nil || entry.kind == kindFilter
            let matchesQuery = query.isEmpty
                || entry.text.localizedCaseInsensitiveContains(query)
                || entry.project.localizedCaseInsensitiveContains(query)
            return matchesKind && matchesQuery
        }
    }

    /// Buckets by session, keeping the order sessions first appear in the feed
    /// so the newest activity stays at the top.
    private var grouped: [(sessionId: String, project: String, entries: [ActivityEntry])] {
        var order: [String] = []
        var buckets: [String: [ActivityEntry]] = [:]
        for entry in filtered {
            if buckets[entry.sessionId] == nil { order.append(entry.sessionId) }
            buckets[entry.sessionId, default: []].append(entry)
        }
        return order.map { id in
            (sessionId: id, project: buckets[id]?.first?.project ?? "", entries: buckets[id] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LiveDot(color: Theme.claudeColor)
                Text("ACTIVITY FEED").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)

                Spacer(minLength: 8)

                inlineSearch
                filterMenu

                Button {
                    groupBySession.toggle()
                } label: {
                    Image(systemName: groupBySession ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                        .font(.system(size: 11))
                        .foregroundStyle(groupBySession ? Theme.claudeColor : Theme.ink3)
                }
                .buttonStyle(.plain)
                .help(groupBySession ? "Ungroup" : "Group by session")
            }

            if filtered.isEmpty {
                Spacer(minLength: 0)
                Text(store.activity.isEmpty
                     ? "Waiting for tool activity from live sessions…"
                     : "No entries match this filter.")
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
                    .padding(.vertical, 6)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if groupBySession {
                            ForEach(grouped, id: \.sessionId) { group in
                                SessionGroupHeader(
                                    project: group.project,
                                    sessionId: group.sessionId,
                                    count: group.entries.count
                                )
                                ForEach(group.entries) { entry in
                                    LogRow(entry: entry, showProject: false)
                                    Divider().background(Theme.hairline2)
                                }
                            }
                        } else {
                            ForEach(filtered.prefix(80)) { entry in
                                LogRow(entry: entry, showProject: true)
                                Divider().background(Theme.hairline2)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.claudeColor)
        .cornerBracket(color: Theme.claudeColor)
    }

    /// Compact, inline, and only as wide as it needs to be — one row of chrome
    /// in the header instead of a full-width bar plus a chip rail.
    private var inlineSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.ink3)

            TextField("Filter", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink1)
                .focused($searchFocused)
                .frame(width: 108)

            if query.isEmpty {
                Text("⌘F").font(Theme.mono(9)).foregroundStyle(Theme.ink3.opacity(0.7))
            } else {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(searchFocused ? Theme.claudeColor.opacity(0.5) : Theme.hairline2, lineWidth: 1)
        )
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        )
    }

    /// A native menu rather than six always-on chips — same filtering, a
    /// fraction of the visual weight, and it shows the active choice.
    private var filterMenu: some View {
        Menu {
            Button("All") { kindFilter = nil }
            Divider()
            ForEach(ActivityEntry.Kind.allCases, id: \.self) { kind in
                Button(kind.label.capitalized) { kindFilter = kind }
            }
        } label: {
            HStack(spacing: 4) {
                if let kindFilter {
                    Circle().fill(Self.color(for: kindFilter)).frame(width: 6, height: 6)
                }
                Text(kindFilter?.label ?? "ALL")
                    .font(Theme.mono(9.5, weight: .semibold))
                Text("\(filtered.count)")
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3.opacity(0.8))
            }
            .foregroundStyle(kindFilter == nil ? Theme.ink3 : Self.color(for: kindFilter!))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by kind")
    }

    /// Three categorical hues for the real categories, neutral for the generic
    /// shell bucket, and the reserved status red for failures.
    static func color(for kind: ActivityEntry.Kind) -> Color {
        switch kind {
        case .edit:  return Theme.claudeColor
        case .git:   return Theme.cursorColor
        case .build: return Theme.copilotColor
        case .run:   return Theme.ink2
        case .error: return Theme.critical
        }
    }
}

private struct SessionGroupHeader: View {
    let project: String
    let sessionId: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("──")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3.opacity(0.4))

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.colorForProject(project))
                .frame(width: 7, height: 7)

            Text(project.isEmpty ? "default workspace" : project)
                .font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.ink1)

            Text("· SES-\(sessionId.prefix(6).uppercased())")
                .font(Theme.mono(9.5)).foregroundStyle(Theme.accent)

            Text("──")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3.opacity(0.4))

            Spacer()
            Text("\(count) events").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
        }
        .padding(.top, 12).padding(.bottom, 6)
    }
}

private struct LogRow: View {
    let entry: ActivityEntry
    let showProject: Bool

    @State private var isDiffExpanded = false
    @State private var copied = false

    private var isAIAgent: Bool {
        entry.sessionId != "local-terminal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Expand toggle for edits
                if entry.kind == .edit {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isDiffExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isDiffExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 10, height: 10)
                    }
                    .buttonStyle(.plain)
                    .help(isDiffExpanded ? "Collapse diff" : "Expand diff")
                } else {
                    Spacer().frame(width: 10)
                }

                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(Theme.mono(11)).foregroundStyle(Theme.ink3)
                    .frame(width: 62, alignment: .leading)

                // Event Kind Badge
                Text(entry.kind.label)
                    .font(Theme.mono(8.5, weight: .semibold))
                    .foregroundStyle(ActivityFeedPanel.color(for: entry.kind))
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(
                        ActivityFeedPanel.color(for: entry.kind).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                    .frame(width: 46, alignment: .leading)

                // AI Agent Badge (glowing purple)
                if isAIAgent {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 7))
                        Text("AI")
                            .font(Theme.mono(7.5, weight: .black))
                    }
                    .foregroundStyle(Theme.accentSecondary)
                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(Theme.accentSecondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    .shadow(color: Theme.accentSecondary.opacity(0.4), radius: 4)
                }

                if showProject {
                    Text(entry.project)
                        .font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.ink1)
                        .frame(width: 90, alignment: .leading).lineLimit(1)
                }

                Text(entry.text)
                    .font(Theme.mono(11.5)).foregroundStyle(Theme.ink2)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 5)

            // Inline Diff Preview for edit operations
            if entry.kind == .edit && isDiffExpanded {
                diffView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contextMenu {
            if entry.kind == .edit {
                Button("Open File in Editor") {
                    let cleaned = entry.text.replacingOccurrences(of: "edited ", with: "")
                    let url = URL(fileURLWithPath: cleaned)
                    DevAppLauncher.openInEditor(url)
                }
                Button("Copy File Path") {
                    let cleaned = entry.text.replacingOccurrences(of: "edited ", with: "")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cleaned, forType: .string)
                    CockpitAudio.playSuccess()
                }
            } else {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    CockpitAudio.playSuccess()
                }
                Button("Run in Terminal") {
                    DevAppLauncher.openInTerminal(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                }
            }
        }
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("MODIFIED LINES")
                    .font(Theme.mono(8.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("diff patch")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.bottom, 2)

            // Sample synthesized diff block showing additions & removals
            VStack(alignment: .leading, spacing: 1.5) {
                Text("- // previous configuration line")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.critical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.critical.opacity(0.12), in: RoundedRectangle(cornerRadius: 2))

                Text("+ let updatedConfig = TelemetryConfig.liveActive()")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.copilotColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.copilotColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 2))
            }
        }
        .padding(8)
        .background(Theme.track.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5).stroke(Theme.accent.opacity(0.2), lineWidth: 1)
        )
        .padding(.leading, 18)
        .padding(.bottom, 4)
    }
}

