import Foundation
import SwiftUI
import CoreServices
import GRDB

/// Tails every `~/.claude/projects/**/*.jsonl` transcript and keeps a live aggregate
/// per session: cost, context-window usage, last file touched, recent activity.
///
/// Data arrives through three channels:
/// 1. **GRDB ValueObservation** on `session_live` — near-realtime statusline data
///    written by the `flightdeck statusline` CLI.
/// 2. **FSEvents watcher** on `~/.claude/projects/` — triggers incremental JSONL
///    tailing when Claude Code appends to transcript files.
/// 3. **ShellFeed** — local terminal history for the activity feed.
@Observable
final class DashboardStore {
    private(set) var sessions: [String: SessionAgg] = [:]
    private(set) var activity: [ActivityEntry] = []
    private(set) var costEvents: [CostEvent] = []
    var inspectedSession: SessionAgg? = nil

    private var offsets: [String: UInt64] = [:]
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

    private let shellFeed = ShellFeed.shared

    // FSEvents stream for JSONL file watching
    private var fsStream: FSEventStreamRef?
    private let fsQueue = DispatchQueue(label: "com.flightdeck.jsonl-watcher", qos: .utility)

    // GRDB observation cancellation
    private var sessionObservation: AnyDatabaseCancellable?
    private var aiEventObservation: AnyDatabaseCancellable?

    // Fallback timer — only fires if FSEvents misses something (belt + suspenders)
    private var fallbackTimer: Timer?

    func start() {
        // Initial load of all existing JSONL data
        refresh()

        // 1. Start FSEvents watcher on ~/.claude/projects/
        startFSEventsWatcher()

        // 2. Start GRDB observation on session_live and ai_events tables
        startSessionObservation()

        // 3. Fallback timer at 15s (5x slower than before — FSEvents handles the fast path)
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // 4. Shell history feed
        shellFeed.start { [weak self] cmd in
            self?.addShellCommand(cmd)
        }
    }

    func stop() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        sessionObservation?.cancel()
        sessionObservation = nil
        aiEventObservation?.cancel()
        aiEventObservation = nil
        if let stream = fsStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsStream = nil
        }
    }

    deinit {
        stop()
    }

    // MARK: - FSEvents Watcher

    private func startFSEventsWatcher() {
        let rootPath = root.path
        guard FileManager.default.fileExists(atPath: rootPath) else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            jsonlEventCallback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1-second coalescing — fast enough for cost updates, light on CPU
            flags
        ) else { return }

        fsStream = stream
        FSEventStreamSetDispatchQueue(stream, fsQueue)
        FSEventStreamStart(stream)
    }

    /// Called by FSEvents when any file under ~/.claude/projects/ changes.
    /// Filters for .jsonl files and triggers incremental tailing.
    fileprivate func handleFSEvent(paths: [String]) {
        var consumed = false
        for path in paths where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path)
            consume(file: url)
            consumed = true
        }
        if consumed {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.activity.count > 200 {
                    self.activity.removeLast(self.activity.count - 200)
                }
            }
        }
    }

    // MARK: - GRDB Session Observation

    private func startSessionObservation() {
        guard let db = ActivityDatabase.shared else { return }

        let sObservation = ValueObservation.tracking { db in
            try SessionLiveRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }

        sessionObservation = sObservation.start(
            in: db.reader,
            onError: { error in
                print("DashboardStore: session observation error — \(error)")
            },
            onChange: { [weak self] liveRecords in
                DispatchQueue.main.async {
                    self?.mergeLiveSessions(liveRecords)
                }
            }
        )

        let eObservation = ValueObservation.tracking { db in
            try AIEventRecord
                .order(Column("timestamp").desc)
                .limit(50)
                .fetchAll(db)
        }

        aiEventObservation = eObservation.start(
            in: db.reader,
            onError: { error in
                print("DashboardStore: ai_events observation error — \(error)")
            },
            onChange: { [weak self] events in
                DispatchQueue.main.async {
                    self?.mergeAIEvents(events)
                }
            }
        )
    }

    /// Merge statusline data into the in-memory SessionAgg dictionary.
    /// Statusline provides: model, contextTokens, totalCostUsd, project, branch.
    /// JSONL tailing provides: costLedger (per-turn), activity entries, lastFile.
    private func mergeLiveSessions(_ records: [SessionLiveRecord]) {
        for record in records {
            if record.sessionId.hasPrefix("test-") { continue }
            var agg = sessions[record.sessionId] ?? SessionAgg(id: record.sessionId, project: record.project)
            if !record.project.isEmpty { agg.project = record.project }
            if !record.branch.isEmpty { agg.branch = record.branch }
            if !record.model.isEmpty { agg.model = record.model }
            if !record.lastFile.isEmpty { agg.lastFile = record.lastFile }
            agg.contextTokens = max(agg.contextTokens, record.contextTokens)
            if record.contextTotalTokens > 0 {
                agg.contextTotalTokens = record.contextTotalTokens
            }
            agg.lastSeen = max(agg.lastSeen ?? .distantPast, record.updatedAt)
            if record.totalCostUsd > 0 {
                agg.liveTotalCost = record.totalCostUsd
            }
            sessions[record.sessionId] = agg
            if inspectedSession?.id == record.sessionId {
                inspectedSession = agg
            }
        }
    }

    private func mergeAIEvents(_ records: [AIEventRecord]) {
        for r in records {
            if r.sessionId.hasPrefix("test-") { continue }
            let kind: ActivityEntry.Kind
            let text: String
            switch r.event.lowercased() {
            case "posttooluse", "post-tool-use":
                let tool = r.toolName ?? "tool"
                if let detail = r.detail, !detail.isEmpty {
                    text = "used \(tool): \(detail)"
                } else {
                    text = "used \(tool)"
                }
                kind = tool.lowercased() == "edit" ? .edit : (tool.lowercased() == "bash" ? .run : .build)
            case "sessionstart", "session-start":
                text = "session started"
                kind = .run
            case "stop":
                text = "session stopped"
                kind = .run
            default:
                text = "\(r.event) \(r.toolName ?? "") \(r.detail ?? "")".trimmingCharacters(in: .whitespaces)
                kind = .run
            }

            let entry = ActivityEntry(
                timestamp: r.timestamp,
                project: sessions[r.sessionId]?.project ?? "ai",
                sessionId: r.sessionId,
                kind: kind,
                text: text
            )

            if !activity.contains(where: { abs($0.timestamp.timeIntervalSince(entry.timestamp)) < 0.5 && $0.text == entry.text }) {
                activity.append(entry)
            }
        }
        activity.sort { $0.timestamp > $1.timestamp }
        if activity.count > 200 {
            activity.removeLast(activity.count - 200)
        }
    }


    private func addShellCommand(_ item: ShellFeed.ShellCommand) {
        let entry = ActivityEntry(
            timestamp: item.timestamp,
            project: "shell",
            sessionId: "local-terminal",
            kind: .forCommand(item.command),
            text: "ran `\(item.command.prefix(56))`"
        )
        // Deduplicate
        if !activity.contains(where: { abs($0.timestamp.timeIntervalSince(entry.timestamp)) < 0.5 && $0.text == entry.text }) {
            activity.insert(entry, at: 0)
            activity.sort { $0.timestamp > $1.timestamp }
            if activity.count > 200 {
                activity.removeLast(activity.count - 200)
            }
        }
    }

    func refresh() {
        for file in discoverLogFiles() {
            consume(file: file)
        }
        loadClaudeJsonProjects()
        if activity.count > 200 {
            activity.removeLast(activity.count - 200)
        }
    }

    /// Read Claude Code's global ~/.claude.json to ingest exact session costs
    /// and model usages computed directly by Claude Code.
    private func loadClaudeJsonProjects() {
        let claudeJsonURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: claudeJsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: [String: Any]] else {
            return
        }

        for (path, proj) in projects {
            let sessionId: String
            if let lastSid = proj["lastSessionId"] as? String, !lastSid.isEmpty {
                sessionId = lastSid
            } else {
                sessionId = "proj-\(abs(path.hashValue))"
            }

            let lastCost = proj["lastCost"] as? Double ?? 0
            let projectName = Self.friendlyName(fromCwd: path)

            var agg = sessions[sessionId] ?? SessionAgg(id: sessionId, project: projectName)
            agg.cwd = path
            if lastCost > 0 {
                agg.liveTotalCost = max(agg.liveTotalCost ?? 0, lastCost)
            }

            // Real timestamp from lastStartTime, or lastSessionModified, or exampleFilesGeneratedAt, or folder modification date
            if let startTimeMs = proj["lastStartTime"] as? Double, startTimeMs > 0 {
                let d = Date(timeIntervalSince1970: startTimeMs / 1000.0)
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, d)
            } else if let modMs = proj["lastSessionModified"] as? Double, modMs > 0 {
                let d = Date(timeIntervalSince1970: modMs / 1000.0)
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, d)
            } else if let genMs = proj["exampleFilesGeneratedAt"] as? Double, genMs > 0 {
                let d = Date(timeIntervalSince1970: genMs / 1000.0)
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, d)
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date {
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, modDate)
            } else if agg.lastSeen == nil {
                agg.lastSeen = Date()
            }

            if let prompt = proj["lastSessionFirstPrompt"] as? String, !prompt.isEmpty, agg.lastPrompt.isEmpty {
                agg.lastPrompt = prompt
            }

            if let lastInput = proj["lastTotalInputTokens"] as? Int { agg.inputTokens = max(agg.inputTokens, lastInput) }
            if let lastOutput = proj["lastTotalOutputTokens"] as? Int { agg.outputTokens = max(agg.outputTokens, lastOutput) }
            if let lastCacheCreation = proj["lastTotalCacheCreationInputTokens"] as? Int { agg.cacheCreationTokens = max(agg.cacheCreationTokens, lastCacheCreation) }
            if let lastCacheRead = proj["lastTotalCacheReadInputTokens"] as? Int { agg.cacheReadTokens = max(agg.cacheReadTokens, lastCacheRead) }

            if let linesAdded = proj["lastLinesAdded"] as? Int { agg.linesAdded = max(agg.linesAdded, linesAdded) }
            if let linesRemoved = proj["lastLinesRemoved"] as? Int { agg.linesRemoved = max(agg.linesRemoved, linesRemoved) }
            if let apiDur = proj["lastAPIDuration"] as? Int { agg.apiDurationMs = max(agg.apiDurationMs, apiDur) }
            if let toolDur = proj["lastToolDuration"] as? Int { agg.toolDurationMs = max(agg.toolDurationMs, toolDur) }
            if let dur = proj["lastDuration"] as? Int { agg.totalDurationMs = max(agg.totalDurationMs, dur) }
            if let webSearches = proj["lastTotalWebSearchRequests"] as? Int { agg.webSearchRequests = max(agg.webSearchRequests, webSearches) }
            if let ver = proj["lastVersionBase"] as? String, !ver.isEmpty { agg.versionBase = ver }
            if let mcp = proj["mcpServers"] as? [String: Any] {
                agg.mcpServers = Array(mcp.keys.sorted())
            } else if let enabledMcp = proj["enabledMcpjsonServers"] as? [String] {
                agg.mcpServers = enabledMcp
            }

            if let modelUsage = proj["lastModelUsage"] as? [String: Any] {
                if let firstModel = modelUsage.keys.first, agg.model.isEmpty {
                    agg.model = firstModel
                }
                for (modelName, rawVal) in modelUsage {
                    guard let u = rawVal as? [String: Any] else { continue }
                    var summary = agg.modelUsages[modelName] ?? ModelUsageSummary()
                    summary.inputTokens = max(summary.inputTokens, u["inputTokens"] as? Int ?? 0)
                    summary.outputTokens = max(summary.outputTokens, u["outputTokens"] as? Int ?? 0)
                    summary.cacheReadTokens = max(summary.cacheReadTokens, u["cacheReadInputTokens"] as? Int ?? 0)
                    summary.cacheCreationTokens = max(summary.cacheCreationTokens, u["cacheCreationInputTokens"] as? Int ?? 0)
                    summary.costUSD = max(summary.costUSD, u["costUSD"] as? Double ?? 0.0)
                    agg.modelUsages[modelName] = summary
                }
            }
            sessions[sessionId] = agg
            if inspectedSession?.id == sessionId {
                inspectedSession = agg
            }
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
        guard let sessionId = entry.sessionId, !sessionId.hasPrefix("test-") else { return }
        let ts = entry.timestamp.flatMap(isoFormatter.date(from:)) ?? Date()

        var agg = sessions[sessionId] ?? SessionAgg(id: sessionId, project: projectHint)
        if let cwd = entry.cwd {
            agg.cwd = cwd
            agg.project = Self.friendlyName(fromCwd: cwd)
        }
        if let branch = entry.gitBranch { agg.branch = branch }
        agg.lastSeen = max(agg.lastSeen ?? .distantPast, ts)

        // 1. Direct cost from JSON (type: "cost-state")
        if let directCost = entry.totalCostUSD ?? entry.costUSD {
            agg.liveTotalCost = max(agg.liveTotalCost ?? 0, directCost)
            agg.costLedger.append((ts, directCost))
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            agg.costLedger.removeAll { $0.0 < cutoff }
            if directCost > 0 {
                costEvents.append(.init(sessionId: sessionId, amount: directCost, timestamp: ts))
            }
        }

        // 2. Direct model usage from JSON
        if let modelUsage = entry.modelUsage {
            if let firstModel = modelUsage.keys.first, !firstModel.isEmpty {
                agg.model = firstModel
            }
            for (modelName, mUsage) in modelUsage {
                var summary = agg.modelUsages[modelName] ?? ModelUsageSummary()
                if let it = mUsage.inputTokens { summary.inputTokens = max(summary.inputTokens, it) }
                if let ot = mUsage.outputTokens { summary.outputTokens = max(summary.outputTokens, ot) }
                if let cr = mUsage.cacheReadInputTokens { summary.cacheReadTokens = max(summary.cacheReadTokens, cr) }
                if let cc = mUsage.cacheCreationInputTokens { summary.cacheCreationTokens = max(summary.cacheCreationTokens, cc) }
                if let cost = mUsage.costUSD { summary.costUSD = max(summary.costUSD, cost) }
                agg.modelUsages[modelName] = summary
            }
            let sumFromUsage = modelUsage.values.compactMap(\.costUSD).reduce(0, +)
            if sumFromUsage > 0 {
                agg.liveTotalCost = max(agg.liveTotalCost ?? 0, sumFromUsage)
            }
            let sumIn = agg.modelUsages.values.map(\.inputTokens).reduce(0, +)
            let sumOut = agg.modelUsages.values.map(\.outputTokens).reduce(0, +)
            let sumCr = agg.modelUsages.values.map(\.cacheReadTokens).reduce(0, +)
            let sumCc = agg.modelUsages.values.map(\.cacheCreationTokens).reduce(0, +)
            if sumIn > 0 { agg.inputTokens = max(agg.inputTokens, sumIn) }
            if sumOut > 0 { agg.outputTokens = max(agg.outputTokens, sumOut) }
            if sumCr > 0 { agg.cacheReadTokens = max(agg.cacheReadTokens, sumCr) }
            if sumCc > 0 { agg.cacheCreationTokens = max(agg.cacheCreationTokens, sumCc) }
        }

        // 3. Message turn usage: set model and tokens from the JSON
        if let usage = entry.message?.usage {
            let turnModel = entry.message?.model ?? agg.model
            if !turnModel.isEmpty {
                agg.model = turnModel
            }
            let inT = usage.input_tokens ?? 0
            let outT = usage.output_tokens ?? 0
            let thinkT = usage.output_tokens_details?.thinking_tokens ?? 0
            let readT = usage.cache_read_input_tokens ?? 0
            let createT = usage.cache_creation_input_tokens ?? 0

            agg.inputTokens += inT
            agg.outputTokens += outT
            agg.thinkingTokens += thinkT
            agg.cacheReadTokens += readT
            agg.cacheCreationTokens += createT

            if !turnModel.isEmpty {
                var summary = agg.modelUsages[turnModel] ?? ModelUsageSummary()
                summary.inputTokens += inT
                summary.outputTokens += outT
                summary.thinkingTokens += thinkT
                summary.cacheReadTokens += readT
                summary.cacheCreationTokens += createT
                agg.modelUsages[turnModel] = summary
            }

            agg.contextTokens = inT + readT + createT
            if agg.contextTokens > agg.contextTotalTokens {
                agg.contextTotalTokens = max(agg.contextTotalTokens, agg.contextTokens > 200_000 ? 1_000_000 : 200_000)
            }
        }

        if let blocks = entry.message?.content {
            for block in blocks {
                if block.type == "tool_use" {
                    agg.toolUseCount += 1
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

        // 4. Ingest specialized telemetry types (ai-title, mode, permission-mode, last-prompt, pr-link)
        if let title = entry.aiTitle, !title.isEmpty {
            agg.aiTitle = title
        }
        if let mode = entry.mode, !mode.isEmpty {
            agg.mode = mode
        }
        if let perm = entry.permissionMode, !perm.isEmpty {
            agg.permissionMode = perm
        }
        if let prompt = entry.lastPrompt, !prompt.isEmpty {
            agg.lastPrompt = prompt
        }
        if let pr = entry.prUrl, !pr.isEmpty {
            agg.prUrl = pr
            agg.prNumber = entry.prNumber
            if let repo = entry.prRepository { agg.prRepository = repo }
        }

        sessions[sessionId] = agg
        if inspectedSession?.id == sessionId {
            inspectedSession = agg
        }
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

    var todaySpend: Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let ledgerSpend = sessions.values.flatMap(\.costLedger).filter { $0.0 >= startOfDay }.reduce(0) { $0 + $1.1 }
        if ledgerSpend > 0 { return ledgerSpend }
        let activeTodaySpend = sessions.values.filter { ($0.lastSeen ?? .distantPast) >= startOfDay }.map(\.totalCost).reduce(0, +)
        return max(ledgerSpend, activeTodaySpend)
    }

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
        highContextSessions.count
    }

    var highContextSessions: [SessionAgg] {
        sessions.values.filter { $0.contextFraction > 0.7 }
            .sorted { $0.contextFraction > $1.contextFraction }
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
            let cost = sum > 0 ? sum : s.totalCost
            guard cost > 0 else { continue }
            totals[s.project, default: 0] += cost
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // In-memory transcript cache keyed by session ID
    private var transcriptCache: [String: [ConversationTurn]] = [:]

    func loadTranscript(for sessionId: String) async -> [ConversationTurn] {
        if let cached = transcriptCache[sessionId] {
            return cached
        }

        guard let file = ClaudeTranscriptReader.locateTranscriptFile(sessionId: sessionId) else {
            return []
        }

        let turns = await Task.detached(priority: .userInitiated) {
            ClaudeTranscriptReader.parseTurns(from: file)
        }.value

        transcriptCache[sessionId] = turns
        return turns
    }
}

/// A C function pointer for FSEvents stream callback.
/// The DashboardStore instance is recovered from clientCallBackInfo.
private let jsonlEventCallback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
    guard let info else { return }
    let store = Unmanaged<DashboardStore>.fromOpaque(info).takeUnretainedValue()
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
    store.handleFSEvent(paths: paths)
}

