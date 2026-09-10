import Testing
import Foundation
@testable import Flightdeck

@Suite("ClaudeTranscriptTests")
struct ClaudeTranscriptTests {

    @Test("ClaudeTranscriptReader correctly parses user prompts, thinking blocks, and assistant text")
    func parseUserAndAssistantTurns() throws {
        let sampleJSONL = """
        {"type":"user","message":{"role":"user","content":"Can you list the active ports?"},"uuid":"turn-1","timestamp":"2026-09-10T12:00:00Z"}
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","role":"assistant","content":[{"type":"thinking","thinking":"Checking ports using lsof..."},{"type":"text","text":"I will check the open ports now."}],"usage":{"input_tokens":150,"output_tokens":45,"cache_read_input_tokens":100,"cache_creation_input_tokens":0}},"uuid":"turn-1-asst","timestamp":"2026-09-10T12:00:02Z"}
        {"type":"cost-state","costUSD":0.0025}
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-transcript-\(UUID().uuidString).jsonl")
        try sampleJSONL.data(using: .utf8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let turns = ClaudeTranscriptReader.parseTurns(from: tempURL)
        #expect(turns.count == 1)

        let turn = turns[0]
        #expect(turn.userPrompt == "Can you list the active ports?")
        #expect(turn.assistantText == "I will check the open ports now.")
        #expect(turn.thinkingText == "Checking ports using lsof...")
        #expect(turn.model == "claude-3-7-sonnet")
        #expect(turn.inputTokens == 150)
        #expect(turn.outputTokens == 45)
        #expect(turn.cacheTokens == 100)
        #expect(turn.totalTokens == 295)
        #expect(turn.costUSD == 0.0025)
    }

    @Test("ClaudeTranscriptReader correctly parses tool calls and matches tool results")
    func parseToolUseAndResult() throws {
        let sampleJSONL = """
        {"type":"user","message":{"role":"user","content":"Run a git status check"},"uuid":"turn-2","timestamp":"2026-09-10T12:05:00Z"}
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","role":"assistant","content":[{"type":"tool_use","id":"call-bash-123","name":"Bash","input":{"command":"git status -s"}}]},"uuid":"turn-2-asst","timestamp":"2026-09-10T12:05:01Z"}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"call-bash-123","content":" M Sources/Flightdeck/App.swift","is_error":false}]},"uuid":"turn-2-res","timestamp":"2026-09-10T12:05:02Z"}
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","role":"assistant","content":[{"type":"text","text":"App.swift is modified."}]},"uuid":"turn-2-final","timestamp":"2026-09-10T12:05:03Z"}
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-transcript-\(UUID().uuidString).jsonl")
        try sampleJSONL.data(using: .utf8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let turns = ClaudeTranscriptReader.parseTurns(from: tempURL)
        #expect(turns.count == 1)

        let turn = turns[0]
        #expect(turn.userPrompt == "Run a git status check")
        #expect(turn.assistantText == "App.swift is modified.")
        #expect(turn.toolCalls.count == 1)

        let tool = turn.toolCalls[0]
        #expect(tool.name == "Bash")
        #expect(tool.inputSummary == "git status -s")
        #expect(tool.isBash == true)
        #expect(tool.result?.contains("App.swift") == true)
        #expect(tool.isError == false)
    }

    @Test("ClaudeTranscriptReader parses multiple conversation turns sequentially")
    func parseMultipleTurns() throws {
        let sampleJSONL = """
        {"type":"user","message":{"role":"user","content":"Hello"},"uuid":"turn-a","timestamp":"2026-09-10T12:10:00Z"}
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","role":"assistant","content":[{"type":"text","text":"Hi! How can I help?"}]},"uuid":"turn-a-asst","timestamp":"2026-09-10T12:10:01Z"}
        {"type":"user","message":{"role":"user","content":"What is Flightdeck?"},"uuid":"turn-b","timestamp":"2026-09-10T12:10:05Z"}
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","role":"assistant","content":[{"type":"text","text":"Flightdeck is a macOS dev telemetry cockpit."}]},"uuid":"turn-b-asst","timestamp":"2026-09-10T12:10:06Z"}
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-transcript-\(UUID().uuidString).jsonl")
        try sampleJSONL.data(using: .utf8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let turns = ClaudeTranscriptReader.parseTurns(from: tempURL)
        #expect(turns.count == 2)
        #expect(turns[0].turnIndex == 1)
        #expect(turns[0].userPrompt == "Hello")
        #expect(turns[0].assistantText == "Hi! How can I help?")

        #expect(turns[1].turnIndex == 2)
        #expect(turns[1].userPrompt == "What is Flightdeck?")
        #expect(turns[1].assistantText == "Flightdeck is a macOS dev telemetry cockpit.")
    }
}
