import Foundation
import SwiftUI

/// Tails every `~/.claude/projects/**/*.jsonl` transcript and keeps a live aggregate
/// per session: cost, context-window usage, last file touched, recent activity.
///
/// Cursor and Copilot integrations are not wired yet — their local log formats
/// haven't been verified against a real install, so this build only ever shows
/// real Claude Code sessions rather than fabricate numbers for the others.
@Observable
final class DashboardStore {
    private(set) var sessions: [String: SessionAgg] = [:]
    private(set) var activity: [ActivityEntry] = []
    private(set) var costEvents: [CostEvent] = []

    private var offsets: [String: UInt64] = [:]
    private var timer: Timer?
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        for file in discoverLogFiles() {
            consume(file: file)
        }
        if activity.count > 200 {
            activity.removeLast(activity.count - 200)
        }
    }

    // MARK: - Discovery

    private func discoverLogFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            out.append(url)
        }
        return out
    }

    // MARK: - Incremental read

    private func consume(file: URL) {
        let path = file.path
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let startOffset = offsets[path] ?? 0
        guard (try? handle.seek(toOffset: startOffset)) != nil else { return }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var consumedBytes = data.count

        // A file mid-write can end on a partial line — leave it for the next poll.
        if !text.hasSuffix("\n"), let last = lines.last {
            consumedBytes -= last.utf8.count
            lines.removeLast()
        }
        offsets[path] = startOffset + UInt64(consumedBytes)

        let projectHint = Self.friendlyName(fromSanitizedDir: file.deletingLastPathComponent().lastPathComponent)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(ClaudeLogLine.self, from: lineData) else { continue }
            apply(entry, projectHint: projectHint)
        }
    }

    private func apply(_ entry: ClaudeLogLine, projectHint: String) {
        guard let sessionId = entry.sessionId else { return }
        let ts = entry.timestamp.flatMap(isoFormatter.date(from:)) ?? Date()

        var agg = sessions[sessionId] ?? SessionAgg(id: sessionId, project: projectHint)
        if let cwd = entry.cwd { agg.project = Self.friendlyName(fromCwd: cwd) }
        if let branch = entry.gitBranch { agg.branch = branch }
        agg.lastSeen = max(agg.lastSeen ?? .distantPast, ts)

        if let usage = entry.message?.usage {
            let cost = PricingTable.cost(model: entry.message?.model, usage: usage)
            if let model = entry.message?.model { agg.model = model }
            agg.contextTokens = (usage.input_tokens ?? 0)
                + (usage.cache_read_input_tokens ?? 0)
                + (usage.cache_creation_input_tokens ?? 0)
            agg.costLedger.append((ts, cost))
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            agg.costLedger.removeAll { $0.0 < cutoff }
            if cost > 0 {
                costEvents.append(.init(sessionId: sessionId, amount: cost, timestamp: ts))
            }
        }

        if let blocks = entry.message?.content {
            for block in blocks {
                if block.type == "tool_use" {
                    if let path = block.input?.file_path {
                        agg.lastFile = path
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        activity.insert(
                            .init(timestamp: ts, project: agg.project, sessionId: sessionId, kind: .edit, text: "edited \(name)"),
                            at: 0
                        )
                    } else if let cmd = block.input?.command {
                        activity.insert(
                            .init(
                                timestamp: ts,
                                project: agg.project,
                                sessionId: sessionId,
                                kind: .forCommand(cmd),
                                text: "ran `\(cmd.prefix(48))`"
                            ),
                            at: 0
                        )
                    }
                } else if block.type == "tool_result", block.is_error == true {
                    agg.lastErrorAt = ts
                    activity.insert(
                        .init(timestamp: ts, project: agg.project, sessionId: sessionId, kind: .error, text: "⚠ tool call failed"),
                        at: 0
                    )
                }
            }
        }

        sessions[sessionId] = agg
        if costEvents.count > 300 {
            costEvents.removeFirst(costEvents.count - 300)
        }
    }

    // MARK: - Friendly naming

    /// `cwd` is an absolute path — show the project folder, or "(home)" when a
    /// session was opened straight in the home directory rather than a project.
    private static func friendlyName(fromCwd cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home { return "(home)" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "(home)" : name
    }

    /// Before a session's first `cwd` line arrives, fall back to its log directory
    /// name, which is the cwd with slashes flattened to dashes — e.g.
    /// "-Users-pawankumar-Downloads-mirage" — take the last real segment.
    private static func friendlyName(fromSanitizedDir dir: String) -> String {
        let parts = dir.split(separator: "-").filter { !$0.isEmpty }
        return parts.last.map(String.init) ?? dir
    }

    // MARK: - Derived stats consumed by the views

    var last24hSpend: Double {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return sessions.values.flatMap(\.costLedger).filter { $0.0 > cutoff }.reduce(0) { $0 + $1.1 }
    }

    var activeSessions: [SessionAgg] {
        sessions.values
            .sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
    }

    var activeCount: Int { sessions.values.filter(\.isActive).count }

    var burnRatePerMin: Double {
        sessions.values.reduce(0) { $0 + $1.burnRatePerMin }
    }

    var contextAlertCount: Int {
        sessions.values.filter { $0.contextFraction > 0.7 }.count
    }

    /// Most recent real tool-call failure across every tracked session, not just
    /// the handful currently shown as cards — the signal a global flash reacts to.
    var lastErrorAt: Date? {
        sessions.values.compactMap(\.lastErrorAt).max()
    }

    var spendByProject: [(name: String, cost: Double)] {
        var totals: [String: Double] = [:]
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for s in sessions.values {
            let sum = s.costLedger.filter { $0.0 > cutoff }.reduce(0) { $0 + $1.1 }
            guard sum > 0 else { continue }
            totals[s.project, default: 0] += sum
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
