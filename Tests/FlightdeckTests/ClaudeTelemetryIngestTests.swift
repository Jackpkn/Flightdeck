import Testing
import Foundation
@testable import Flightdeck

@Suite("Claude telemetry ingest")
struct ClaudeTelemetryIngestTests {

    private func decode(_ json: String) throws -> ClaudeLogLine {
        try JSONDecoder().decode(ClaudeLogLine.self, from: Data(json.utf8))
    }

    /// `cost-state` carries per-session totals Flightdeck previously only read from
    /// ~/.claude.json, where they are scoped to a project's *last* session.
    @Test("cost-state totals decode from the session's own record")
    func costStateTotals() throws {
        let line = try decode("""
        {
          "type": "cost-state",
          "sessionId": "1e56dddf",
          "totalCostUSD": 33.14324060000002,
          "totalAPIDuration": 3877412,
          "totalToolDuration": 188506,
          "totalLinesAdded": 2687,
          "totalLinesRemoved": 257,
          "totalDuration": 453334803,
          "startTime": 1788500437097,
          "hasUnknownModelCost": false
        }
        """)
        #expect(line.totalCostUSD == 33.14324060000002)
        #expect(line.totalLinesAdded == 2687)
        #expect(line.totalLinesRemoved == 257)
        #expect(line.totalAPIDuration == 3877412)
        #expect(line.totalToolDuration == 188506)
        #expect(line.totalDuration == 453334803)
        #expect(line.startTime == 1788500437097)
        #expect(line.hasUnknownModelCost == false)
    }

    @Test("A session priced with an unknown model is marked as incomplete")
    func unknownModelCostFlag() throws {
        let line = try decode(#"{"type":"cost-state","sessionId":"s","hasUnknownModelCost":true}"#)
        #expect(line.hasUnknownModelCost == true)

        var agg = SessionAgg(id: "s", project: "p")
        #expect(agg.costIsComplete)
        agg.hasUnknownModelCost = true
        #expect(!agg.costIsComplete)
    }

    @Test("agent-name records decode the subagent that ran")
    func agentNameRecord() throws {
        let line = try decode("""
        {"type":"agent-name","agentName":"autonomous-replies-marketing-agentic","sessionId":"093de610"}
        """)
        #expect(line.agentName == "autonomous-replies-marketing-agentic")
    }

    @Test("file-history-delta records decode the file that was modified")
    func fileHistoryDelta() throws {
        let line = try decode("""
        {
          "type": "file-history-delta",
          "trackingPath": "skillpath-framer-assignment/CoursesSection.tsx",
          "sessionId": "s",
          "timestamp": "2026-08-13T06:43:15.470Z"
        }
        """)
        #expect(line.trackingPath == "skillpath-framer-assignment/CoursesSection.tsx")
    }

    @Test("Records without the new fields still decode")
    func backwardCompatible() throws {
        let line = try decode(#"{"type":"user","sessionId":"s"}"#)
        #expect(line.agentName == nil)
        #expect(line.trackingPath == nil)
        #expect(line.hasUnknownModelCost == nil)
        #expect(line.totalLinesAdded == nil)
    }

    // MARK: - SessionAgg derived telemetry

    @Test("Subagents are recorded once each, in a stable order")
    func subagentRoster() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteSubagent("code-reviewer")
        agg.noteSubagent("Explore")
        agg.noteSubagent("code-reviewer")
        #expect(agg.subagents == ["Explore", "code-reviewer"])
    }

    @Test("Blank subagent names are ignored")
    func ignoresBlankSubagents() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteSubagent("")
        agg.noteSubagent("   ")
        #expect(agg.subagents.isEmpty)
    }

    @Test("Files modified are deduplicated and counted")
    func filesModified() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteFileModified("a/b/Thing.swift")
        agg.noteFileModified("a/b/Thing.swift")
        agg.noteFileModified("a/c/Other.swift")
        #expect(agg.filesModifiedCount == 2)
        #expect(agg.filesModified.contains("a/c/Other.swift"))
    }

    @Test("Latency split reports API versus tool time from real durations")
    func latencySplit() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.apiDurationMs = 3_877_412
        agg.toolDurationMs = 188_506
        #expect(abs(agg.apiTimeRatio - 0.9536) < 0.001)
    }
}

@Suite("Claude skill usage")
struct ClaudeSkillUsageTests {

    private let payload = Data("""
    {
      "skillUsage": {
        "run": { "usageCount": 1, "lastUsedAt": 1783909805670 },
        "deep-research": { "usageCount": 3, "lastUsedAt": 1784295907630 },
        "artifact-design": { "usageCount": 2, "lastUsedAt": 1788883496714 }
      }
    }
    """.utf8)

    @Test("Parses skill usage counts and timestamps")
    func parsesSkills() throws {
        let skills = ClaudeSkillUsageReader.parse(payload)
        #expect(skills.count == 3)
        let research = try #require(skills.first { $0.name == "deep-research" })
        #expect(research.usageCount == 3)
        #expect(research.lastUsedAt != nil)
    }

    @Test("Skills are ranked by how often they are used")
    func rankedByUsage() {
        let skills = ClaudeSkillUsageReader.parse(payload)
        #expect(skills.first?.name == "deep-research")
        #expect(skills.map(\.usageCount) == [3, 2, 1])
    }

    @Test("Missing skill data yields an empty list, not a crash")
    func missingData() {
        #expect(ClaudeSkillUsageReader.parse(Data("{}".utf8)).isEmpty)
        #expect(ClaudeSkillUsageReader.parse(Data("bad".utf8)).isEmpty)
    }

    @Test("Entries with no usage count are skipped")
    func skipsEmptyEntries() {
        let data = Data(#"{"skillUsage":{"ghost":{},"real":{"usageCount":2}}}"#.utf8)
        let skills = ClaudeSkillUsageReader.parse(data)
        #expect(skills.map(\.name) == ["real"])
    }
}

@Suite("Records without a session id")
struct SessionlessRecordTests {

    /// Verified against real transcripts: 0 of 179 `file-history-delta` records on
    /// this machine carry a `sessionId`. The transcript filename is the session id,
    /// so requiring the field discarded every file-change record.
    @Test("file-history-delta really has no sessionId field")
    func deltaHasNoSessionId() throws {
        let line = try JSONDecoder().decode(ClaudeLogLine.self, from: Data("""
        {
          "type": "file-history-delta",
          "messageId": "e465eeb6",
          "snapshotMessageId": "ab2663cb",
          "trackingPath": "packages/core/src/store.ts",
          "backup": { "realParentDir": "/Users/x/vendo/packages/core/src" },
          "timestamp": "2026-08-13T06:43:15.470Z"
        }
        """.utf8))
        #expect(line.sessionId == nil)
        #expect(line.trackingPath == "packages/core/src/store.ts")
        #expect(line.backup?.realParentDir == "/Users/x/vendo/packages/core/src")
    }

    @Test("A tracked path resolves against its real parent directory")
    func resolvesAbsolutePath() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteFileModified(
            trackingPath: "packages/core/src/store.ts",
            realParentDir: "/Users/x/vendo/packages/core/src"
        )
        #expect(agg.filesModified == ["/Users/x/vendo/packages/core/src/store.ts"])
    }

    @Test("A tracked path with no parent directory falls back to the raw path")
    func fallsBackToRawPath() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteFileModified(trackingPath: "a/b/File.swift", realParentDir: nil)
        #expect(agg.filesModified == ["a/b/File.swift"])
    }

    @Test("A flat tracked path still resolves")
    func flatPath() {
        var agg = SessionAgg(id: "s", project: "p")
        agg.noteFileModified(trackingPath: "README.md", realParentDir: "/Users/x/proj")
        #expect(agg.filesModified == ["/Users/x/proj/README.md"])
    }
}
