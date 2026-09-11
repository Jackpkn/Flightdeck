import Testing
import Foundation
@testable import Flightdeck

@Suite("Waste report")
struct WasteReportTests {

    private func session(
        id: String = "s",
        project: String = "p",
        cost: Double = 0,
        files: [String] = [],
        linesAdded: Int = 0,
        linesRemoved: Int = 0,
        tools: Int = 0,
        toolErrors: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        contextTokens: Int = 0,
        contextTotal: Int = 200_000,
        contextSource: ContextWindowSource = .inferred
    ) -> SessionAgg {
        var agg = SessionAgg(id: id, project: project)
        agg.liveTotalCost = cost
        for f in files { agg.noteFileModified(f) }
        agg.linesAdded = linesAdded
        agg.linesRemoved = linesRemoved
        agg.toolUseCount = tools
        agg.toolErrorCount = toolErrors
        agg.cacheReadTokens = cacheRead
        agg.cacheCreationTokens = cacheWrite
        agg.contextTokens = contextTokens
        agg.contextTotalTokens = contextTotal
        agg.contextWindowSource = contextSource
        return agg
    }

    // MARK: - Spend with no code change

    @Test("A session that cost money and changed no code is reported")
    func flagsSpendWithNoCodeChange() {
        let report = WasteReport(sessions: [session(cost: 12.40, tools: 30)])
        let finding = report.findings.first { $0.kind == .noCodeChange }
        #expect(finding != nil)
        #expect(finding?.attributableCost == 12.40)
    }

    @Test("A session that produced files is not flagged")
    func ignoresProductiveSession() {
        let report = WasteReport(sessions: [session(cost: 12.40, files: ["a.swift"], linesAdded: 50)])
        #expect(!report.findings.contains { $0.kind == .noCodeChange })
    }

    @Test("A session with line changes but no tracked files is still productive")
    func linesCountAsOutput() {
        let report = WasteReport(sessions: [session(cost: 5, linesAdded: 120)])
        #expect(!report.findings.contains { $0.kind == .noCodeChange })
    }

    @Test("A free session with no code change is not worth reporting")
    func ignoresZeroCostSession() {
        let report = WasteReport(sessions: [session(cost: 0, tools: 5)])
        #expect(report.findings.isEmpty)
    }

    @Test("Only spend above the noise floor is reported")
    func ignoresTrivialSpend() {
        let report = WasteReport(sessions: [session(cost: 0.004, tools: 2)])
        #expect(!report.findings.contains { $0.kind == .noCodeChange })
    }

    // MARK: - Tool failures

    @Test("Sessions with failing tool calls are reported with the real counts")
    func flagsToolFailures() throws {
        let report = WasteReport(sessions: [session(cost: 8, files: ["a"], tools: 100, toolErrors: 22)])
        let finding = try #require(report.findings.first { $0.kind == .toolFailures })
        #expect(finding.detail.contains("22"))
        // Failures cost money but the amount isn't separable, so none is claimed.
        #expect(finding.attributableCost == nil)
    }

    @Test("A low failure rate is normal and not reported")
    func ignoresLowFailureRate() {
        let report = WasteReport(sessions: [session(cost: 8, files: ["a"], tools: 100, toolErrors: 2)])
        #expect(!report.findings.contains { $0.kind == .toolFailures })
    }

    @Test("Failure rate needs enough tool calls to mean anything")
    func ignoresSmallSamples() {
        let report = WasteReport(sessions: [session(cost: 8, files: ["a"], tools: 3, toolErrors: 2)])
        #expect(!report.findings.contains { $0.kind == .toolFailures })
    }

    // MARK: - Cache churn

    @Test("A session that keeps rebuilding its context is reported")
    func flagsCacheChurn() throws {
        // Writing 3M of cache against only 5M of reads means the context kept resetting.
        let report = WasteReport(sessions: [
            session(cost: 20, files: ["a"], cacheRead: 5_000_000, cacheWrite: 3_000_000)
        ])
        let finding = try #require(report.findings.first { $0.kind == .cacheChurn })
        #expect(finding.detail.contains("%"))
    }

    @Test("A healthy cache hit rate is not reported")
    func ignoresHealthyCache() {
        let report = WasteReport(sessions: [
            session(cost: 20, files: ["a"], cacheRead: 85_000_000, cacheWrite: 3_000_000)
        ])
        #expect(!report.findings.contains { $0.kind == .cacheChurn })
    }

    @Test("Sessions with no cache activity are not reported")
    func ignoresNoCacheActivity() {
        let report = WasteReport(sessions: [session(cost: 1, files: ["a"])])
        #expect(!report.findings.contains { $0.kind == .cacheChurn })
    }

    // MARK: - Context pressure

    @Test("Work done near the context ceiling is reported")
    func flagsContextPressure() {
        let report = WasteReport(sessions: [
            session(cost: 20, files: ["a"], contextTokens: 950_000, contextTotal: 1_000_000)
        ])
        #expect(report.findings.contains { $0.kind == .contextPressure })
    }

    @Test("Context pressure is not claimed when the window size was only a guess")
    func skipsContextPressureOnFallbackWindow() {
        let report = WasteReport(sessions: [
            session(cost: 20, files: ["a"], contextTokens: 190_000,
                    contextTotal: 200_000, contextSource: .fallback)
        ])
        #expect(!report.findings.contains { $0.kind == .contextPressure })
    }

    // MARK: - Aggregate

    @Test("Total attributable cost only counts findings with a real dollar figure")
    func totalsOnlyRealDollars() {
        let report = WasteReport(sessions: [
            session(id: "a", cost: 10, tools: 20),                                   // no code change: $10
            session(id: "b", cost: 30, files: ["x"], tools: 100, toolErrors: 40),    // failures: no $ claimed
        ])
        #expect(report.totalAttributableCost == 10)
    }

    @Test("Findings are ordered with the most expensive first")
    func ordersByCost() {
        let report = WasteReport(sessions: [
            session(id: "cheap", cost: 2, tools: 10),
            session(id: "pricey", cost: 50, tools: 10),
        ])
        #expect(report.findings.first?.sessionId == "pricey")
    }

    @Test("A clean set of sessions produces no findings")
    func cleanSlate() {
        let report = WasteReport(sessions: [
            session(cost: 20, files: ["a"], linesAdded: 400, tools: 100, toolErrors: 1,
                    cacheRead: 85_000_000, cacheWrite: 3_000_000, contextTokens: 100_000)
        ])
        #expect(report.findings.isEmpty)
        #expect(report.totalAttributableCost == 0)
    }
}

@Suite("Churn hotspots")
struct ChurnHotspotTests {

    private func session(_ id: String, _ project: String, _ files: [String]) -> SessionAgg {
        var agg = SessionAgg(id: id, project: project)
        for f in files { agg.noteFileModified(f) }
        return agg
    }

    @Test("Files touched across several sessions rank highest")
    func ranksRepeatedFiles() throws {
        let hotspots = ChurnAnalyzer.hotspots(in: [
            session("1", "app", ["Auth.swift", "View.swift"]),
            session("2", "app", ["Auth.swift"]),
            session("3", "app", ["Auth.swift", "Other.swift"]),
        ])
        let top = try #require(hotspots.first)
        #expect(top.path == "Auth.swift")
        #expect(top.sessionCount == 3)
    }

    @Test("A file touched in only one session is not a hotspot")
    func ignoresSingleTouch() {
        let hotspots = ChurnAnalyzer.hotspots(in: [session("1", "app", ["Once.swift"])])
        #expect(hotspots.isEmpty)
    }

    @Test("A hotspot records which projects it spans")
    func recordsProjects() throws {
        let hotspots = ChurnAnalyzer.hotspots(in: [
            session("1", "app", ["Shared.swift"]),
            session("2", "lib", ["Shared.swift"]),
        ])
        let top = try #require(hotspots.first)
        #expect(top.projects == ["app", "lib"])
    }

    @Test("Ordering is stable when counts tie")
    func stableOrdering() {
        let sessions = [
            session("1", "app", ["B.swift", "A.swift"]),
            session("2", "app", ["B.swift", "A.swift"]),
        ]
        let runs = (0..<20).map { _ in ChurnAnalyzer.hotspots(in: sessions).map(\.path) }
        #expect(Set(runs.map { $0.joined() }).count == 1)
        #expect(runs.first?.first == "A.swift")
    }

    @Test("No sessions means no hotspots")
    func emptyInput() {
        #expect(ChurnAnalyzer.hotspots(in: []).isEmpty)
    }
}
