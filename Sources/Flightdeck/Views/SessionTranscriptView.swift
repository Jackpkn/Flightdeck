import SwiftUI
import AppKit

/// Displays the full interactive turn timeline, prompts, tool calls, and assistant responses
/// parsed from a Claude Code session's .jsonl transcript.
struct SessionTranscriptView: View {
    let session: SessionAgg
    let turns: [ConversationTurn]
    let isLoading: Bool

    @State private var searchQuery: String = ""
    @State private var expandedTurnIds: Set<String> = []
    @State private var expandedThinkingIds: Set<String> = []
    @State private var expandedToolIds: Set<String> = []
    @State private var copiedTurnId: String? = nil

    private var filteredTurns: [ConversationTurn] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return turns
        }
        let q = searchQuery.lowercased()
        return turns.filter { turn in
            turn.userPrompt.lowercased().contains(q) ||
            turn.assistantText.lowercased().contains(q) ||
            turn.toolCalls.contains { $0.name.lowercased().contains(q) || $0.inputSummary.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar & Search
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Text("CONVERSATION TURNS (\(turns.count))")
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(Theme.ink1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                    TextField("Filter prompts, tools, responses...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(11))
                        .frame(width: 220)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
            }

            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Reading session transcript...")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if turns.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.ink3)
                    Text("No transcript file found for this session")
                        .font(Theme.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                    Text("Transcripts are retained in ~/.claude/projects/ while active.")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTurns.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.ink3)
                    Text("No turns match \"\(searchQuery)\"")
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredTurns) { turn in
                            turnCard(turn)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One conversation turn.
    ///
    /// Split into named sub-views rather than one long builder: as a single
    /// expression this took the Swift type-checker ~22 seconds on its own, which
    /// dominated every build of the whole app.
    @ViewBuilder
    private func turnCard(_ turn: ConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            turnHeader(turn)
            userPromptBubble(turn)
            thinkingBlock(turn)
            if !turn.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.toolCalls) { tool in
                        toolCallRow(tool)
                    }
                }
            }
            assistantResponse(turn)
        }
        .padding(14)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func turnHeader(_ turn: ConversationTurn) -> some View {
        HStack(spacing: 8) {
            Text("TURN #\(turn.turnIndex)")
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(turn.timestamp.formatted(date: .omitted, time: .standard))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.ink3)

            if !turn.model.isEmpty {
                Text("· \(turn.model)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.claudeColor)
            }

            Spacer()

            turnCostPill(turn)
            copyTurnButton(turn)
        }
    }

    @ViewBuilder
    private func turnCostPill(_ turn: ConversationTurn) -> some View {
        HStack(spacing: 6) {
            if turn.totalTokens > 0 {
                Text("\(Formatters.tokens(turn.totalTokens)) tok")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
            }
            if let cost = turn.costUSD, cost > 0 {
                Text(Formatters.usd(cost))
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.good)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.white.opacity(0.03), in: Capsule())
    }

    @ViewBuilder
    private func copyTurnButton(_ turn: ConversationTurn) -> some View {
        Button {
            let fullText = "User: \(turn.userPrompt)\n\nAssistant: \(turn.assistantText)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullText, forType: .string)
            CockpitAudio.playPing()
            copiedTurnId = turn.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedTurnId = nil }
        } label: {
            Image(systemName: copiedTurnId == turn.id ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(copiedTurnId == turn.id ? Theme.good : Theme.ink3)
        }
        .buttonStyle(.plain)
        .help("Copy this turn")
    }

    @ViewBuilder
    private func userPromptBubble(_ turn: ConversationTurn) -> some View {
        if !turn.userPrompt.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 3)

                Text(turn.userPrompt)
                    .font(Theme.ui(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink1)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func thinkingBlock(_ turn: ConversationTurn) -> some View {
        if let thinking = turn.thinkingText, !thinking.isEmpty {
            let isExpanded = expandedThinkingIds.contains(turn.id)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if isExpanded {
                        expandedThinkingIds.remove(turn.id)
                    } else {
                        expandedThinkingIds.insert(turn.id)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10))
                        Text("THINKING PROCESS (\(thinking.count) chars)")
                            .font(Theme.mono(9.5, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.pink.opacity(0.85))
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(thinking)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(Color.pink.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.18), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func assistantResponse(_ turn: ConversationTurn) -> some View {
        if !turn.assistantText.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.claudeColor)
                    .padding(.top, 3)

                Text(turn.assistantText)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.ink1)
                    .lineSpacing(2.5)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline2, lineWidth: 1))
        }
    }

    private func toolCallRow(_ tool: TranscriptToolCall) -> some View {
        let isExpanded = expandedToolIds.contains(tool.id)
        let toolColor: Color = tool.isBash ? Color.green : (tool.isEdit ? Color.orange : Color.blue)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if tool.result != nil {
                    if isExpanded {
                        expandedToolIds.remove(tool.id)
                    } else {
                        expandedToolIds.insert(tool.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if tool.result != nil {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.ink3)
                    }

                    Text(tool.name.uppercased())
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(toolColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(toolColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

                    Text(tool.inputSummary)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)

                    Spacer()

                    if tool.isError {
                        Text("ERROR")
                            .font(Theme.mono(8.5, weight: .bold))
                            .foregroundStyle(Theme.critical)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.critical.opacity(0.15), in: Capsule())
                    } else if tool.result != nil {
                        Text("COMPLETED")
                            .font(Theme.mono(8.5))
                            .foregroundStyle(Theme.good)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let res = tool.result, !res.isEmpty {
                Text(res.prefix(1500))
                    .font(Theme.mono(10))
                    .foregroundStyle(tool.isError ? Theme.critical : Theme.ink3)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
    }
}
