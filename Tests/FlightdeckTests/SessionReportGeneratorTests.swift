import Foundation
import Testing
@testable import Flightdeck

@Suite("Session Report Generator")
struct SessionReportGeneratorTests {

    private func sampleSession() -> SessionAgg {
        var s = SessionAgg(id: "sess-abc-123", project: "Flightdeck")
        s.branch = "feat/telemetry"
        s.model = "claude-3-7-sonnet"
        s.liveTotalCost = 3.42
        s.inputTokens = 120_000
        s.outputTokens = 15_000
        s.thinkingTokens = 4_000
        s.cacheReadTokens = 85_000
        s.cacheCreationTokens = 25_000
        s.linesAdded = 150
        s.linesRemoved = 30
        s.toolUseCount = 28
        s.toolErrorCount = 2
        s.noteFileModified("Sources/Flightdeck/CLI.swift")
        s.noteFileModified("README.md")
        return s
    }

    private func sampleOutcome() -> GitOutcome {
        GitOutcome(
            filesConsidered: 2,
            filesInHead: 2,
            filesUncommitted: 0,
            filesDropped: 0,
            commits: 3,
            linesAdded: 180,
            linesRemoved: 10
        )
    }

    @Test("Generates complete Markdown post-mortem document")
    func generatesMarkdownReport() {
        let session = sampleSession()
        let outcome = sampleOutcome()
        let spot = ChurnHotspot(
            path: "Sources/Flightdeck/CLI.swift",
            sessionCount: 3,
            projects: ["Flightdeck"],
            diagnosis: .missingInstructions,
            suggestedAction: "Update CLAUDE.md"
        )

        let md = SessionReportGenerator.generateMarkdown(
            session: session,
            outcome: outcome,
            hotspots: [spot],
            waste: nil
        )

        #expect(md.contains("Claude Code Session Post-Mortem Report"))
        #expect(md.contains("sess-abc-123"))
        #expect(md.contains("Flightdeck"))
        #expect(md.contains("Survival Rate in HEAD:"))
        #expect(md.contains("100%"))
        #expect(md.contains("Token Breakdown"))
        #expect(md.contains("MISSING INSTRUCTIONS"))
        #expect(md.contains("Update CLAUDE.md"))
    }

    @Test("Low survival rate emits warning alert block")
    func lowSurvivalRateWarning() {
        let session = sampleSession()
        let lowOutcome = GitOutcome(
            filesConsidered: 4,
            filesInHead: 1,
            filesUncommitted: 0,
            filesDropped: 3,
            commits: 1,
            linesAdded: 50,
            linesRemoved: 40
        )

        let md = SessionReportGenerator.generateMarkdown(
            session: session,
            outcome: lowOutcome,
            hotspots: [],
            waste: nil
        )

        #expect(md.contains("25%"))
        #expect(md.contains("Low Survival Warning"))
    }

    @Test("Generates structured JSON post-mortem dictionary")
    func generatesJSONReport() {
        let session = sampleSession()
        let outcome = sampleOutcome()

        let json = SessionReportGenerator.generateJSON(
            session: session,
            outcome: outcome,
            hotspots: []
        )

        #expect(json["sessionId"] as? String == "sess-abc-123")
        #expect(json["project"] as? String == "Flightdeck")
        #expect(json["totalCostUsd"] as? Double == 3.42)

        let git = json["gitOutcome"] as? [String: Any]
        #expect(git?["survivalRate"] as? Double == 1.0)
        #expect(git?["filesInHead"] as? Int == 2)

        let tokens = json["tokens"] as? [String: Any]
        #expect(tokens?["input"] as? Int == 120_000)
    }
}
