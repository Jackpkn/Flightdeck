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
                return "Quality drops rapidly past 85% context pressure before auto-compaction. Split the task into subtasks or commit a clean handoff."
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
    static let contextPressureFraction = 0.85

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

/// Classification of why a file keeps getting rewritten across sessions.
enum ChurnDiagnosis: String, Codable, Sendable {
    /// File rewritten across sessions with high frequency or failing tool retries.
    case missingInstructions = "MISSING INSTRUCTIONS"
    /// File rewritten in sessions that reached >=85% context pressure or compaction.
    case taskTooLarge = "TASK TOO LARGE"
    /// File rewritten across multiple distinct projects or disparate boundaries.
    case architecturalCoupling = "ARCHITECTURAL COUPLING"
    /// Normal sequential changes across consecutive sessions.
    case activeIteration = "ACTIVE ITERATION"

    var advice: String {
        switch self {
        case .missingInstructions:
            return "File repeatedly modified across sessions. Add explicit constraints, architecture rules, and test commands to CLAUDE.md."
        case .taskTooLarge:
            return "Rewritten under heavy context pressure (≥85%). Break the prompt down into smaller, single-responsibility subtasks."
        case .architecturalCoupling:
            return "File is touched across multiple project boundaries. Consider extracting shared utilities or decoupling interfaces."
        case .activeIteration:
            return "Normal ongoing feature development."
        }
    }
}

/// A file Claude Code has come back to across multiple sessions.
struct ChurnHotspot: Identifiable, Sendable {
    let path: String
    let sessionCount: Int
    let projects: [String]
    let diagnosis: ChurnDiagnosis
    let suggestedAction: String

    var id: String { path }

    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }

    init(
        path: String,
        sessionCount: Int,
        projects: [String],
        diagnosis: ChurnDiagnosis = .activeIteration,
        suggestedAction: String? = nil
    ) {
        self.path = path
        self.sessionCount = sessionCount
        self.projects = projects
        self.diagnosis = diagnosis
        self.suggestedAction = suggestedAction ?? diagnosis.advice
    }

    /// Display-only copy. `sessionCount` and diagnosis are the finding, so they are untouched.
    func redacted(by redactor: Redactor) -> ChurnHotspot {
        guard redactor.isEnabled else { return self }
        return ChurnHotspot(
            path: redactor.path(path),
            sessionCount: sessionCount,
            projects: projects.map(redactor.project),
            diagnosis: diagnosis,
            suggestedAction: suggestedAction
        )
    }

    /// Generates a tailored, copy-pasteable rule block for `CLAUDE.md`.
    var claudeMdSnippet: String {
        let name = fileName
        switch diagnosis {
        case .missingInstructions:
            return """
            ## File Rule: \(name)
            - Target: `\(path)` (churned across \(sessionCount) sessions)
            - Pattern: \(diagnosis.rawValue)
            - Upfront Specification: Inspect existing tests and invariants before editing.
            - Explicit Constraints: Preserve existing public APIs and verify with project tests immediately after modifying.
            """
        case .taskTooLarge:
            return """
            ## Context & Task Boundary: \(name)
            - Target: `\(path)` (churned across \(sessionCount) sessions)
            - Pattern: \(diagnosis.rawValue) (reached ≥85% context pressure or triggered compaction)
            - Strategy: Split implementation into atomic, single-responsibility commits before modifying `\(name)`.
            - Compact Early: If context window approaches 80%, end the session or issue `/compact` before editing complex logic.
            """
        case .architecturalCoupling:
            return """
            ## Architecture & Boundaries: \(name)
            - Target: `\(path)` (churned across \(sessionCount) sessions in \(projects.joined(separator: ", ")))
            - Pattern: \(diagnosis.rawValue)
            - Modular Rule: Do not add cross-project dependencies directly into `\(name)`. Extract shared protocols or decouple caller contracts.
            """
        case .activeIteration:
            return """
            ## Active Development: \(name)
            - Target: `\(path)` (active across \(sessionCount) sessions)
            - Test Invariants: Ensure all unit tests pass before committing changes.
            """
        }
    }
}

/// Finds files that repeatedly get reworked and diagnoses root causes.
///
/// Built from Claude Code's own `file-history-delta` checkpoints, so it reflects
/// files actually written rather than files merely read or mentioned.
enum ChurnAnalyzer {
    /// One session touching a file is just work; two or more is a pattern.
    static let minimumSessions = 2

    static func hotspots(in sessions: [SessionAgg], limit: Int = 20) -> [ChurnHotspot] {
        var fileSessions: [String: [SessionAgg]] = [:]
        var sessionCounts: [String: Int] = [:]
        var projects: [String: Set<String>] = [:]

        for session in sessions {
            for path in session.filesModified {
                fileSessions[path, default: []].append(session)
                sessionCounts[path, default: 0] += 1
                projects[path, default: []].insert(session.project)
            }
        }

        var hotspots: [ChurnHotspot] = []
        for (path, count) in sessionCounts where count >= minimumSessions {
            let spanned: [String] = projects[path].map { Array($0).sorted() } ?? []
            let touchingSessions = fileSessions[path] ?? []

            // Diagnostic heuristics
            let diagnosis: ChurnDiagnosis
            if spanned.count > 1 {
                // Spans multiple distinct projects
                diagnosis = .architecturalCoupling
            } else if touchingSessions.contains(where: { $0.contextFraction >= WasteReport.contextPressureFraction }) {
                // Touched during sessions experiencing >= 85% context pressure / impending compaction
                diagnosis = .taskTooLarge
            } else if count >= 3 || touchingSessions.contains(where: { $0.toolErrorCount > 3 }) {
                // Repeatedly churned across 3+ sessions or with failing tool retries
                diagnosis = .missingInstructions
            } else {
                diagnosis = .activeIteration
            }

            hotspots.append(ChurnHotspot(
                path: path,
                sessionCount: count,
                projects: spanned,
                diagnosis: diagnosis,
                suggestedAction: diagnosis.advice
            ))
        }
        // Path breaks ties so repeated renders keep the same order.
        hotspots.sort { lhs, rhs in
            lhs.sessionCount == rhs.sessionCount ? lhs.path < rhs.path : lhs.sessionCount > rhs.sessionCount
        }
        return Array(hotspots.prefix(limit))
    }
}

