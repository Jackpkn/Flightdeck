import Foundation
import GRDB

/// One line of a Claude Code session transcript at `~/.claude/projects/<project>/<session>.jsonl`.
/// Field names match the real on-disk schema — only the subset Flightdeck needs is decoded;
/// unknown keys are ignored by Codable.
struct ClaudeLogLine: Decodable {
    let type: String?
    let timestamp: String?
    let cwd: String?
    let gitBranch: String?
    let sessionId: String?
    let message: MessagePayload?

    // Direct cost fields emitted in Claude Code's `cost-state` records.
    // `totalCostUSD` is the session's running total; `startTime` is epoch milliseconds.
    let totalCostUSD: Double?
    let startTime: Double?
    let modelUsage: [String: ModelUsage]?

    // Session totals, also from `cost-state`. These are scoped to this session,
    // unlike the `last*` keys in ~/.claude.json which describe a project's last run.
    let totalLinesAdded: Int?
    let totalLinesRemoved: Int?
    let totalAPIDuration: Int?
    let totalToolDuration: Int?
    let totalDuration: Int?
    /// True when Claude Code priced a model it does not know — the cost is a floor.
    let hasUnknownModelCost: Bool?

    /// Subagent that produced this record (`agent-name`).
    let agentName: String?
    /// File Claude Code checkpointed a change to (`file-history-delta`). Relative to
    /// the session's cwd; `backup.realParentDir` gives the absolute directory, which
    /// together with the file name resolves it unambiguously.
    let trackingPath: String?
    let backup: FileBackup?

    struct FileBackup: Decodable {
        let realParentDir: String?
    }

    // Additional telemetry from specialized records
    let aiTitle: String?
    let mode: String?
    let permissionMode: String?
    let lastPrompt: String?
    let prUrl: String?
    let prNumber: Int?
    let prRepository: String?

    struct ModelUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let costUSD: Double?
        let webSearchRequests: Int?
    }

    struct MessagePayload: Decodable {
        let model: String?
        let usage: Usage?
        let content: [ContentBlock]?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let output_tokens_details: OutputTokensDetails?
    }

    struct OutputTokensDetails: Decodable {
        let thinking_tokens: Int?
    }

    struct ContentBlock: Decodable {
        let type: String?
        let name: String?
        let input: ToolInput?
        let is_error: Bool?
    }

    struct ToolInput: Decodable {
        let file_path: String?
        let command: String?
    }
}

/// Token and cost breakdown per model directly parsed from Claude Code telemetry JSON.
struct ModelUsageSummary: Codable, Equatable, Hashable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var thinkingTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var costUSD: Double = 0.0

    /// `thinkingTokens` is deliberately excluded: the API reports it inside
    /// `output_tokens_details`, meaning it is already part of `outputTokens`.
    /// Adding it again inflated every token figure in the UI.
    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    var cacheHitRatio: Double {
        let total = cacheReadTokens + inputTokens
        guard total > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(total)
    }
}

/// Live aggregate for one session, rebuilt incrementally as its log file grows.
struct SessionAgg: Identifiable {
    let id: String
    var project: String
    var branch: String = ""
    var model: String = ""
    var cwd: String = ""
    var lastFile: String = ""
    var lastSeen: Date?
    var lastErrorAt: Date?
    var contextTokens: Int = 0
    var contextTotalTokens: Int = ContextWindowResolver.defaultWindow
    /// How `contextTotalTokens` was determined — measured, inferred, or defaulted.
    var contextWindowSource: ContextWindowSource = .fallback
    /// Cumulative cost checkpoints written by Claude Code, never per-turn deltas.
    var costLedger = CostSnapshotLedger()
    var liveTotalCost: Double? = nil
    /// When Claude Code says this session began (`cost-state.startTime` / `lastStartTime`).
    var sessionStart: Date? = nil
    /// Earliest timestamp seen in the transcript. Used as the session window's start
    /// when Claude Code reported no explicit start time, which is the common case.
    var firstSeen: Date? = nil

    // Detailed token telemetry
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var thinkingTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    // Per-model breakdown directly from JSON
    var modelUsages: [String: ModelUsageSummary] = [:]

    // Activity and tools telemetry
    var toolUseCount: Int = 0
    /// Tool calls that came back as errors. Every retry after one of these is paid for.
    var toolErrorCount: Int = 0

    // Session intent, mode & title
    var aiTitle: String = ""
    var mode: String = ""
    var permissionMode: String = ""
    var lastPrompt: String = ""

    // Git PR integrations
    var prUrl: String = ""
    var prNumber: Int? = nil
    var prRepository: String = ""

    /// GitHub puts the number in the URL (`…/pull/1343`), so when a transcript
    /// reports the URL without `prNumber` we read it back from there. An
    /// unreadable URL yields no number — a placeholder would name a real but
    /// different pull request.
    var resolvedPRNumber: Int? {
        if let prNumber { return prNumber }
        let segments = prUrl.split(separator: "/", omittingEmptySubsequences: true)
        guard let pull = segments.lastIndex(of: "pull") else { return nil }
        let next = segments.index(after: pull)
        guard next < segments.endIndex else { return nil }
        return Int(segments[next])
    }

    var prTitle: String {
        guard let number = resolvedPRNumber else { return "GITHUB PULL REQUEST" }
        return "GITHUB PULL REQUEST #\(number)"
    }

    var prSubtitle: String { prRepository.isEmpty ? prUrl : prRepository }

    /// The link to hand to the system, or nil. Transcripts are shareable, so
    /// `prUrl` is attacker-influenced: anything but http(s) — `file://`,
    /// `javascript:` — is refused rather than launched on click.
    var prLink: URL? {
        let trimmed = prUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    // Code velocity & project impact
    var linesAdded: Int = 0
    var linesRemoved: Int = 0

    // Latency & performance split
    var apiDurationMs: Int = 0
    var toolDurationMs: Int = 0
    var totalDurationMs: Int = 0

    /// Set when Claude Code priced a model it doesn't have a rate for: the reported
    /// cost is then a lower bound, and the UI must not present it as exact.
    var hasUnknownModelCost: Bool = false

    /// Subagents this session ran, from `agent-name` records.
    private(set) var subagents: [String] = []
    /// Files Claude Code checkpointed a change to, from `file-history-delta` records.
    private(set) var filesModified: Set<String> = []

    // Web & MCP ecosystem
    var webSearchRequests: Int = 0
    var mcpServers: [String] = []
    var versionBase: String = ""

    var displayTitle: String {
        if !aiTitle.isEmpty { return aiTitle }
        return project
    }

    var netLines: Int {
        linesAdded - linesRemoved
    }

    /// False when at least one model in this session had no known price — the cost
    /// figure is then a floor, not a total.
    var costIsComplete: Bool { !hasUnknownModelCost }

    var filesModifiedCount: Int { filesModified.count }

    /// Records a subagent run, ignoring blanks and duplicates. Sorted so the roster
    /// does not reshuffle between renders.
    mutating func noteSubagent(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !subagents.contains(trimmed) else { return }
        subagents.append(trimmed)
        subagents.sort()
    }

    mutating func noteFileModified(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filesModified.insert(trimmed)
    }

    /// Resolves a `file-history-delta` record to an absolute path.
    ///
    /// `trackingPath` is relative to the session's cwd, so on its own it is ambiguous
    /// across projects. `realParentDir` is the absolute directory the file lives in,
    /// so combining it with the file name is unambiguous regardless of nesting.
    mutating func noteFileModified(trackingPath: String, realParentDir: String?) {
        let name = URL(fileURLWithPath: trackingPath).lastPathComponent
        guard !name.isEmpty else { return }
        if let realParentDir, !realParentDir.isEmpty {
            noteFileModified(URL(fileURLWithPath: realParentDir).appendingPathComponent(name).path)
        } else {
            noteFileModified(trackingPath)
        }
    }

    var apiTimeRatio: Double {
        let sum = apiDurationMs + toolDurationMs
        guard sum > 0 else { return 0 }
        return Double(apiDurationMs) / Double(sum)
    }

    /// Billed tokens. `thinkingTokens` is a breakdown of `outputTokens`, not an
    /// additional bucket, so it is reported separately and never added in here.
    var totalTokens: Int {
        let sum = inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
        if sum > 0 { return sum }
        return modelUsages.values.map(\.totalTokens).reduce(0, +)
    }

    var cacheHitRatio: Double {
        let total = cacheReadTokens + inputTokens
        guard total > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(total)
    }

    /// Total cost reported by Claude Code itself — never a locally priced estimate.
    ///
    /// Every source here is already a running total for the whole session, so they are
    /// reconciled with `max`. Summing the cost ledger (the previous behaviour) multiplied
    /// a session's cost by however many checkpoints it wrote.
    var totalCost: Double {
        var best = costLedger.total
        if let liveTotalCost { best = max(best, liveTotalCost) }
        let modelSum = modelUsages.values.map(\.costUSD).reduce(0, +)
        return max(best, modelSum)
    }

    /// Spend attributable to a window, and whether that attribution is exact.
    ///
    /// `totalCost` is used as the session's current running total rather than the
    /// ledger's own latest value: the statusline pushes a fresh figure every couple of
    /// seconds while `cost-state` checkpoints land rarely, so reading the ledger alone
    /// reported a stale number — and marked it exact.
    func spend(since cutoff: Date) -> (amount: Double, isExact: Bool) {
        if !costLedger.isEmpty {
            let windowed = costLedger.spend(since: cutoff, sessionStart: sessionStart)
            let baseline = costLedger.total - windowed.amount
            return (max(0, totalCost - baseline), windowed.isExact)
        }
        // No checkpoints: the only honest fallback is "did this session run in the
        // window at all", which cannot separate out spend from an earlier day.
        let ran = (sessionStart ?? lastSeen ?? .distantPast) >= cutoff
        guard totalCost > 0 else { return (0, true) }
        if ran { return (totalCost, sessionStart != nil) }
        guard (lastSeen ?? .distantPast) >= cutoff else { return (0, true) }
        return (totalCost, false)
    }

    /// Exact model from the JSON payload — no hardcoded vendor mapping.
    var displayModel: String {
        if ClaudeModelPicker.isReal(model) { return model }
        if let dominant = ClaudeModelPicker.dominant(in: modelUsages) { return dominant }
        return "unknown"
    }

    var isActive: Bool {
        guard let lastSeen else { return false }
        return lastSeen.timeIntervalSinceNow > -180
    }

    var contextFraction: Double {
        let total = max(1, contextTotalTokens)
        return min(Double(contextTokens) / Double(total), 1)
    }

    /// Real cumulative cost checkpoints, oldest first — empty when Claude Code has
    /// not written any. Views must hide the trend rather than pad it with zeros.
    var sparkline: [Double] {
        costLedger.recentCumulative
    }

    /// Best known start of the session: Claude Code's own figure, else the first
    /// transcript line.
    var startedAt: Date? {
        guard let sessionStart else { return firstSeen }
        guard let firstSeen else { return sessionStart }
        return min(sessionStart, firstSeen)
    }

    /// Wall-clock length of the session, when a start is known.
    var duration: TimeInterval? {
        guard let startedAt, let lastSeen, lastSeen > startedAt else { return nil }
        return lastSeen.timeIntervalSince(startedAt)
    }
}

struct ActivityEntry: Identifiable {
    /// Three real categories plus a status case. Deliberately not one hue per
    /// command name — `.run` is the honest "generic shell command" bucket
    /// rather than an invented color, and `.error` is a status, not a category.
    enum Kind: Hashable, CaseIterable {
        case edit, git, build, run, error

        var label: String {
            switch self {
            case .edit:  return "EDITS"
            case .git:   return "GIT"
            case .build: return "BUILD"
            case .run:   return "SHELL"
            case .error: return "ERRORS"
            }
        }

        /// Classifies a real shell command by its leading tokens.
        static func forCommand(_ command: String) -> Kind {
            let lower = command.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "git" || lower.hasPrefix("git ") { return .git }
            let toolchain = [
                "swift build", "swift test", "xcodebuild", "make", "cmake",
                "cargo build", "cargo test", "go build", "go test",
                "npm run build", "npm test", "yarn build", "pnpm build",
                "tsc", "gradle", "pytest",
            ]
            if toolchain.contains(where: { lower.contains($0) }) { return .build }
            return .run
        }
    }

    let id = UUID()
    let timestamp: Date
    let project: String
    let sessionId: String
    let kind: Kind
    let text: String
}

/// One real cost-bearing turn — the source event for the cost-fountain particle burst.
struct CostEvent: Identifiable {
    let id = UUID()
    let sessionId: String
    let amount: Double
    let timestamp: Date
}

// MARK: - GRDB Records for Claude Code Integration

/// Persisted snapshot of a live Claude Code session, written by the `flightdeck statusline`
/// CLI and observed by the GUI via GRDB `ValueObservation`.
struct SessionLiveRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_live"

    var sessionId: String
    var project: String
    var branch: String
    var model: String
    var contextTokens: Int
    var contextTotalTokens: Int = ContextWindowResolver.defaultWindow
    var totalCostUsd: Double
    var lastFile: String
    var updatedAt: Date
}

/// One event from a Claude Code hook (SessionStart, Stop, PreToolUse, PostToolUse),
/// written by the `flightdeck hook` CLI and read by the GUI for the Activity feed.
struct AIEventRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "ai_events"

    var id: Int64?
    var sessionId: String
    var event: String
    var toolName: String?
    var detail: String?
    var timestamp: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// JSON payload piped to stdin by Claude Code's statusline feature.
/// Fields match the documented schema as of September 2026.
struct StatuslinePayload: Decodable {
    let session_id: String?
    let model: String?
    let total_cost: Double?
    let context_window: ContextWindow?
    let cwd: String?
    let git_branch: String?

    struct ContextWindow: Decodable {
        let used: Int?
        let total: Int?
    }
}

