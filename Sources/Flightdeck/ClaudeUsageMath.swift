import Foundation

// MARK: - Cost snapshots

/// One `cost-state` record from a Claude Code transcript.
///
/// The value is the session's **cumulative** cost at that moment, not the cost of
/// one turn — Claude Code rewrites the whole running total each time it checkpoints.
struct CostSnapshot: Equatable, Sendable {
    let at: Date
    let cumulativeUSD: Double
}

/// Ledger of cumulative cost snapshots for a single session.
///
/// Adding snapshots together would multiply a session's real cost by the number of
/// checkpoints it happened to write, so every read here is expressed as either the
/// newest cumulative value or a delta between two of them.
struct CostSnapshotLedger: Equatable, Sendable {
    /// Sorted oldest-first; at most one entry per distinct timestamp.
    private(set) var snapshots: [CostSnapshot] = []

    var isEmpty: Bool { snapshots.isEmpty }

    /// The session's cost so far — the largest cumulative value seen.
    ///
    /// Uses the maximum rather than the last element so a late-arriving stale
    /// checkpoint can never walk the displayed total backwards.
    var total: Double {
        snapshots.map(\.cumulativeUSD).max() ?? 0
    }

    /// The 12 most recent cumulative values, oldest first, for a trend sparkline.
    /// Empty when there is nothing real to draw — callers must not substitute zeros.
    var recentCumulative: [Double] {
        snapshots.suffix(12).map(\.cumulativeUSD)
    }

    mutating func record(_ cumulativeUSD: Double, at date: Date) {
        guard cumulativeUSD.isFinite, cumulativeUSD >= 0 else { return }
        if let idx = snapshots.firstIndex(where: { $0.at == date }) {
            // Same checkpoint rewritten — keep the higher figure, never stack them.
            if cumulativeUSD > snapshots[idx].cumulativeUSD {
                snapshots[idx] = CostSnapshot(at: date, cumulativeUSD: cumulativeUSD)
            }
            return
        }
        snapshots.append(CostSnapshot(at: date, cumulativeUSD: cumulativeUSD))
        snapshots.sort { $0.at < $1.at }
    }

    /// Spend attributable to the window starting at `cutoff`.
    ///
    /// `isExact` is false when the window cannot be isolated — no checkpoint exists
    /// from before `cutoff` and the session predates it, so the returned amount is an
    /// upper bound that may include earlier days. Callers surface that rather than
    /// silently presenting a guess as a measurement.
    func spend(since cutoff: Date, sessionStart: Date?) -> (amount: Double, isExact: Bool) {
        guard let latest = snapshots.max(by: { $0.cumulativeUSD < $1.cumulativeUSD }) else {
            return (0, true)
        }
        if let baseline = snapshots.last(where: { $0.at < cutoff }) {
            return (max(0, latest.cumulativeUSD - baseline.cumulativeUSD), true)
        }
        if let sessionStart, sessionStart >= cutoff {
            return (latest.cumulativeUSD, true)
        }
        return (latest.cumulativeUSD, false)
    }

    /// Drops snapshots older than `date`, **keeping the newest one before it** as the
    /// baseline every delta is measured against.
    mutating func prune(before date: Date) {
        guard let baselineIdx = snapshots.lastIndex(where: { $0.at < date }) else { return }
        guard baselineIdx > 0 else { return }
        snapshots.removeFirst(baselineIdx)
    }
}

// MARK: - Context window

/// Where a session's context-window size came from, so the UI can distinguish a
/// measured number from an inferred one.
enum ContextWindowSource: Equatable, Sendable {
    /// Reported by Claude Code's statusline payload — authoritative.
    case statusline
    /// Derived from the largest context this model has actually been observed holding.
    case inferred
    /// Nothing observed yet; the conservative default.
    case fallback
}

struct ResolvedContextWindow: Equatable, Sendable {
    let total: Int
    let source: ContextWindowSource
}

/// Resolves how large a model's context window is.
///
/// Claude Code's transcripts record the model as e.g. `claude-opus-5` with no hint of
/// whether it is the 200K or the 1M variant, so a fixed constant is wrong for anyone
/// on a long-context model. This learns the answer from the largest context each model
/// has actually been seen holding and snaps it up to the nearest real tier.
struct ContextWindowResolver: Equatable, Sendable {
    static let defaultWindow = 200_000
    /// Context sizes Claude models are actually sold in, ascending.
    static let knownTiers = [200_000, 500_000, 1_000_000]

    private var highWaterMark: [String: Int] = [:]
    private var authoritative: [String: Int] = [:]

    /// Feed in a real measured context size for a model.
    mutating func observe(model: String, contextTokens: Int) {
        let key = Self.normalize(model)
        guard !key.isEmpty, contextTokens > 0 else { return }
        highWaterMark[key] = max(highWaterMark[key] ?? 0, contextTokens)
    }

    /// Record a window size Claude Code itself reported — trusted over inference.
    mutating func recordAuthoritative(model: String, total: Int) {
        let key = Self.normalize(model)
        guard !key.isEmpty, total > 0 else { return }
        authoritative[key] = max(authoritative[key] ?? 0, total)
    }

    func resolve(model: String) -> ResolvedContextWindow {
        let key = Self.normalize(model)
        guard !key.isEmpty else {
            return ResolvedContextWindow(total: Self.defaultWindow, source: .fallback)
        }
        if let exact = authoritative[key] {
            return ResolvedContextWindow(total: exact, source: .statusline)
        }
        guard let observed = highWaterMark[key] else {
            return ResolvedContextWindow(total: Self.defaultWindow, source: .fallback)
        }
        return ResolvedContextWindow(total: Self.tier(atLeast: observed), source: .inferred)
    }

    /// Smallest real tier that fits `observed`; beyond the known tiers, round up to a
    /// whole million rather than clamping and reporting an impossible >100% fill.
    static func tier(atLeast observed: Int) -> Int {
        if let tier = knownTiers.first(where: { $0 >= observed }) { return tier }
        let millions = (observed + 999_999) / 1_000_000
        return millions * 1_000_000
    }

    /// Claude Code sometimes suffixes a long-context variant (`claude-opus-5[1m]`);
    /// the base name is what transcripts and statusline payloads agree on.
    private static func normalize(_ model: String) -> String {
        var name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let bracket = name.firstIndex(of: "[") {
            name = String(name[name.startIndex..<bracket])
        }
        return name
    }
}

// MARK: - Model selection

/// Chooses which model to show for a session that used more than one.
enum ClaudeModelPicker {
    /// Claude Code writes this for internal bookkeeping messages; it is not a model
    /// the user ran and must never appear in the UI.
    static let syntheticMarker = "<synthetic>"

    static func isReal(_ model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != syntheticMarker
    }

    /// The model that did the most work, by billed input + output tokens.
    ///
    /// Swift dictionaries have no stable order, so picking `keys.first` gave a
    /// different answer on every launch; ties break alphabetically to stay stable.
    static func dominant(in usages: [String: ModelUsageSummary]) -> String? {
        usages
            .filter { isReal($0.key) }
            .max { lhs, rhs in
                let l = lhs.value.inputTokens + lhs.value.outputTokens
                let r = rhs.value.inputTokens + rhs.value.outputTokens
                if l != r { return l < r }
                return lhs.key > rhs.key
            }?
            .key
    }
}
