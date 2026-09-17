import Foundation

/// Formatter and streaming visualizer for Claude Code turns, tools, and token metrics.
enum ClaudeSessionReplay {

    /// Formats a single conversation turn into a readable terminal block.
    static func formatTurn(_ turn: ConversationTurn, verbose: Bool = false) -> String {
        var out = ""
        let timeStr = DateFormatter.localizedString(from: turn.timestamp, dateStyle: .none, timeStyle: .medium)
        let costStr = turn.costUSD != nil ? Formatters.usd(turn.costUSD!) : "-"
        let tokStr = "\(Formatters.tokens(turn.totalTokens)) tok"
        let modelStr = turn.model.isEmpty ? "claude" : turn.model

        out += "╭── Turn #\(turn.turnIndex) ── [\(timeStr)] ── \(modelStr) ── \(tokStr) (\(costStr))\n"

        // User Prompt
        if !turn.userPrompt.isEmpty {
            let promptText = verbose ? turn.userPrompt : truncate(turn.userPrompt, maxLength: 200)
            out += "│ 👤 User:\n"
            for line in promptText.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "│   \(line)\n"
            }
        }

        // Tool Invocations
        if !turn.toolCalls.isEmpty {
            out += "│\n│ 🛠 Tools Used (\(turn.toolCalls.count)):\n"
            for (idx, tool) in turn.toolCalls.enumerated() {
                let badge = tool.isError ? "❌ [ERR]" : "✓ [OK]"
                let nameStr = tool.name.padding(toLength: 16, withPad: " ", startingAt: 0)
                let summary = verbose ? tool.inputSummary : truncate(tool.inputSummary, maxLength: 90)
                out += "│   \(idx + 1). \(badge) \(nameStr) \(summary)\n"

                if verbose, let res = tool.result, !res.isEmpty {
                    let preview = truncate(res, maxLength: 160)
                    out += "│      └─ Result: \(preview.replacingOccurrences(of: "\n", with: " "))\n"
                }
            }
        }

        // Assistant Text
        if !turn.assistantText.isEmpty {
            out += "│\n│ 🤖 Claude:\n"
            let text = verbose ? turn.assistantText : truncate(turn.assistantText, maxLength: 300)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "│   \(line)\n"
            }
        }

        out += "╰" + String(repeating: "─", count: 70) + "\n"
        return out
    }

    /// Formats the complete replay of a session's conversation turns.
    static func formatSessionReplay(
        turns: [ConversationTurn],
        session: SessionAgg?,
        verbose: Bool = false
    ) -> String {
        var out = ""
        let totalCost = session?.totalCost ?? turns.compactMap(\.costUSD).last ?? 0.0
        let totalTok = session?.contextTokens ?? turns.map(\.totalTokens).reduce(0, +)
        let proj = session?.project.isEmpty == false ? session!.project : "active"
        let branch = session?.branch.isEmpty == false ? " (\(session!.branch))" : ""
        let sessionId = session?.id ?? "unknown"

        out += "┌──────────────────────────────────────────────────────────────────────────────┐\n"
        out += "│ ⚡️ CLAUDE CODE SESSION REPLAY: \(proj)\(branch)\n"
        out += "│ ID: \(sessionId)\n"
        out += "│ Turns: \(turns.count)  ·  Context: \(Formatters.tokens(totalTok)) tok  ·  Cost: \(Formatters.usd(totalCost))\n"
        out += "└──────────────────────────────────────────────────────────────────────────────┘\n\n"

        if turns.isEmpty {
            out += "No conversation turns recorded in this session transcript yet.\n"
            return out
        }

        for turn in turns {
            out += formatTurn(turn, verbose: verbose)
            out += "\n"
        }

        return out
    }

    /// Converts turns into structured JSON dictionary.
    static func turnsToJSON(turns: [ConversationTurn], session: SessionAgg?) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let session {
            dict["sessionId"] = session.id
            dict["project"] = session.project
            dict["branch"] = session.branch
            dict["totalCostUsd"] = session.totalCost
            dict["contextTokens"] = session.contextTokens
        }
        dict["turnsCount"] = turns.count

        dict["turns"] = turns.map { t in
            [
                "turnIndex": t.turnIndex,
                "id": t.id,
                "timestamp": ISO8601DateFormatter().string(from: t.timestamp),
                "model": t.model,
                "prompt": t.userPrompt,
                "assistantText": t.assistantText,
                "inputTokens": t.inputTokens,
                "outputTokens": t.outputTokens,
                "cacheTokens": t.cacheTokens,
                "totalTokens": t.totalTokens,
                "costUSD": t.costUSD as Any,
                "toolCalls": t.toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "name": tc.name,
                        "inputSummary": tc.inputSummary,
                        "isError": tc.isError,
                        "result": tc.result as Any
                    ] as [String: Any]
                }
            ] as [String: Any]
        }

        return dict
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength)) + "..."
    }
}
