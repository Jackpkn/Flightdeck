import Testing
import Foundation
import GRDB
@testable import Flightdeck

@Suite("ClaudeIntegrationTests")
struct ClaudeIntegrationTests {

    @Test("Statusline JSON payload decodes properly")
    func statuslineDecoding() throws {
        let json = """
        {
            "session_id": "test-session-123",
            "model": "claude-fable-5-1",
            "total_cost": 0.4285,
            "context_window": {
                "used": 45000,
                "total": 200000
            },
            "cwd": "/Users/test/Projects/Flightdeck",
            "git_branch": "feature/claude-hooks"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(StatuslinePayload.self, from: data)

        #expect(payload.session_id == "test-session-123")
        #expect(payload.model == "claude-fable-5-1")
        #expect(payload.total_cost == 0.4285)
        #expect(payload.context_window?.used == 45000)
        #expect(payload.context_window?.total == 200000)
        #expect(payload.cwd == "/Users/test/Projects/Flightdeck")
        #expect(payload.git_branch == "feature/claude-hooks")
    }


    @Test("SessionAgg merges live total cost and preserves max value")
    func sessionAggCostMerging() {
        var agg = SessionAgg(id: "sess-1", project: "Flightdeck")
        #expect(agg.totalCost == 0.0)

        // Add some ledger turns
        let now = Date()
        agg.costLedger = [
            (now.addingTimeInterval(-100), 0.05),
            (now.addingTimeInterval(-50), 0.10)
        ]
        #expect(abs(agg.totalCost - 0.15) < 0.0001)

        // Live statusline reports cumulative cost higher than ledger
        agg.liveTotalCost = 0.25
        #expect(agg.totalCost == 0.25)

        // If live cost is lower (e.g. older), ledger sum takes precedence
        agg.liveTotalCost = 0.10
        #expect(abs(agg.totalCost - 0.15) < 0.0001)
    }

    @Test("ActivityDatabase upserts and fetches live session records with dynamic context total")
    func databaseSessionLiveOperations() throws {
        guard let db = ActivityDatabase.shared else {
            return
        }

        let id = "test-live-" + UUID().uuidString
        let record = SessionLiveRecord(
            sessionId: id,
            project: "Flightdeck",
            branch: "main",
            model: "claude-fable-5-1[1m]",
            contextTokens: 12000,
            contextTotalTokens: 1_000_000,
            totalCostUsd: 0.88,
            lastFile: "Sources/Flightdeck/App.swift",
            updatedAt: Date()
        )

        db.upsertSession(record)

        let sessions = db.fetchLiveSessions()
        let match = sessions.first { $0.sessionId == id }
        #expect(match != nil)
        #expect(match?.model == "claude-fable-5-1[1m]")
        #expect(match?.contextTokens == 12000)
        #expect(match?.contextTotalTokens == 1_000_000)
        #expect(match?.totalCostUsd == 0.88)
    }

    @Test("ClaudeLogLine parses real cost-state records with totalCostUSD from JSON")
    func costStateDecoding() throws {
        let json = """
        {
            "type": "cost-state",
            "sessionId": "sess-cost-999",
            "totalCostUSD": 33.1432,
            "modelUsage": {
                "claude-fable-5-1[1m]": {
                    "inputTokens": 6770,
                    "outputTokens": 353652,
                    "costUSD": 33.139
                }
            }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(ClaudeLogLine.self, from: data)

        #expect(entry.type == "cost-state")
        #expect(entry.sessionId == "sess-cost-999")
        #expect(entry.totalCostUSD == 33.1432)
        #expect(entry.modelUsage?["claude-fable-5-1[1m]"]?.costUSD == 33.139)
    }

    @Test("ActivityDatabase inserts and fetches AI event records")
    func databaseAIEventOperations() throws {
        guard let db = ActivityDatabase.shared else {
            return
        }

        let sid = "test-event-" + UUID().uuidString
        let event = AIEventRecord(
            id: nil,
            sessionId: sid,
            event: "PostToolUse",
            toolName: "Edit",
            detail: "Sources/Flightdeck/CLI.swift",
            timestamp: Date()
        )

        db.insertEvent(event)

        let recents = db.recentEvents(limit: 50)
        let match = recents.first { $0.sessionId == sid }
        #expect(match != nil)
        #expect(match?.event == "PostToolUse")
        #expect(match?.toolName == "Edit")
        #expect(match?.detail == "Sources/Flightdeck/CLI.swift")
    }

    @Test("Message turn usage decodes thinking tokens and cache tokens properly from JSON")
    func messageTurnUsageDecoding() throws {
        let json = """
        {
            "type": "assistant",
            "sessionId": "sess-tokens-123",
            "message": {
                "model": "claude-sonnet-5",
                "usage": {
                    "input_tokens": 12,
                    "output_tokens": 850,
                    "cache_creation_input_tokens": 42000,
                    "cache_read_input_tokens": 18000,
                    "output_tokens_details": {
                        "thinking_tokens": 340
                    }
                }
            }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(ClaudeLogLine.self, from: data)

        #expect(entry.message?.model == "claude-sonnet-5")
        #expect(entry.message?.usage?.input_tokens == 12)
        #expect(entry.message?.usage?.output_tokens == 850)
        #expect(entry.message?.usage?.cache_creation_input_tokens == 42000)
        #expect(entry.message?.usage?.cache_read_input_tokens == 18000)
        #expect(entry.message?.usage?.output_tokens_details?.thinking_tokens == 340)
    }

    @Test("SessionAgg calculates total tokens and cache hit ratio accurately")
    func sessionAggTokenMetrics() {
        var agg = SessionAgg(id: "sess-calc-1", project: "Flightdeck")
        agg.inputTokens = 1000
        agg.outputTokens = 500
        agg.thinkingTokens = 200
        agg.cacheReadTokens = 9000
        agg.cacheCreationTokens = 4000

        #expect(agg.totalTokens == 14700)
        // Cache hit ratio = 9000 / (9000 + 1000) = 0.90 (90%)
        #expect(abs(agg.cacheHitRatio - 0.90) < 0.001)

        var modelSummary = ModelUsageSummary()
        modelSummary.inputTokens = 500
        modelSummary.outputTokens = 100
        modelSummary.thinkingTokens = 50
        modelSummary.costUSD = 0.12
        #expect(modelSummary.totalTokens == 650)
        agg.modelUsages["claude-sonnet-5"] = modelSummary

        #expect(agg.modelUsages["claude-sonnet-5"]?.costUSD == 0.12)
    }
}

