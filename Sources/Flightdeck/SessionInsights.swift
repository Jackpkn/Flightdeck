import Foundation

// MARK: - Waste report

/// Something about a session worth a second look, with the measurement behind it.
///
/// Every finding states what was actually observed. `attributableCost` is only set
/// where a real dollar figure belongs to the finding — Claude Code prices a session,
/// not an individual failed tool call, so most findings deliberately carry none
/// rather than inventing a split.
struct WasteFinding: Identifiable {
    enum Kind: String {
        case noCodeChange
        case toolFailures
        case cacheChurn
        case contextPressure

        var title: String {
            switch self {
            case .noCodeChange:    return "SPEND, NO CODE CHANGE"
            case .toolFailures:    return "TOOL CALLS FAILING"
            case .cacheChurn:      return "CONTEXT KEEPS REBUILDING"
            case .contextPressure: return "WORKING NEAR THE CONTEXT LIMIT"
            }
        }

        /// What to actually do about it.
        var advice: String {
            switch self {
            case .noCodeChange:
                return "Fine for research or review. Worth checking if you expected code out of it."
            case .toolFailures:
                return "Every failed call is billed and usually retried. Check permissions, paths, and hook timeouts."
            case .cacheChurn:
                return "Cache writes cost more than reads. Long-lived sessions with stable context re-read instead of rebuilding."
            case .contextPressure:
                return "Quality drops near the ceiling and auto-compaction is imminent. Split the work or /compact sooner."
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let sessionId: String
    let project: String
    let title: String
    /// Measured evidence, in the session's own numbers.
    let detail: String
    /// Real cost this finding accounts for, when one can honestly be assigned.
    let attributableCost: Double?
    /// Session cost, shown for context even when none of it is attributable.
    let sessionCost: Double

    /// Display-only copy for presentation mode. Both costs pass through: the
    /// whole point of a waste finding is the number attached to it.
    func redacted(by redactor: Redactor) -> WasteFinding {
        guard redactor.isEnabled else { return self }
        return WasteFinding(
            kind: kind,
            sessionId: sessionId,
            project: redactor.project(project),
            title: redactor.title(title, project: project),
            detail: detail,
            attributableCost: attributableCost,
            sessionCost: sessionCost
        )
    }
}

/// Scans sessions for spend that may not have bought anything.
struct WasteReport {

    // Thresholds are stated here rather than buried in the checks, so the bar for
    // calling something wasteful is visible and arguable.

    /// Below this a session is rounding error, not a finding.
    static let minimumCost = 0.05
    /// Failure rate at which retries stop being background noise.
    static let toolFailureRate = 0.10
    /// Tool calls needed before a failure rate means anything.
    static let minimumToolCalls = 10
    /// Share of cache traffic that is writes rather than reads.
    static let cacheChurnRatio = 0.25
    /// Enough cache traffic for the ratio to be meaningful.
    static let minimumCacheTokens = 100_000
    /// Context fill at which auto-compaction is close and quality degrades.
    static let contextPressureFraction = 0.9

    let findings: [WasteFinding]

    init(sessions: [SessionAgg]) {
        var found: [WasteFinding] = []

        for session in sessions {
            let cost = session.totalCost
            guard cost >= Self.minimumCost else { continue }

            found.append(contentsOf: Self.check(session, cost: cost))
        }

        // Most expensive first; session id breaks ties so the list doesn't reshuffle.
        findings = found.sorted { lhs, rhs in
            if lhs.sessionCost != rhs.sessionCost { return lhs.sessionCost > rhs.sessionCost }
            if lhs.sessionId != rhs.sessionId { return lhs.sessionId < rhs.sessionId }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    private static func check(_ session: SessionAgg, cost: Double) -> [WasteFinding] {
        var out: [WasteFinding] = []

        func add(_ kind: WasteFinding.Kind, _ detail: String, attributable: Double? = nil) {
            out.append(WasteFinding(
                kind: kind,
                sessionId: session.id,
                project: session.project,
                title: kind.title,
                detail: detail,
                attributableCost: attributable,
                sessionCost: cost
            ))
        }

        // 1. Money spent, nothing written. The whole session cost is attributable —
        //    that is a measured fact, not an estimate.
        let producedCode = session.filesModifiedCount > 0
            || session.linesAdded > 0
            || session.linesRemoved > 0
        if !producedCode {
            add(.noCodeChange,
                "\(Formatters.usd(cost)) spent · no files changed · \(session.toolUseCount) tool calls",
                attributable: cost)
        }

        // 2. Failing tool calls. Billed, and almost always retried.
        if session.toolUseCount >= minimumToolCalls, session.toolErrorCount > 0 {
            let rate = Double(session.toolErrorCount) / Double(session.toolUseCount)
            if rate >= toolFailureRate {
                add(.toolFailures,
                    "\(session.toolErrorCount) of \(session.toolUseCount) tool calls failed (\(Int(rate * 100))%)")
            }
        }

        // 3. Cache writes cost several times what reads do, so a session that keeps
        //    re-establishing its context pays repeatedly for the same tokens.
        let cacheTotal = session.cacheReadTokens + session.cacheCreationTokens
        if cacheTotal >= minimumCacheTokens {
            let writeShare = Double(session.cacheCreationTokens) / Double(cacheTotal)
            if writeShare >= cacheChurnRatio {
                add(.cacheChurn,
                    "\(Int(writeShare * 100))% of cache traffic was writes · "
                    + "\(Formatters.tokens(session.cacheCreationTokens)) rebuilt vs "
                    + "\(Formatters.tokens(session.cacheReadTokens)) reused")
            }
        }

        // 4. Only meaningful when the window size is measured or inferred — a
        //    defaulted guess would flag every long-context session.
        if session.contextWindowSource != .fallback,
           session.contextFraction >= contextPressureFraction {
            add(.contextPressure,
                "\(Formatters.tokens(session.contextTokens)) of "
                + "\(Formatters.tokens(session.contextTotalTokens)) used "
                + "(\(Int(session.contextFraction * 100))%)")
        }

        return out
    }

    /// Sum of the costs that genuinely belong to a finding. Deliberately excludes
    /// findings with no honest dollar attribution rather than guessing at a share.
    var totalAttributableCost: Double {
        findings.compactMap(\.attributableCost).reduce(0, +)
    }

    var isEmpty: Bool { findings.isEmpty }

    func findings(ofKind kind: WasteFinding.Kind) -> [WasteFinding] {
        findings.filter { $0.kind == kind }
    }
}

// MARK: - Churn hotspots

/// A file Claude Code has come back to across multiple sessions.
struct ChurnHotspot: Identifiable {
    let path: String
    let sessionCount: Int
    let projects: [String]

    var id: String { path }

    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }

    /// Display-only copy. `sessionCount` is the finding, so it is untouched.
    func redacted(by redactor: Redactor) -> ChurnHotspot {
        guard redactor.isEnabled else { return self }
        return ChurnHotspot(
            path: redactor.path(path),
            sessionCount: sessionCount,
            projects: projects.map(redactor.project)
        )
    }
}

/// Finds files that repeatedly get reworked.
///
/// Built from Claude Code's own `file-history-delta` checkpoints, so it reflects
/// files actually written rather than files merely read or mentioned. A file that
/// keeps coming back is usually a sign the codebase is hard to change there.
enum ChurnAnalyzer {
    /// One session touching a file is just work; two or more is a pattern.
    static let minimumSessions = 2

    static func hotspots(in sessions: [SessionAgg], limit: Int = 20) -> [ChurnHotspot] {
        var sessionCounts: [String: Int] = [:]
        var projects: [String: Set<String>] = [:]

        for session in sessions {
            for path in session.filesModified {
                sessionCounts[path, default: 0] += 1
                projects[path, default: []].insert(session.project)
            }
        }

        var hotspots: [ChurnHotspot] = []
        for (path, count) in sessionCounts where count >= minimumSessions {
            let spanned: [String] = projects[path].map { Array($0).sorted() } ?? []
            hotspots.append(ChurnHotspot(path: path, sessionCount: count, projects: spanned))
        }
        // Path breaks ties so repeated renders keep the same order.
        hotspots.sort { lhs, rhs in
            lhs.sessionCount == rhs.sessionCount ? lhs.path < rhs.path : lhs.sessionCount > rhs.sessionCount
        }
        return Array(hotspots.prefix(limit))
    }
}
