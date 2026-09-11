import Foundation

/// How often a Claude Code skill has been invoked, as recorded in `~/.claude.json`.
struct ClaudeSkillUsage: Identifiable, Equatable, Sendable {
    let name: String
    let usageCount: Int
    let lastUsedAt: Date?

    var id: String { name }
}

/// Reads the `skillUsage` map Claude Code maintains in `~/.claude.json`.
enum ClaudeSkillUsageReader {

    static func load(from url: URL = ClaudeUsageLimitsReader.defaultURL()) -> [ClaudeSkillUsage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data)
    }

    /// Ranked most-used first; ties break by name so the order is stable.
    static func parse(_ data: Data) -> [ClaudeSkillUsage] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let usage = root["skillUsage"] as? [String: Any]
        else { return [] }

        return usage.compactMap { name, raw -> ClaudeSkillUsage? in
            guard
                let entry = raw as? [String: Any],
                let count = entry["usageCount"] as? Int, count > 0
            else { return nil }
            let lastMs = entry["lastUsedAt"] as? Double
            return ClaudeSkillUsage(
                name: name,
                usageCount: count,
                lastUsedAt: lastMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            )
        }
        .sorted { lhs, rhs in
            lhs.usageCount == rhs.usageCount ? lhs.name < rhs.name : lhs.usageCount > rhs.usageCount
        }
    }
}
