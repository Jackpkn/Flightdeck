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
    /// The unredacted truth. Ingestion and every internal calculation use this.
    private(set) var rawSessions: [String: SessionAgg] = [:]

    /// What the UI sees. In presentation mode the strings that identify *what
    /// you are working on* are replaced; every measured number passes straight
    /// through, so a shared screen still shows real spend.
    var sessions: [String: SessionAgg] {
        guard redactor.isEnabled else { return rawSessions }
        return rawSessions.mapValues { $0.redacted(by: redactor) }
    }

    var redactor = Redactor()

    /// Safe to screenshare: masks project names, session titles, branches and
    /// file paths. Costs, tokens and survival rates are never masked.
    var isPresentationMode: Bool {
        get { redactor.isEnabled }
        set {
            redactor.isEnabled = newValue
            if newValue {
                redactor.register(projects: rawSessions.values.map(\.project))
            }
        }
    }
    private(set) var activity: [ActivityEntry] = []
    private(set) var costEvents: [CostEvent] = []
    var inspectedSession: SessionAgg? = nil

    private var offsets: [String: UInt64] = [:]
    /// Learns each model's real context-window size from observed usage, so the
    /// gauge is not pinned to a constant that is wrong for long-context models.
    private var contextResolver = ContextWindowResolver()
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

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

    @MainActor
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
        let transcripts = paths.filter { $0.hasSuffix(".jsonl") }.map { URL(fileURLWithPath: $0) }
        guard !transcripts.isEmpty else { return }
        ingest(files: transcripts)
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
    /// Statusline provides: model, contextTokens, contextTotalTokens (authoritative),
    /// totalCostUsd, project, branch. JSONL tailing provides the cumulative cost
    /// checkpoints, activity entries and lastFile.
    @MainActor
    private func mergeLiveSessions(_ records: [SessionLiveRecord]) {
        for record in records {
            if record.sessionId.hasPrefix("test-") { continue }
            var agg = rawSessions[record.sessionId] ?? SessionAgg(id: record.sessionId, project: record.project)
            if !record.project.isEmpty { agg.project = record.project }
            if !record.branch.isEmpty { agg.branch = record.branch }
            if !record.model.isEmpty { agg.model = record.model }
            if !record.lastFile.isEmpty { agg.lastFile = record.lastFile }
            // A point-in-time reading, not a high-water mark: context genuinely drops
            // after Claude Code compacts, and clamping with max() left the "near limit"
            // alert stuck on for the rest of the session.
            if record.contextTokens > 0 {
                agg.contextTokens = record.contextTokens
            }
            if record.contextTotalTokens > 0 {
                // Claude Code reported the real window size — trusted over inference,
                // and remembered for this model so transcript-only sessions benefit too.
                contextResolver.recordAuthoritative(model: record.model, total: record.contextTotalTokens)
                agg.contextTotalTokens = record.contextTotalTokens
                agg.contextWindowSource = .statusline
            }
            agg.lastSeen = max(agg.lastSeen ?? .distantPast, record.updatedAt)
            if record.totalCostUsd > 0 {
                agg.liveTotalCost = record.totalCostUsd
            }
            rawSessions[record.sessionId] = agg
            if inspectedSession?.id == record.sessionId {
                inspectedSession = agg
            }
        }
    }

    @MainActor
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
                project: rawSessions[r.sessionId]?.project ?? "ai",
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


    @MainActor
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

    /// Full rescan. Discovery and parsing happen on `fsQueue`; only the merge runs
    /// on main, so a large first load never blocks rendering.
    func refresh() {
        fsQueue.async { [weak self] in
            guard let self else { return }
            let batches = self.discoverLogFiles().compactMap { self.readBatch(from: $0) }
            let projectData = Self.readClaudeJsonProjects()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !batches.isEmpty { self.applyBatches(batches) }
                self.mergeClaudeJsonProjects(projectData)
                self.trimActivity()
            }
        }
    }

    /// One project's "last session" telemetry from `~/.claude.json`, parsed into a
    /// `Sendable` value so it can cross from the reader queue to the main thread.
    struct ClaudeProjectSnapshot: Sendable {
        let sessionId: String
        let cwd: String
        var lastCost: Double = 0
        var startedAt: Date?
        var modifiedAt: Date?
        var firstPrompt: String = ""
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var linesAdded: Int = 0
        var linesRemoved: Int = 0
        var apiDurationMs: Int = 0
        var toolDurationMs: Int = 0
        var totalDurationMs: Int = 0
        var webSearchRequests: Int = 0
        var versionBase: String = ""
        var mcpServers: [String] = []
        var modelUsages: [String: ModelUsageSummary] = [:]
    }

    /// Reads and parses `~/.claude.json`. Pure — touches no instance state — so it is
    /// safe to call from the reader queue.
    static func readClaudeJsonProjects() -> [ClaudeProjectSnapshot] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: [String: Any]] else {
            return []
        }

        return projects.compactMap { path, proj in
            // Only real sessions get a card. The previous fallback synthesised an id
            // from `path.hashValue`, which Swift re-seeds every launch — so a project
            // that had never run a session produced a differently-named phantom
            // session on each start, with no transcript behind it.
            guard let sessionId = proj["lastSessionId"] as? String, !sessionId.isEmpty else { return nil }

            var snap = ClaudeProjectSnapshot(sessionId: sessionId, cwd: path)
            snap.lastCost = proj["lastCost"] as? Double ?? 0

            // `lastStartTime` is when the session began — it anchors duration and
            // day-attribution, and is not the same thing as when it was last active.
            if let ms = proj["lastStartTime"] as? Double, ms > 0 {
                snap.startedAt = Date(timeIntervalSince1970: ms / 1000.0)
            }
            // `exampleFilesGeneratedAt` and the project folder's mtime were previously
            // used as activity proxies. Neither tracks session activity — a build or a
            // checkout moves the folder mtime — so idle sessions looked recently active.
            if let ms = proj["lastSessionModified"] as? Double, ms > 0 {
                snap.modifiedAt = Date(timeIntervalSince1970: ms / 1000.0)
            }
            snap.firstPrompt = proj["lastSessionFirstPrompt"] as? String ?? ""

            snap.inputTokens = proj["lastTotalInputTokens"] as? Int ?? 0
            snap.outputTokens = proj["lastTotalOutputTokens"] as? Int ?? 0
            snap.cacheCreationTokens = proj["lastTotalCacheCreationInputTokens"] as? Int ?? 0
            snap.cacheReadTokens = proj["lastTotalCacheReadInputTokens"] as? Int ?? 0
            snap.linesAdded = proj["lastLinesAdded"] as? Int ?? 0
            snap.linesRemoved = proj["lastLinesRemoved"] as? Int ?? 0
            snap.apiDurationMs = proj["lastAPIDuration"] as? Int ?? 0
            snap.toolDurationMs = proj["lastToolDuration"] as? Int ?? 0
            snap.totalDurationMs = proj["lastDuration"] as? Int ?? 0
            snap.webSearchRequests = proj["lastTotalWebSearchRequests"] as? Int ?? 0
            snap.versionBase = proj["lastVersionBase"] as? String ?? ""

            if let mcp = proj["mcpServers"] as? [String: Any] {
                snap.mcpServers = mcp.keys.sorted()
            } else if let enabled = proj["enabledMcpjsonServers"] as? [String] {
                snap.mcpServers = enabled
            }

            if let modelUsage = proj["lastModelUsage"] as? [String: Any] {
                for (modelName, rawVal) in modelUsage {
                    guard ClaudeModelPicker.isReal(modelName), let u = rawVal as? [String: Any] else { continue }
                    snap.modelUsages[modelName] = ModelUsageSummary(
                        inputTokens: u["inputTokens"] as? Int ?? 0,
                        outputTokens: u["outputTokens"] as? Int ?? 0,
                        cacheReadTokens: u["cacheReadInputTokens"] as? Int ?? 0,
                        cacheCreationTokens: u["cacheCreationInputTokens"] as? Int ?? 0,
                        costUSD: u["costUSD"] as? Double ?? 0
                    )
                }
            }
            return snap
        }
    }

    /// Merges parsed project telemetry into the live session map. Main thread only.
    @MainActor
    private func mergeClaudeJsonProjects(_ snapshots: [ClaudeProjectSnapshot]) {
        for snap in snapshots {
            var agg = rawSessions[snap.sessionId]
                ?? SessionAgg(id: snap.sessionId, project: Self.friendlyName(fromCwd: snap.cwd))
            agg.cwd = snap.cwd

            if snap.lastCost > 0 {
                agg.liveTotalCost = max(agg.liveTotalCost ?? 0, snap.lastCost)
            }
            if let started = snap.startedAt {
                agg.sessionStart = min(agg.sessionStart ?? started, started)
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, started)
            }
            if let modified = snap.modifiedAt {
                agg.lastSeen = max(agg.lastSeen ?? .distantPast, modified)
            }
            if !snap.firstPrompt.isEmpty, agg.lastPrompt.isEmpty {
                agg.lastPrompt = snap.firstPrompt
            }

            agg.inputTokens = max(agg.inputTokens, snap.inputTokens)
            agg.outputTokens = max(agg.outputTokens, snap.outputTokens)
            agg.cacheCreationTokens = max(agg.cacheCreationTokens, snap.cacheCreationTokens)
            agg.cacheReadTokens = max(agg.cacheReadTokens, snap.cacheReadTokens)
            agg.linesAdded = max(agg.linesAdded, snap.linesAdded)
            agg.linesRemoved = max(agg.linesRemoved, snap.linesRemoved)
            agg.apiDurationMs = max(agg.apiDurationMs, snap.apiDurationMs)
            agg.toolDurationMs = max(agg.toolDurationMs, snap.toolDurationMs)
            agg.totalDurationMs = max(agg.totalDurationMs, snap.totalDurationMs)
            agg.webSearchRequests = max(agg.webSearchRequests, snap.webSearchRequests)
            if !snap.versionBase.isEmpty { agg.versionBase = snap.versionBase }
            if !snap.mcpServers.isEmpty { agg.mcpServers = snap.mcpServers }

            for (modelName, usage) in snap.modelUsages {
                var summary = agg.modelUsages[modelName] ?? ModelUsageSummary()
                summary.inputTokens = max(summary.inputTokens, usage.inputTokens)
                summary.outputTokens = max(summary.outputTokens, usage.outputTokens)
                summary.cacheReadTokens = max(summary.cacheReadTokens, usage.cacheReadTokens)
                summary.cacheCreationTokens = max(summary.cacheCreationTokens, usage.cacheCreationTokens)
                summary.costUSD = max(summary.costUSD, usage.costUSD)
                agg.modelUsages[modelName] = summary
            }
            if !ClaudeModelPicker.isReal(agg.model),
               let dominant = ClaudeModelPicker.dominant(in: agg.modelUsages) {
                agg.model = dominant
            }

            rawSessions[snap.sessionId] = agg
            if inspectedSession?.id == snap.sessionId {
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

    /// One transcript file's newly-appended lines, already parsed off the main thread.
    private struct TranscriptBatch {
        let sessionIdHint: String
        let projectHint: String
        let entries: [ClaudeLogLine]
        let fileModified: Date?
    }

    /// Reads and parses new lines from a transcript. Runs on `fsQueue` only, which is
    /// also the sole owner of `offsets` — no observable state is touched here, so this
    /// can never race the main thread's rendering.
    private func readBatch(from file: URL) -> TranscriptBatch? {
        dispatchPrecondition(condition: .onQueue(fsQueue))

        let path = file.path
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let startOffset = offsets[path] ?? 0
        guard (try? handle.seek(toOffset: startOffset)) != nil else { return nil }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var consumedBytes = data.count

        // A file mid-write can end on a partial line — leave it for the next poll.
        if !text.hasSuffix("\n"), let last = lines.last {
            consumedBytes -= last.utf8.count
            lines.removeLast()
        }
        offsets[path] = startOffset + UInt64(consumedBytes)

        let entries = lines.compactMap { line -> ClaudeLogLine? in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ClaudeLogLine.self, from: lineData)
        }
        guard !entries.isEmpty else { return nil }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return TranscriptBatch(
            sessionIdHint: file.deletingPathExtension().lastPathComponent,
            projectHint: Self.friendlyName(fromSanitizedDir: file.deletingLastPathComponent().lastPathComponent),
            entries: entries,
            fileModified: attrs?[.modificationDate] as? Date
        )
    }

    /// Applies parsed batches to the observable state. Main thread only — every
    /// mutation of `sessions`, `activity`, `costEvents` and `contextResolver` goes
    /// through here or through the GRDB merges, which also hop to main.
    @MainActor
    private func applyBatches(_ batches: [TranscriptBatch]) {
        for batch in batches {
            for entry in batch.entries {
                apply(entry, projectHint: batch.projectHint, sessionIdHint: batch.sessionIdHint)
            }
            // Fall back to the transcript's own mtime when no line carried a timestamp.
            if var agg = rawSessions[batch.sessionIdHint], agg.lastSeen == nil, let modified = batch.fileModified {
                agg.lastSeen = modified
                rawSessions[batch.sessionIdHint] = agg
            }
        }
        trimActivity()
    }

    /// Reads the given transcripts on `fsQueue`, then applies them on main.
    private func ingest(files: [URL]) {
        fsQueue.async { [weak self] in
            guard let self else { return }
            let batches = files.compactMap { self.readBatch(from: $0) }
            guard !batches.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.applyBatches(batches)
            }
        }
    }

    private func trimActivity() {
        if activity.count > 200 {
            activity.removeLast(activity.count - 200)
        }
    }

    @MainActor
    /// `sessionIdHint` is the transcript's filename, which *is* the session id.
    /// Some record types — `file-history-delta` among them — carry no `sessionId`
    /// field at all, so requiring one silently discarded every file-change record.
    private func apply(_ entry: ClaudeLogLine, projectHint: String, sessionIdHint: String = "") {
        let sessionId = entry.sessionId ?? sessionIdHint
        guard !sessionId.isEmpty, !sessionId.hasPrefix("test-") else { return }
        let ts = parseDate(entry.timestamp)

        var agg = rawSessions[sessionId] ?? SessionAgg(id: sessionId, project: projectHint)
        if let cwd = entry.cwd {
            agg.cwd = cwd
            agg.project = Self.friendlyName(fromCwd: cwd)
        }
        if let branch = entry.gitBranch { agg.branch = branch }
        if let ts {
            agg.lastSeen = max(agg.lastSeen ?? .distantPast, ts)
            agg.firstSeen = min(agg.firstSeen ?? .distantFuture, ts)
        }

        // 1. Direct cost from JSON (type: "cost-state").
        // `totalCostUSD` is the session's running total at that checkpoint, so it is
        // recorded as a snapshot. Treating it as a per-turn delta multiplied every
        // session's cost by the number of checkpoints it happened to write.
        if let startMs = entry.startTime, startMs > 0 {
            let started = Date(timeIntervalSince1970: startMs / 1000.0)
            agg.sessionStart = min(agg.sessionStart ?? started, started)
        }
        if let cumulative = entry.totalCostUSD {
            let eventDate = ts ?? agg.lastSeen ?? Date()
            let previousTotal = agg.costLedger.total
            agg.costLedger.record(cumulative, at: eventDate)
            agg.costLedger.prune(before: Date().addingTimeInterval(-7 * 24 * 3600))
            agg.liveTotalCost = max(agg.liveTotalCost ?? 0, cumulative)
            // The fountain visualises real new spend — the delta, not the running total.
            let delta = agg.costLedger.total - previousTotal
            if delta > 0 {
                costEvents.append(.init(sessionId: sessionId, amount: delta, timestamp: eventDate))
            }
        }
        if entry.hasUnknownModelCost == true {
            agg.hasUnknownModelCost = true
        }

        // Session totals from `cost-state`. These describe this session specifically,
        // where the `last*` keys in ~/.claude.json describe a project's most recent run.
        if let added = entry.totalLinesAdded { agg.linesAdded = max(agg.linesAdded, added) }
        if let removed = entry.totalLinesRemoved { agg.linesRemoved = max(agg.linesRemoved, removed) }
        if let api = entry.totalAPIDuration { agg.apiDurationMs = max(agg.apiDurationMs, api) }
        if let tool = entry.totalToolDuration { agg.toolDurationMs = max(agg.toolDurationMs, tool) }
        if let total = entry.totalDuration { agg.totalDurationMs = max(agg.totalDurationMs, total) }

        // Subagent runs and real file checkpoints.
        if let agentName = entry.agentName { agg.noteSubagent(agentName) }
        if let path = entry.trackingPath {
            agg.noteFileModified(trackingPath: path, realParentDir: entry.backup?.realParentDir)
        }

        // 2. Direct model usage from JSON
        if let modelUsage = entry.modelUsage {
            for (modelName, mUsage) in modelUsage {
                guard ClaudeModelPicker.isReal(modelName) else { continue }
                var summary = agg.modelUsages[modelName] ?? ModelUsageSummary()
                if let it = mUsage.inputTokens { summary.inputTokens = max(summary.inputTokens, it) }
                if let ot = mUsage.outputTokens { summary.outputTokens = max(summary.outputTokens, ot) }
                if let cr = mUsage.cacheReadInputTokens { summary.cacheReadTokens = max(summary.cacheReadTokens, cr) }
                if let cc = mUsage.cacheCreationInputTokens { summary.cacheCreationTokens = max(summary.cacheCreationTokens, cc) }
                if let cost = mUsage.costUSD { summary.costUSD = max(summary.costUSD, cost) }
                agg.modelUsages[modelName] = summary
            }
            if let dominant = ClaudeModelPicker.dominant(in: agg.modelUsages) {
                agg.model = dominant
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
            let rawModel = entry.message?.model ?? agg.model
            // `<synthetic>` marks Claude Code's own bookkeeping messages — not a model
            // the user ran, and never something to display or attribute usage to.
            let turnModel = ClaudeModelPicker.isReal(rawModel) ? rawModel : agg.model
            if ClaudeModelPicker.isReal(turnModel) {
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

            if ClaudeModelPicker.isReal(turnModel) {
                var summary = agg.modelUsages[turnModel] ?? ModelUsageSummary()
                summary.inputTokens += inT
                summary.outputTokens += outT
                summary.thinkingTokens += thinkT
                summary.cacheReadTokens += readT
                summary.cacheCreationTokens += createT
                agg.modelUsages[turnModel] = summary
            }

            // Context held for this turn = fresh input + everything replayed from cache.
            agg.contextTokens = inT + readT + createT
            contextResolver.observe(model: turnModel, contextTokens: agg.contextTokens)
            let resolved = contextResolver.resolve(model: turnModel)
            agg.contextTotalTokens = resolved.total
            agg.contextWindowSource = resolved.source
        }

        if let blocks = entry.message?.content {
            for block in blocks {
                if block.type == "tool_use" {
                    agg.toolUseCount += 1
                    let actTs = ts ?? agg.lastSeen ?? Date()
                    if let path = block.input?.file_path {
                        agg.lastFile = path
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        activity.insert(
                            .init(timestamp: actTs, project: agg.project, sessionId: sessionId, kind: .edit, text: "edited \(name)"),
                            at: 0
                        )
                    } else if let cmd = block.input?.command {
                        activity.insert(
                            .init(
                                timestamp: actTs,
                                project: agg.project,
                                sessionId: sessionId,
                                kind: .forCommand(cmd),
                                text: "ran `\(cmd.prefix(48))`"
                            ),
                            at: 0
                        )
                    }
                } else if block.type == "tool_result", block.is_error == true {
                    agg.toolErrorCount += 1
                    if let ts { agg.lastErrorAt = ts }
                    let actTs = ts ?? agg.lastSeen ?? Date()
                    activity.insert(
                        .init(timestamp: actTs, project: agg.project, sessionId: sessionId, kind: .error, text: "⚠ tool call failed"),
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

        rawSessions[sessionId] = agg
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

    /// Spend in a window, aggregated per session so cumulative checkpoints are
    /// differenced rather than summed. `isExact` is false when any session's
    /// contribution could not be isolated to the window.
    func spend(since cutoff: Date) -> (amount: Double, isExact: Bool) {
        var total = 0.0
        var exact = true
        for session in sessions.values {
            let contribution = session.spend(since: cutoff)
            total += contribution.amount
            if !contribution.isExact, contribution.amount > 0 { exact = false }
        }
        return (total, exact)
    }

    var todaySpend: Double {
        spend(since: Calendar.current.startOfDay(for: Date())).amount
    }

    /// False when today's figure is an upper bound — a session was already running
    /// before midnight and Claude Code wrote no checkpoint to measure against.
    var todaySpendIsExact: Bool {
        spend(since: Calendar.current.startOfDay(for: Date())).isExact
    }

    var last24hSpend: Double {
        spend(since: Date().addingTimeInterval(-24 * 3600)).amount
    }

    var activeSessions: [SessionAgg] {
        sessions.values
            .sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
    }

    /// Same list, never redacted. Anything that *computes* from a session —
    /// probing git, matching paths on disk — has to see real paths, or it
    /// silently measures nothing. Redact at the point of display instead.
    var rawActiveSessions: [SessionAgg] {
        rawSessions.values
            .sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
    }

    var activeCount: Int { sessions.values.filter(\.isActive).count }

    var contextAlertCount: Int {
        highContextSessions.count
    }

    /// Sessions close enough to their context limit to be worth acting on.
    /// Only counts sessions whose window size is measured or inferred — a defaulted
    /// 200K guess on a long-context model would flag everything as critical.
    var highContextSessions: [SessionAgg] {
        sessions.values
            .filter { $0.contextWindowSource != .fallback && $0.contextFraction > Self.highContextThreshold }
            .sorted { $0.contextFraction > $1.contextFraction }
    }

    /// Claude Code auto-compacts near the top of the window, so 70% is the last
    /// point where a manual `/compact` or a fresh session is still a free choice.
    static let highContextThreshold = 0.7

    /// Most recent real tool-call failure across every tracked session, not just
    /// the handful currently shown as cards — the signal a global flash reacts to.
    var lastErrorAt: Date? {
        sessions.values.compactMap(\.lastErrorAt).max()
    }

    var spendByProject: [(name: String, cost: Double)] {
        var totals: [String: Double] = [:]
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for s in sessions.values {
            let cost = s.spend(since: cutoff).amount
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

