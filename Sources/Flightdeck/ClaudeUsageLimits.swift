import Foundation

/// One rate-limit window reported by Claude Code — a five-hour session budget, a
/// weekly budget, or a per-model weekly budget.
///
/// Claude Code caches these in `~/.claude.json` under `cachedUsageUtilization`;
/// they are the only place the account's real limit consumption is visible locally.
struct ClaudeUsageLimit: Identifiable, Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case normal, warning, critical

        /// Claude Code reports `severity` itself, but leaves it at `normal` well past
        /// the point a user would want warning — this escalates on the number when the
        /// payload has not already escalated.
        static func forPercent(_ percent: Int) -> Severity {
            if percent >= 90 { return .critical }
            if percent >= 75 { return .warning }
            return .normal
        }

        static func max(_ lhs: Severity, _ rhs: Severity) -> Severity {
            let rank: [Severity: Int] = [.normal: 0, .warning: 1, .critical: 2]
            return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
        }
    }

    let kind: String
    let group: String
    let percent: Int
    let severity: Severity
    let resetsAt: Date?
    /// True for the window Claude Code is currently drawing against.
    let isActive: Bool

    var id: String { kind }

    /// Human label. Known kinds get a curated name; anything Anthropic adds later is
    /// humanised rather than dropped, so a new limit type still shows up.
    var label: String {
        switch kind {
        case "session":       return "5-HOUR SESSION"
        case "weekly_all":    return "WEEKLY · ALL MODELS"
        case "weekly_opus":   return "WEEKLY · OPUS"
        case "weekly_sonnet": return "WEEKLY · SONNET"
        default:
            return kind.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Seconds until this window resets, or nil once it already has.
    func timeUntilReset(now: Date = Date()) -> TimeInterval? {
        guard let resetsAt, resetsAt > now else { return nil }
        return resetsAt.timeIntervalSince(now)
    }

    var fraction: Double { Swift.min(1.0, Swift.max(0, Double(percent) / 100.0)) }

    /// Severity reconciled with the raw percentage — whichever is more serious.
    var effectiveSeverity: Severity {
        Severity.max(severity, .forPercent(percent))
    }
}

/// A point-in-time reading of the account's limit consumption.
struct ClaudeUsageSnapshot: Equatable, Sendable {
    /// When Claude Code last refreshed this from the server — not when we read it.
    let fetchedAt: Date
    let limits: [ClaudeUsageLimit]
    /// Whether pay-as-you-go extra usage is switched on for the account.
    let extraUsageEnabled: Bool

    /// Claude Code refreshes this cache while a session runs, so anything older than
    /// a few minutes means no session has been active — the numbers are a memory,
    /// not a live reading, and the UI must say so.
    static let freshnessWindow: TimeInterval = 10 * 60

    func age(now: Date = Date()) -> TimeInterval {
        Swift.max(0, now.timeIntervalSince(fetchedAt))
    }

    func isStale(now: Date = Date()) -> Bool {
        age(now: now) > Self.freshnessWindow
    }

    /// Live windows only, most-consumed first.
    func liveLimits(now: Date = Date()) -> [ClaudeUsageLimit] {
        limits.filter { !$0.isExpired(now: now) }.sorted { $0.percent > $1.percent }
    }

    /// The window closest to its ceiling — the one worth putting on screen.
    func headline(now: Date = Date()) -> ClaudeUsageLimit? {
        liveLimits(now: now).first
    }
}

/// Reads Claude Code's cached rate-limit utilization out of `~/.claude.json`.
enum ClaudeUsageLimitsReader {

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ raw: Any?) -> Date? {
        guard let string = raw as? String, !string.isEmpty else { return nil }
        return isoWithFraction.date(from: string) ?? iso.date(from: string)
    }

    static func load(from url: URL) -> ClaudeUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    static func parse(_ data: Data) -> ClaudeUsageSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cached = root["cachedUsageUtilization"] as? [String: Any],
            let utilization = cached["utilization"] as? [String: Any]
        else { return nil }

        let fetchedAtMs = cached["fetchedAtMs"] as? Double ?? 0
        guard fetchedAtMs > 0 else { return nil }
        let fetchedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000.0)

        let extraUsage = utilization["extra_usage"] as? [String: Any]
        let extraEnabled = extraUsage?["is_enabled"] as? Bool ?? false

        let limits = parseLimitsArray(utilization) ?? parseLegacyWindows(utilization)
        guard !limits.isEmpty else { return nil }

        return ClaudeUsageSnapshot(fetchedAt: fetchedAt, limits: limits, extraUsageEnabled: extraEnabled)
    }

    /// Preferred source: the explicit `limits` array, which names each window and its
    /// group rather than encoding them as sibling keys.
    private static func parseLimitsArray(_ utilization: [String: Any]) -> [ClaudeUsageLimit]? {
        guard let raw = utilization["limits"] as? [[String: Any]], !raw.isEmpty else { return nil }
        let parsed = raw.compactMap { entry -> ClaudeUsageLimit? in
            guard let kind = entry["kind"] as? String, !kind.isEmpty else { return nil }
            let percent = entry["percent"] as? Int ?? 0
            let severityRaw = (entry["severity"] as? String) ?? "normal"
            return ClaudeUsageLimit(
                kind: kind,
                group: entry["group"] as? String ?? kind,
                percent: percent,
                severity: ClaudeUsageLimit.Severity(rawValue: severityRaw) ?? .normal,
                resetsAt: parseDate(entry["resets_at"]),
                isActive: entry["is_active"] as? Bool ?? false
            )
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// Older Claude Code versions only wrote sibling windows. The map is also full of
    /// internal codename buckets (`nimbus_quill`, `cinder_cove`, …) that mean nothing
    /// to a user, so only the two documented windows are read.
    private static func parseLegacyWindows(_ utilization: [String: Any]) -> [ClaudeUsageLimit] {
        let known: [(key: String, kind: String, group: String)] = [
            ("five_hour", "session", "session"),
            ("seven_day", "weekly_all", "weekly"),
            ("seven_day_opus", "weekly_opus", "weekly"),
            ("seven_day_sonnet", "weekly_sonnet", "weekly"),
        ]
        return known.compactMap { entry in
            guard
                let window = utilization[entry.key] as? [String: Any],
                let percent = window["utilization"] as? Int
            else { return nil }
            return ClaudeUsageLimit(
                kind: entry.kind,
                group: entry.group,
                percent: percent,
                severity: .forPercent(percent),
                resetsAt: parseDate(window["resets_at"]),
                isActive: entry.key == "five_hour"
            )
        }
    }
}
