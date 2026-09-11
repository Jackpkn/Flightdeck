import Testing
import Foundation
@testable import Flightdeck

@Suite("Alert engine")
struct AlertEngineTests {

    private func limit(_ kind: String, percent: Int, resetsIn: TimeInterval = 3600) -> ClaudeUsageLimit {
        ClaudeUsageLimit(
            kind: kind, group: kind, percent: percent, severity: .normal,
            resetsAt: Date().addingTimeInterval(resetsIn), isActive: true
        )
    }

    private func snapshot(_ limits: [ClaudeUsageLimit], fetchedAgo: TimeInterval = 0) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fetchedAt: Date().addingTimeInterval(-fetchedAgo),
            limits: limits,
            extraUsageEnabled: false
        )
    }

    private func session(id: String = "s", cost: Double = 0, contextTokens: Int = 0,
                         contextTotal: Int = 1_000_000,
                         source: ContextWindowSource = .inferred) -> SessionAgg {
        var agg = SessionAgg(id: id, project: "proj")
        agg.liveTotalCost = cost
        agg.contextTokens = contextTokens
        agg.contextTotalTokens = contextTotal
        agg.contextWindowSource = source
        agg.lastSeen = Date()
        return agg
    }

    // MARK: - Plan limits

    @Test("A limit crossing the warning threshold raises an alert")
    func limitWarning() throws {
        var engine = AlertEngine()
        let alerts = engine.evaluate(
            usage: snapshot([limit("session", percent: 82)]),
            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date()
        )
        let alert = try #require(alerts.first { $0.kind == .planLimit })
        #expect(alert.title.contains("82%"))
    }

    @Test("A limit below the threshold raises nothing")
    func limitQuiet() {
        var engine = AlertEngine()
        let alerts = engine.evaluate(
            usage: snapshot([limit("session", percent: 40)]),
            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date()
        )
        #expect(alerts.isEmpty)
    }

    @Test("The same limit does not alert twice at the same severity")
    func limitNotRepeated() {
        var engine = AlertEngine()
        let first = engine.evaluate(usage: snapshot([limit("session", percent: 82)]),
                                    sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        let second = engine.evaluate(usage: snapshot([limit("session", percent: 84)]),
                                     sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test("Escalating from warning to critical alerts again")
    func limitEscalates() {
        var engine = AlertEngine()
        _ = engine.evaluate(usage: snapshot([limit("session", percent: 82)]),
                            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        let escalated = engine.evaluate(usage: snapshot([limit("session", percent: 96)]),
                                        sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        #expect(escalated.count == 1)
        #expect(escalated.first?.isCritical == true)
    }

    @Test("A window that reset clears its alert so the next rise fires again")
    func limitResetsAfterWindowRolls() {
        var engine = AlertEngine()
        _ = engine.evaluate(usage: snapshot([limit("session", percent: 82)]),
                            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        // Fresh window: consumption dropped back down.
        _ = engine.evaluate(usage: snapshot([limit("session", percent: 3)]),
                            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        let again = engine.evaluate(usage: snapshot([limit("session", percent: 85)]),
                                    sessions: [], todaySpend: 0, dailyBudget: 20, now: Date())
        #expect(again.count == 1)
    }

    @Test("Stale cached limits are not alerted on")
    func staleLimitsIgnored() {
        var engine = AlertEngine()
        // Five days old — the state real caches sit in between sessions.
        let alerts = engine.evaluate(
            usage: snapshot([limit("session", percent: 95)], fetchedAgo: 5 * 86_400),
            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date()
        )
        #expect(!alerts.contains { $0.kind == .planLimit })
    }

    @Test("An expired window is not alerted on")
    func expiredWindowIgnored() {
        var engine = AlertEngine()
        let alerts = engine.evaluate(
            usage: snapshot([limit("session", percent: 95, resetsIn: -60)]),
            sessions: [], todaySpend: 0, dailyBudget: 20, now: Date()
        )
        #expect(!alerts.contains { $0.kind == .planLimit })
    }

    // MARK: - Budget

    @Test("Crossing the daily budget raises an alert")
    func budgetExceeded() throws {
        var engine = AlertEngine()
        let alerts = engine.evaluate(usage: nil, sessions: [], todaySpend: 21, dailyBudget: 20, now: Date())
        let alert = try #require(alerts.first { $0.kind == .budget })
        #expect(alert.isCritical)
    }

    @Test("Nearing the daily budget warns before it is breached")
    func budgetNearing() throws {
        var engine = AlertEngine()
        let alerts = engine.evaluate(usage: nil, sessions: [], todaySpend: 17, dailyBudget: 20, now: Date())
        let alert = try #require(alerts.first { $0.kind == .budget })
        #expect(!alert.isCritical)
    }

    @Test("A budget alert does not repeat on the same day at the same severity")
    func budgetNotRepeated() {
        var engine = AlertEngine()
        _ = engine.evaluate(usage: nil, sessions: [], todaySpend: 17, dailyBudget: 20, now: Date())
        let second = engine.evaluate(usage: nil, sessions: [], todaySpend: 18, dailyBudget: 20, now: Date())
        #expect(second.isEmpty)
    }

    @Test("A new day allows the budget alert to fire again")
    func budgetResetsNextDay() {
        var engine = AlertEngine()
        let today = Date()
        _ = engine.evaluate(usage: nil, sessions: [], todaySpend: 17, dailyBudget: 20, now: today)
        let tomorrow = today.addingTimeInterval(86_400)
        let next = engine.evaluate(usage: nil, sessions: [], todaySpend: 17, dailyBudget: 20, now: tomorrow)
        #expect(next.count == 1)
    }

    @Test("A zero or negative budget is not alerted against")
    func noBudgetNoAlert() {
        var engine = AlertEngine()
        #expect(engine.evaluate(usage: nil, sessions: [], todaySpend: 50, dailyBudget: 0, now: Date()).isEmpty)
    }

    // MARK: - Context pressure

    @Test("A session near its context ceiling raises an alert")
    func contextPressure() throws {
        var engine = AlertEngine()
        let alerts = engine.evaluate(
            usage: nil,
            sessions: [session(contextTokens: 920_000)],
            todaySpend: 0, dailyBudget: 20, now: Date()
        )
        let alert = try #require(alerts.first { $0.kind == .contextPressure })
        #expect(alert.body.contains("compact"))
    }

    @Test("A guessed context window never raises pressure alerts")
    func contextPressureNeedsRealWindow() {
        var engine = AlertEngine()
        let alerts = engine.evaluate(
            usage: nil,
            sessions: [session(contextTokens: 195_000, contextTotal: 200_000, source: .fallback)],
            todaySpend: 0, dailyBudget: 20, now: Date()
        )
        #expect(!alerts.contains { $0.kind == .contextPressure })
    }

    @Test("Context pressure alerts once per session until it drops back")
    func contextPressureNotRepeated() {
        var engine = AlertEngine()
        let hot = session(contextTokens: 920_000)
        let first = engine.evaluate(usage: nil, sessions: [hot], todaySpend: 0, dailyBudget: 20, now: Date())
        let second = engine.evaluate(usage: nil, sessions: [hot], todaySpend: 0, dailyBudget: 20, now: Date())
        #expect(first.count == 1)
        #expect(second.isEmpty)

        // After a compaction the context falls; rising again should alert again.
        _ = engine.evaluate(usage: nil, sessions: [session(contextTokens: 100_000)],
                            todaySpend: 0, dailyBudget: 20, now: Date())
        let again = engine.evaluate(usage: nil, sessions: [hot], todaySpend: 0, dailyBudget: 20, now: Date())
        #expect(again.count == 1)
    }

    @Test("Nothing to report produces no alerts at all")
    func silentByDefault() {
        var engine = AlertEngine()
        #expect(engine.evaluate(usage: nil, sessions: [], todaySpend: 0, dailyBudget: 20, now: Date()).isEmpty)
    }
}
