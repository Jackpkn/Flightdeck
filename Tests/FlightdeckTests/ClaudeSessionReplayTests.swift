import Testing
import Foundation
@testable import Flightdeck

@Suite("Claude Session Replay Tests")
struct ClaudeSessionReplayTests {

    @Test("Formats a conversation turn with tools and token metrics cleanly")
    func formatSingleTurn() {
        let tool = TranscriptToolCall(
            id: "tool-1",
            name: "edit",
            inputSummary: "AuthModal.tsx",
            result: "Replaced 5 lines",
            isError: false
        )

        let turn = ConversationTurn(
            id: "turn-uuid-1",
            turnIndex: 3,
            timestamp: Date(),
            userPrompt: "Fix the race condition in AuthModal",
            assistantText: "I have updated the state lock to prevent race conditions.",
            thinkingText: "Checking lock semantics...",
            toolCalls: [tool],
            model: "claude-3-7-sonnet",
            inputTokens: 1200,
            outputTokens: 350,
            cacheTokens: 4000,
            costUSD: 0.0145
        )

        let formatted = ClaudeSessionReplay.formatTurn(turn, verbose: false)
        #expect(formatted.contains("Turn #3"))
        #expect(formatted.contains("claude-3-7-sonnet"))
        #expect(formatted.contains("Fix the race condition in AuthModal"))
        #expect(formatted.contains("Tools Used (1)"))
        #expect(formatted.contains("edit"))
        #expect(formatted.contains("✓ [OK]"))
        #expect(formatted.contains("I have updated the state lock"))
    }

    @Test("Formats tool error tag when tool call failed")
    func formatToolErrorTurn() {
        let errTool = TranscriptToolCall(
            id: "tool-err",
            name: "bash",
            inputSummary: "npm test",
            result: "exit code 1: command not found",
            isError: true
        )

        let turn = ConversationTurn(
            id: "turn-err",
            turnIndex: 1,
            timestamp: Date(),
            userPrompt: "Run tests",
            assistantText: "The test run failed because npm was not found.",
            toolCalls: [errTool]
        )

        let formatted = ClaudeSessionReplay.formatTurn(turn, verbose: true)
        #expect(formatted.contains("❌ [ERR]"))
        #expect(formatted.contains("npm test"))
        #expect(formatted.contains("command not found"))
    }

    @Test("Converts turns to structured JSON without data loss")
    func turnsToJSONExport() {
        let turn = ConversationTurn(
            id: "turn-123",
            turnIndex: 1,
            timestamp: Date(),
            userPrompt: "Hello Claude",
            assistantText: "Hello! How can I assist you today?",
            model: "claude-3-5-sonnet",
            inputTokens: 100,
            outputTokens: 20,
            costUSD: 0.0006
        )

        var session = SessionAgg(id: "sess-abc", project: "Flightdeck")
        session.branch = "main"
        session.contextTokens = 5000
        session.liveTotalCost = 0.05

        let json = ClaudeSessionReplay.turnsToJSON(turns: [turn], session: session)
        #expect(json["sessionId"] as? String == "sess-abc")
        #expect(json["project"] as? String == "Flightdeck")
        #expect(json["turnsCount"] as? Int == 1)

        guard let turnsArray = json["turns"] as? [[String: Any]], turnsArray.count == 1 else {
            Issue.record("Expected 1 turn in JSON array")
            return
        }

        let first = turnsArray[0]
        #expect(first["prompt"] as? String == "Hello Claude")
        #expect(first["model"] as? String == "claude-3-5-sonnet")
        #expect(first["totalTokens"] as? Int == 120)
    }

    @Test("Session replay banner includes project, branch, and cost")
    func formatSessionReplayBanner() {
        var session = SessionAgg(id: "sess-xyz", project: "mirage")
        session.branch = "feat/nfs"
        session.liveTotalCost = 1.25

        let banner = ClaudeSessionReplay.formatSessionReplay(turns: [], session: session)
        #expect(banner.contains("CLAUDE CODE SESSION REPLAY: mirage (feat/nfs)"))
        #expect(banner.contains("sess-xyz"))
        #expect(banner.contains("$1.25"))
        #expect(banner.contains("No conversation turns recorded"))
    }
}
