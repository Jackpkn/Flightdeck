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

/// Live aggregate for one session, rebuilt incrementally as its log file grows.
struct SessionAgg: Identifiable {
    let id: String
    var project: String
    var branch: String = ""
    var model: String = ""
    var lastFile: String = ""
    var lastSeen: Date?
    var lastErrorAt: Date?
    var contextTokens: Int = 0
    /// (timestamp, cost-in-usd) for every assistant turn seen, trimmed to the last 7 days.
    var costLedger: [(Date, Double)] = []
    var liveTotalCost: Double? = nil

    var totalCost: Double {
        if let liveTotalCost, liveTotalCost > 0 {
            return max(liveTotalCost, costLedger.reduce(0) { $0 + $1.1 })
        }
        return costLedger.reduce(0) { $0 + $1.1 }
    }

    var isActive: Bool {
        guard let lastSeen else { return false }
        return lastSeen.timeIntervalSinceNow > -180
    }

    var contextFraction: Double {
        min(Double(contextTokens) / 200_000, 1)
    }

    var burnRatePerMin: Double {
        let cutoff = Date().addingTimeInterval(-120)
        let recent = costLedger.filter { $0.0 > cutoff }.reduce(0) { $0 + $1.1 }
        return recent / 2.0
    }

    /// 12-point trend for the sparkline, oldest first.
    var sparkline: [Double] {
        guard !costLedger.isEmpty else { return Array(repeating: 0, count: 12) }
        let recent = costLedger.suffix(12).map(\.1)
        let pad = Array(repeating: 0.0, count: max(0, 12 - recent.count))
        return pad + recent
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

