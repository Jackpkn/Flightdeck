import Foundation
import Observation

/// Caches the git-measured outcome of each session.
///
/// Probing shells out to `git`, so results are computed off the main thread, cached
/// per session, and only recomputed when the session's tracked file set changes.
@Observable
final class SessionOutcomeStore {
    private(set) var outcomes: [String: GitOutcome] = [:]
    /// Sessions whose working directory is not a git repository — a real answer worth
    /// showing, distinct from "not measured yet".
    private(set) var notRepositories: Set<String> = []
    private(set) var isProbing = false

    /// Fingerprint of what each cached result was computed from.
    private var probedFingerprint: [String: Int] = [:]
    private let queue = DispatchQueue(label: "com.flightdeck.git-outcome", qos: .utility)

    @MainActor
    func refresh(sessions: [SessionAgg]) {
        // Only probe sessions that actually wrote files into a real directory.
        let pending = sessions.filter { session in
            guard !session.cwd.isEmpty, !session.filesModified.isEmpty else { return false }
            return probedFingerprint[session.id] != Self.fingerprint(session)
        }
        guard !pending.isEmpty else { return }

        isProbing = true
        let requests = pending.map {
            (id: $0.id, cwd: $0.cwd, files: $0.filesModified,
             since: $0.startedAt, until: $0.lastSeen, fingerprint: Self.fingerprint($0))
        }

        queue.async { [weak self] in
            var measured: [(String, GitOutcome?, Int)] = []
            for request in requests {
                let outcome = GitOutcomeProbe.probe(
                    cwd: request.cwd, files: request.files,
                    since: request.since, until: request.until
                )
                measured.append((request.id, outcome, request.fingerprint))
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for (id, outcome, fingerprint) in measured {
                    self.probedFingerprint[id] = fingerprint
                    if let outcome {
                        self.outcomes[id] = outcome
                        self.notRepositories.remove(id)
                    } else {
                        self.outcomes.removeValue(forKey: id)
                        self.notRepositories.insert(id)
                    }
                }
                self.isProbing = false
            }
        }
    }

    func outcome(for sessionId: String) -> GitOutcome? { outcomes[sessionId] }

    func isNotRepository(_ sessionId: String) -> Bool { notRepositories.contains(sessionId) }

    /// Cheap stand-in for "has anything worth re-measuring changed".
    private static func fingerprint(_ session: SessionAgg) -> Int {
        var hasher = Hasher()
        hasher.combine(session.filesModified.count)
        hasher.combine(session.cwd)
        hasher.combine(session.lastSeen?.timeIntervalSince1970.rounded() ?? 0)
        return hasher.finalize()
    }

    // MARK: - Portfolio rollup

    /// Cost-per-outcome across every measured session.
    struct Rollup {
        var sessionsMeasured = 0
        var totalCost: Double = 0
        var filesConsidered = 0
        var filesInHead = 0
        var filesDropped = 0
        var commits = 0

        var survivalRate: Double {
            guard filesConsidered > 0 else { return 0 }
            return Double(filesInHead) / Double(filesConsidered)
        }

        /// What each surviving file cost. Nil rather than a divide-by-zero placeholder.
        var costPerSurvivingFile: Double? {
            guard filesInHead > 0, totalCost > 0 else { return nil }
            return totalCost / Double(filesInHead)
        }

        var costPerCommit: Double? {
            guard commits > 0, totalCost > 0 else { return nil }
            return totalCost / Double(commits)
        }
    }

    func rollup(for sessions: [SessionAgg]) -> Rollup {
        var out = Rollup()
        for session in sessions {
            guard let outcome = outcomes[session.id], outcome.filesConsidered > 0 else { continue }
            out.sessionsMeasured += 1
            out.totalCost += session.totalCost
            out.filesConsidered += outcome.filesConsidered
            out.filesInHead += outcome.filesInHead
            out.filesDropped += outcome.filesDropped
            out.commits += outcome.commits ?? 0
        }
        return out
    }
}
