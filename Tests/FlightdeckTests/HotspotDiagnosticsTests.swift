import Foundation
import Testing
@testable import Flightdeck

@Suite("Hotspot Diagnostics & 85% Compaction Sentinel")
struct HotspotDiagnosticsTests {

    private func makeSession(
        id: String,
        project: String,
        files: [String],
        contextTokens: Int = 50_000,
        contextTotal: Int = 200_000,
        source: ContextWindowSource = .statusline,
        toolErrors: Int = 0
    ) -> SessionAgg {
        var agg = SessionAgg(id: id, project: project)
        for f in files { agg.noteFileModified(f) }
        agg.contextTokens = contextTokens
        agg.contextTotalTokens = contextTotal
        agg.contextWindowSource = source
        agg.toolUseCount = 20
        agg.toolErrorCount = toolErrors
        agg.liveTotalCost = 1.0
        return agg
    }

    @Test("Context pressure triggers at 85% threshold, not 90%")
    func contextPressureThreshold85() {
        #expect(WasteReport.contextPressureFraction == 0.85)

        // 170,000 / 200,000 = 85.0%
        let at85 = makeSession(id: "s1", project: "app", files: ["Main.swift"], contextTokens: 170_000, contextTotal: 200_000)
        let report85 = WasteReport(sessions: [at85])
        let finding = report85.findings.first { $0.kind == .contextPressure }
        #expect(finding != nil)
        #expect(finding?.detail.contains("85%") == true)
        #expect(finding?.kind.advice.contains("85%") == true)

        // 160,000 / 200,000 = 80.0% (below 85% threshold)
        let at80 = makeSession(id: "s2", project: "app", files: ["Main.swift"], contextTokens: 160_000, contextTotal: 200_000)
        let report80 = WasteReport(sessions: [at80])
        #expect(report80.findings.filter { $0.kind == .contextPressure }.isEmpty)
    }

    @Test("Diagnoses architectural coupling when file spans multiple projects")
    func diagnosesCouplingAcrossProjects() throws {
        let s1 = makeSession(id: "1", project: "Frontend", files: ["SharedConfig.swift"])
        let s2 = makeSession(id: "2", project: "Backend", files: ["SharedConfig.swift"])

        let spots = ChurnAnalyzer.hotspots(in: [s1, s2])
        let top = try #require(spots.first)
        #expect(top.path == "SharedConfig.swift")
        #expect(top.diagnosis == .architecturalCoupling)
        #expect(top.projects.count == 2)
    }

    @Test("Diagnoses task too large when rewritten under high context pressure")
    func diagnosesTaskTooLargeAt85PercentContext() throws {
        let s1 = makeSession(id: "1", project: "app", files: ["ComplexEngine.swift"], contextTokens: 175_000, contextTotal: 200_000)
        let s2 = makeSession(id: "2", project: "app", files: ["ComplexEngine.swift"], contextTokens: 180_000, contextTotal: 200_000)

        let spots = ChurnAnalyzer.hotspots(in: [s1, s2])
        let top = try #require(spots.first)
        #expect(top.path == "ComplexEngine.swift")
        #expect(top.diagnosis == .taskTooLarge)
        #expect(top.suggestedAction.contains("85%"))
    }

    @Test("Diagnoses missing instructions when file rewritten 3+ times without high context pressure")
    func diagnosesMissingInstructionsOnRepeatedChurn() throws {
        let s1 = makeSession(id: "1", project: "app", files: ["AuthFlow.swift"], contextTokens: 20_000)
        let s2 = makeSession(id: "2", project: "app", files: ["AuthFlow.swift"], contextTokens: 25_000)
        let s3 = makeSession(id: "3", project: "app", files: ["AuthFlow.swift"], contextTokens: 30_000)

        let spots = ChurnAnalyzer.hotspots(in: [s1, s2, s3])
        let top = try #require(spots.first)
        #expect(top.path == "AuthFlow.swift")
        #expect(top.sessionCount == 3)
        #expect(top.diagnosis == .missingInstructions)
        #expect(top.suggestedAction.contains("CLAUDE.md"))
    }

    @Test("Generates actionable CLAUDE.md snippets for all diagnosis variants")
    func generatesClaudeMdSnippets() {
        let missing = ChurnHotspot(
            path: "Sources/Auth/Login.swift",
            sessionCount: 4,
            projects: ["Flightdeck"],
            diagnosis: .missingInstructions
        )
        #expect(missing.claudeMdSnippet.contains("## File Rule: Login.swift"))
        #expect(missing.claudeMdSnippet.contains("MISSING INSTRUCTIONS"))
        #expect(missing.claudeMdSnippet.contains("Preserve existing public APIs"))

        let tooLarge = ChurnHotspot(
            path: "Sources/Core/Engine.swift",
            sessionCount: 3,
            projects: ["Flightdeck"],
            diagnosis: .taskTooLarge
        )
        #expect(tooLarge.claudeMdSnippet.contains("## Context & Task Boundary: Engine.swift"))
        #expect(tooLarge.claudeMdSnippet.contains("TASK TOO LARGE"))
        #expect(tooLarge.claudeMdSnippet.contains("85%"))

        let coupling = ChurnHotspot(
            path: "Sources/Shared/Config.swift",
            sessionCount: 2,
            projects: ["Client", "Server"],
            diagnosis: .architecturalCoupling
        )
        #expect(coupling.claudeMdSnippet.contains("## Architecture & Boundaries: Config.swift"))
        #expect(coupling.claudeMdSnippet.contains("ARCHITECTURAL COUPLING"))
        #expect(coupling.claudeMdSnippet.contains("Extract shared protocols"))

        let iteration = ChurnHotspot(
            path: "Sources/UI/Theme.swift",
            sessionCount: 2,
            projects: ["Flightdeck"],
            diagnosis: .activeIteration
        )
        #expect(iteration.claudeMdSnippet.contains("## Active Development: Theme.swift"))
        #expect(iteration.claudeMdSnippet.contains("Test Invariants"))
    }
}
