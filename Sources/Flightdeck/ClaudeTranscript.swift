import Foundation

/// A single tool invocation made by Claude Code during a turn.
struct TranscriptToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    var inputSummary: String
    var result: String?
    var isError: Bool = false

    var isEdit: Bool {
        let n = name.lowercased()
        return n == "edit" || n == "multireplace" || n == "write"
    }

    var isBash: Bool {
        name.lowercased() == "bash"
    }
}

/// A complete user <-> assistant conversation turn in Claude Code.
struct ConversationTurn: Identifiable, Equatable {
    let id: String
    let turnIndex: Int
    var timestamp: Date
    var userPrompt: String
    var assistantText: String
    var thinkingText: String?
    var toolCalls: [TranscriptToolCall] = []
    var model: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
    var costUSD: Double? = nil

    var totalTokens: Int {
        inputTokens + outputTokens + cacheTokens
    }
}

/// On-demand streaming parser for Claude Code `.jsonl` session transcripts.
enum ClaudeTranscriptReader {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Locate the transcript file for a given session ID in ~/.claude/projects/
    static func locateTranscriptFile(sessionId: String) -> URL? {
        guard !sessionId.isEmpty, !sessionId.hasPrefix("proj-") else { return nil }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return nil }

        let targetFilename = "\(sessionId).jsonl"
        for case let url as URL in enumerator {
            if url.lastPathComponent == targetFilename {
                return url
            }
        }
        return nil
    }

    /// Reads and structures all conversation turns from a Claude Code `.jsonl` file.
    static func parseTurns(from fileURL: URL) -> [ConversationTurn] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return []
        }

        let content = String(decoding: data, as: UTF8.self)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var turns: [ConversationTurn] = []
        var currentTurn: ConversationTurn?
        var turnCounter = 1

        func finalizeCurrentTurn() {
            if let t = currentTurn, (!t.userPrompt.isEmpty || !t.assistantText.isEmpty || !t.toolCalls.isEmpty) {
                turns.append(t)
            }
            currentTurn = nil
        }

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else {
                continue
            }

            let ts: Date
            if let tsStr = obj["timestamp"] as? String {
                ts = isoFormatter.date(from: tsStr) ?? Date()
            } else {
                ts = Date()
            }

            switch type {
            case "user":
                // Check message content
                guard let message = obj["message"] as? [String: Any] else { continue }
                if let promptStr = message["content"] as? String {
                    // Start of a brand new user prompt -> finalize previous turn
                    finalizeCurrentTurn()
                    let turnId = obj["uuid"] as? String ?? UUID().uuidString
                    currentTurn = ConversationTurn(
                        id: turnId,
                        turnIndex: turnCounter,
                        timestamp: ts,
                        userPrompt: promptStr.trimmingCharacters(in: .whitespacesAndNewlines),
                        assistantText: "",
                        thinkingText: nil,
                        toolCalls: []
                    )
                    turnCounter += 1
                } else if let blocks = message["content"] as? [[String: Any]] {
                    // Tool results array
                    for block in blocks {
                        if block["type"] as? String == "tool_result",
                           let toolUseId = block["tool_use_id"] as? String {
                            let rawOutput: String
                            if let s = block["content"] as? String {
                                rawOutput = s
                            } else if let arr = block["content"] as? [[String: Any]] {
                                rawOutput = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                            } else {
                                rawOutput = ""
                            }
                            let isErr = block["is_error"] as? Bool ?? false

                            // Attach result to matching tool call in current turn
                            if var turn = currentTurn {
                                if let idx = turn.toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                                    turn.toolCalls[idx].result = rawOutput
                                    turn.toolCalls[idx].isError = isErr
                                    currentTurn = turn
                                }
                            }
                        }
                    }
                }

            case "assistant":
                guard let message = obj["message"] as? [String: Any] else { continue }

                if currentTurn == nil {
                    let turnId = obj["uuid"] as? String ?? UUID().uuidString
                    currentTurn = ConversationTurn(
                        id: turnId,
                        turnIndex: turnCounter,
                        timestamp: ts,
                        userPrompt: "",
                        assistantText: "",
                        thinkingText: nil,
                        toolCalls: []
                    )
                    turnCounter += 1
                }

                if let model = message["model"] as? String, currentTurn?.model.isEmpty ?? true {
                    currentTurn?.model = model
                }

                if let usage = message["usage"] as? [String: Any] {
                    if let inTok = usage["input_tokens"] as? Int {
                        currentTurn?.inputTokens += inTok
                    }
                    if let outTok = usage["output_tokens"] as? Int {
                        currentTurn?.outputTokens += outTok
                    }
                    let cr = usage["cache_read_input_tokens"] as? Int ?? 0
                    let cc = usage["cache_creation_input_tokens"] as? Int ?? 0
                    currentTurn?.cacheTokens += (cr + cc)
                }

                if let contentBlocks = message["content"] as? [[String: Any]] {
                    for block in contentBlocks {
                        let btype = block["type"] as? String ?? ""
                        if btype == "text", let text = block["text"] as? String {
                            if !(currentTurn?.assistantText.isEmpty ?? true) {
                                currentTurn?.assistantText.append("\n\n")
                            }
                            currentTurn?.assistantText.append(text)
                        } else if btype == "thinking", let think = block["thinking"] as? String {
                            var existing = currentTurn?.thinkingText ?? ""
                            if !existing.isEmpty { existing.append("\n\n") }
                            existing.append(think)
                            currentTurn?.thinkingText = existing
                        } else if btype == "tool_use" {
                            let toolId = block["id"] as? String ?? UUID().uuidString
                            let name = block["name"] as? String ?? "Tool"
                            let inputDict = block["input"] as? [String: Any] ?? [:]
                            let summary = summarizeToolInput(name: name, input: inputDict)

                            currentTurn?.toolCalls.append(
                                TranscriptToolCall(id: toolId, name: name, inputSummary: summary)
                            )
                        }
                    }
                }

            case "cost-state":
                if let cost = obj["costUSD"] as? Double ?? obj["totalCostUSD"] as? Double {
                    currentTurn?.costUSD = cost
                }

            default:
                break
            }
        }

        finalizeCurrentTurn()
        return turns
    }

    private static func summarizeToolInput(name: String, input: [String: Any]) -> String {
        switch name.lowercased() {
        case "bash":
            return input["command"] as? String ?? ""
        case "edit", "multireplace":
            if let file = input["file_path"] as? String {
                return URL(fileURLWithPath: file).lastPathComponent
            }
            return input["path"] as? String ?? ""
        case "view":
            if let file = input["file_path"] as? String {
                return URL(fileURLWithPath: file).lastPathComponent
            }
            return input["path"] as? String ?? ""
        case "glob":
            return input["pattern"] as? String ?? ""
        case "grep":
            return input["query"] as? String ?? input["pattern"] as? String ?? ""
        default:
            if let firstVal = input.values.first as? String {
                return firstVal
            }
            return ""
        }
    }
}
