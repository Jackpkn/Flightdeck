import Foundation

/// Something worth interrupting the user for.
struct Alert: Identifiable, Equatable {
    enum Kind: String {
        case planLimit
        case budget
        case contextPressure
    }

    enum Severity: String {
        case warning, critical
    }

    let id = UUID()
    let kind: Kind
    let severity: Severity
    let title: String
    let body: String
    /// Stable key for the condition, so the same situation is not reported twice.
    let dedupeKey: String

    var isCritical: Bool { severity == .critical }

    static func == (lhs: Alert, rhs: Alert) -> Bool {
        lhs.dedupeKey == rhs.dedupeKey && lhs.severity == rhs.severity
    }
}

/// Decides when a condition is worth telling the user about.
///
/// Kept as a pure value type with an injectable `now` so the thresholds and the
/// "don't repeat yourself" behaviour are testable without a notification centre.
/// Delivery is a separate concern — see `NotificationCenterDelivery`.
struct AlertEngine {

    // Thresholds are stated here rather than buried in the checks.

    /// Plan-limit consumption at which acting is still a free choice.
    static let limitWarning = 0.80
    /// Consumption at which the window is effectively gone.
    static let limitCritical = 0.95
    /// Share of the daily budget that warrants a heads-up.
    static let budgetWarning = 0.80
    /// Context fill at which auto-compaction is imminent and quality degrades.
    static let contextPressure = 0.90
    /// Consumption below which a previously-raised alert is considered cleared.
    static let clearBelow = 0.60

    /// Severity a condition was last reported at, keyed by `dedupeKey`.
    private var reported: [String: Alert.Severity] = [:]

    /// Evaluates every condition and returns only what has not already been said.
    mutating func evaluate(
        usage: ClaudeUsageSnapshot?,
        sessions: [SessionAgg],
        todaySpend: Double,
        dailyBudget: Double,
        now: Date = Date()
    ) -> [Alert] {
        var raised: [Alert] = []
        var live: Set<String> = []

        for candidate in planLimitAlerts(usage: usage, now: now)
            + budgetAlerts(todaySpend: todaySpend, dailyBudget: dailyBudget, now: now)
            + contextAlerts(sessions: sessions) {
            live.insert(candidate.dedupeKey)
            // Re-notify only when the situation got worse, never on every poll.
            if let previous = reported[candidate.dedupeKey], previous == candidate.severity
                || (previous == .critical && candidate.severity == .warning) {
                continue
            }
            reported[candidate.dedupeKey] = candidate.severity
            raised.append(candidate)
        }

        // Conditions that are no longer present are cleared, so the next time they
        // appear the user hears about it again.
        for key in reported.keys where !live.contains(key) {
            reported.removeValue(forKey: key)
        }

        return raised
    }

    // MARK: - Conditions

    private func planLimitAlerts(usage: ClaudeUsageSnapshot?, now: Date) -> [Alert] {
        guard let usage else { return [] }
        // A cache Claude Code has not refreshed in a while describes the past, and
        // waking someone for a days-old reading is worse than silence.
        guard !usage.isStale(now: now) else { return [] }

        return usage.liveLimits(now: now).compactMap { limit in
            let fraction = Double(limit.percent) / 100.0
            guard fraction >= Self.limitWarning else { return nil }
            let severity: Alert.Severity = fraction >= Self.limitCritical ? .critical : .warning
            let reset = limit.timeUntilReset(now: now).map(Formatters.countdown) ?? "unknown reset"
            return Alert(
                kind: .planLimit,
                severity: severity,
                title: "\(limit.label) at \(limit.percent)%",
                body: severity == .critical
                    ? "This window is nearly gone — \(reset)."
                    : "Approaching the limit — \(reset).",
                dedupeKey: "limit:\(limit.kind)"
            )
        }
    }

    private func budgetAlerts(todaySpend: Double, dailyBudget: Double, now: Date) -> [Alert] {
        guard dailyBudget > 0, todaySpend > 0 else { return [] }
        let fraction = todaySpend / dailyBudget
        guard fraction >= Self.budgetWarning else { return [] }

        // Scoped to the day so tomorrow's first crossing is reported again.
        let day = ISO8601DateFormatter.dayOnly.string(from: now)
        let exceeded = fraction >= 1.0
        return [Alert(
            kind: .budget,
            severity: exceeded ? .critical : .warning,
            title: exceeded
                ? "Daily budget exceeded — \(Formatters.usd(todaySpend))"
                : "\(Int(fraction * 100))% of today's budget used",
            body: exceeded
                ? "\(Formatters.usd(todaySpend - dailyBudget)) over your \(Formatters.usd(dailyBudget)) limit."
                : "\(Formatters.usd(dailyBudget - todaySpend)) left of \(Formatters.usd(dailyBudget)).",
            dedupeKey: "budget:\(day)"
        )]
    }

    private func contextAlerts(sessions: [SessionAgg]) -> [Alert] {
        sessions.compactMap { session in
            // Only when the window size is measured or inferred — against a defaulted
            // guess this would fire for every long-context session.
            guard session.contextWindowSource != .fallback,
                  session.contextFraction >= Self.contextPressure else { return nil }
            return Alert(
                kind: .contextPressure,
                severity: .warning,
                title: "\(session.displayTitle) is \(Int(session.contextFraction * 100))% full",
                body: "\(Formatters.tokens(session.contextTokens)) of "
                    + "\(Formatters.tokens(session.contextTotalTokens)) used. "
                    + "Run /compact or split the work before Claude Code does it for you.",
                dedupeKey: "context:\(session.id)"
            )
        }
    }
}

private extension ISO8601DateFormatter {
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        return f
    }()
}
