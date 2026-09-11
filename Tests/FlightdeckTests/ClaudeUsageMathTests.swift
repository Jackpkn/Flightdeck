import Testing
import Foundation
@testable import Flightdeck

/// `cost-state` records carry a session's *cumulative* cost, so the ledger must
/// treat them as snapshots — summing them is the double-count bug these cover.
@Suite("Cost snapshot ledger")
struct CostSnapshotLedgerTests {

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_788_500_000).addingTimeInterval(offset)
    }

    @Test("Repeated cumulative snapshots do not inflate the total")
    func repeatedSnapshotsDoNotSum() {
        var ledger = CostSnapshotLedger()
        // The real shape seen on disk: the same cumulative total written twice.
        ledger.record(33.14324060000002, at: date(0))
        ledger.record(33.14324060000002, at: date(100))
        #expect(abs(ledger.total - 33.14324060000002) < 0.0000001)
    }

    @Test("Total tracks the newest cumulative snapshot as a session grows")
    func totalTracksGrowth() {
        var ledger = CostSnapshotLedger()
        ledger.record(10, at: date(0))
        ledger.record(25, at: date(60))
        ledger.record(72.96, at: date(120))
        #expect(ledger.total == 72.96)
    }

    @Test("Out-of-order snapshots still report the highest cumulative value")
    func outOfOrderSnapshots() {
        var ledger = CostSnapshotLedger()
        ledger.record(72.96, at: date(120))
        ledger.record(10, at: date(0))
        #expect(ledger.total == 72.96)
    }

    @Test("Empty ledger has no cost and no data")
    func emptyLedger() {
        let ledger = CostSnapshotLedger()
        #expect(ledger.total == 0)
        #expect(ledger.isEmpty)
        let window = ledger.spend(since: date(0), sessionStart: nil)
        #expect(window.amount == 0)
        #expect(window.isExact)
    }

    @Test("Windowed spend is the delta against the last snapshot before the window")
    func windowedSpendUsesDelta() {
        var ledger = CostSnapshotLedger()
        ledger.record(10, at: date(-3600))   // yesterday
        ledger.record(25, at: date(60))      // today
        ledger.record(40, at: date(120))     // today
        let window = ledger.spend(since: date(0), sessionStart: date(-7200))
        #expect(window.amount == 30)         // 40 - 10, not 75
        #expect(window.isExact)
    }

    @Test("A session that started inside the window contributes its whole cost exactly")
    func sessionStartedInsideWindow() {
        var ledger = CostSnapshotLedger()
        ledger.record(12.5, at: date(300))
        let window = ledger.spend(since: date(0), sessionStart: date(60))
        #expect(window.amount == 12.5)
        #expect(window.isExact)
    }

    @Test("No baseline and a start before the window is reported as inexact")
    func unattributableSpendIsFlagged() {
        var ledger = CostSnapshotLedger()
        ledger.record(50, at: date(300))
        let window = ledger.spend(since: date(0), sessionStart: date(-86_400))
        #expect(window.amount == 50)
        #expect(!window.isExact)   // upper bound: may include yesterday's spend
    }

    @Test("Unknown session start with no baseline is inexact")
    func unknownStartIsInexact() {
        var ledger = CostSnapshotLedger()
        ledger.record(50, at: date(300))
        let window = ledger.spend(since: date(0), sessionStart: nil)
        #expect(!window.isExact)
    }

    @Test("Pruning keeps one baseline snapshot older than the retention cutoff")
    func pruningKeepsBaseline() {
        var ledger = CostSnapshotLedger()
        ledger.record(5, at: date(-30 * 86_400))
        ledger.record(8, at: date(-20 * 86_400))
        ledger.record(60, at: date(0))
        ledger.prune(before: date(-7 * 86_400))
        // The pre-cutoff baseline must survive or day-deltas silently over-report.
        let window = ledger.spend(since: date(-1 * 86_400), sessionStart: date(-30 * 86_400))
        #expect(window.amount == 52)   // 60 - 8
        #expect(window.isExact)
    }
}

@Suite("Context window resolution")
struct ContextWindowResolverTests {

    @Test("Statusline total is authoritative when present")
    func statuslineWins() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "claude-opus-5", contextTokens: 150_000)
        resolver.recordAuthoritative(model: "claude-opus-5", total: 1_000_000)
        let r = resolver.resolve(model: "claude-opus-5")
        #expect(r.total == 1_000_000)
        #expect(r.source == .statusline)
    }

    @Test("An observed context above 200K infers the 1M window")
    func infersMillionWindow() {
        var resolver = ContextWindowResolver()
        // Real high-water mark measured from this machine's transcripts.
        resolver.observe(model: "claude-opus-5", contextTokens: 998_404)
        let r = resolver.resolve(model: "claude-opus-5")
        #expect(r.total == 1_000_000)
        #expect(r.source == .inferred)
    }

    @Test("Windows snap up to the next known tier, never below what was observed")
    func snapsUpToTier() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "claude-sonnet-5", contextTokens: 489_613)
        let r = resolver.resolve(model: "claude-sonnet-5")
        #expect(r.total == 500_000)
        #expect(r.total >= 489_613)
    }

    @Test("A small observed context keeps the 200K default")
    func smallStaysDefault() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "claude-haiku-4-5-20251001", contextTokens: 65_336)
        let r = resolver.resolve(model: "claude-haiku-4-5-20251001")
        #expect(r.total == 200_000)
    }

    @Test("An unseen model falls back to the default and says so")
    func unknownModelFallsBack() {
        let resolver = ContextWindowResolver()
        let r = resolver.resolve(model: "some-future-model")
        #expect(r.total == 200_000)
        #expect(r.source == .fallback)
    }

    @Test("A context beyond every known tier rounds up instead of clamping")
    func beyondKnownTiers() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "big", contextTokens: 1_400_000)
        let r = resolver.resolve(model: "big")
        #expect(r.total >= 1_400_000)
    }

    @Test("The high-water mark only ever grows")
    func highWaterMarkOnlyGrows() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "claude-opus-5", contextTokens: 998_404)
        resolver.observe(model: "claude-opus-5", contextTokens: 1_200)
        #expect(resolver.resolve(model: "claude-opus-5").total == 1_000_000)
    }

    @Test("Empty model names are ignored rather than creating a bogus entry")
    func ignoresEmptyModel() {
        var resolver = ContextWindowResolver()
        resolver.observe(model: "", contextTokens: 900_000)
        #expect(resolver.resolve(model: "").source == .fallback)
    }
}

@Suite("Dominant model selection")
struct DominantModelTests {

    @Test("Picks the model that actually did the work, not dictionary order")
    func picksBiggestContributor() {
        let usages: [String: ModelUsageSummary] = [
            "claude-haiku-4-5-20251001": ModelUsageSummary(inputTokens: 4022, outputTokens: 13),
            "claude-sonnet-5": ModelUsageSummary(inputTokens: 6770, outputTokens: 353_652),
        ]
        #expect(ClaudeModelPicker.dominant(in: usages) == "claude-sonnet-5")
    }

    @Test("Synthetic placeholder models are never shown to the user")
    func skipsSynthetic() {
        let usages: [String: ModelUsageSummary] = [
            "<synthetic>": ModelUsageSummary(inputTokens: 999_999, outputTokens: 999_999),
            "claude-opus-5": ModelUsageSummary(inputTokens: 10, outputTokens: 10),
        ]
        #expect(ClaudeModelPicker.dominant(in: usages) == "claude-opus-5")
    }

    @Test("Selection is stable across repeated calls on equal weights")
    func deterministicOnTies() {
        let usages: [String: ModelUsageSummary] = [
            "model-b": ModelUsageSummary(inputTokens: 100, outputTokens: 100),
            "model-a": ModelUsageSummary(inputTokens: 100, outputTokens: 100),
        ]
        let picks = (0..<25).map { _ in ClaudeModelPicker.dominant(in: usages) }
        #expect(Set(picks).count == 1)
        #expect(picks.first == "model-a")
    }

    @Test("Returns nil when there is nothing real to show")
    func nilWhenEmpty() {
        #expect(ClaudeModelPicker.dominant(in: [:]) == nil)
        #expect(ClaudeModelPicker.dominant(in: ["<synthetic>": ModelUsageSummary()]) == nil)
    }
}

@Suite("Session spend reconciliation")
struct SessionSpendReconciliationTests {

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_788_500_000).addingTimeInterval(offset)
    }

    /// The statusline pushes a running total every couple of seconds, while
    /// `cost-state` checkpoints land rarely. Reading only the checkpoint ledger
    /// reports a stale figure — and marks it exact.
    @Test("Windowed spend includes live cost that arrived after the last checkpoint")
    func includesLiveCostBeyondLastCheckpoint() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.sessionStart = date(0)
        agg.lastSeen = date(900)
        agg.costLedger.record(2.00, at: date(60))
        agg.liveTotalCost = 15.00

        let window = agg.spend(since: date(-1))
        #expect(abs(window.amount - 15.00) < 0.0001)
        #expect(window.isExact)
        #expect(abs(agg.totalCost - 15.00) < 0.0001)
    }

    @Test("A mid-window session nets out spend from before the window")
    func netsOutEarlierSpend() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.sessionStart = date(-86_400)
        agg.costLedger.record(10.00, at: date(-3_600))  // yesterday
        agg.costLedger.record(25.00, at: date(60))      // today
        agg.liveTotalCost = 40.00                        // still running

        let window = agg.spend(since: date(0))
        #expect(abs(window.amount - 30.00) < 0.0001)     // 40 - 10
        #expect(window.isExact)
    }

    @Test("Per-model cost sums also count toward the window")
    func modelSumCounts() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.sessionStart = date(0)
        agg.costLedger.record(1.00, at: date(30))
        agg.modelUsages["claude-opus-5"] = ModelUsageSummary(costUSD: 9.00)

        let window = agg.spend(since: date(-1))
        #expect(abs(window.amount - 9.00) < 0.0001)
    }
}
