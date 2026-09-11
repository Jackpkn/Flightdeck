import SwiftUI
import AppKit

/// Cockpit inspection modal displaying deep telemetry for a Claude Code session:
/// active model(s), comprehensive token consumption (input, output, thinking, cache read/creation),
/// exact session costs directly from JSON, context window capacity, and activity stats.
struct SessionDetailModal: View {
    let session: SessionAgg
    let onDismiss: () -> Void

    @State private var copied = false
    private var projectColor: Color {
        Theme.colorForProject(session.project)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .onTapGesture {
                    CockpitAudio.playPing()
                    onDismiss()
                }

            // Modal Card
            VStack(alignment: .leading, spacing: 18) {
                header
                sessionMetaBar
                heroStats
                tokenBreakdownSection
                if !session.modelUsages.isEmpty {
                    modelBreakdownSection
                }
                contextWindowSection
                footerDetails
            }
            .padding(24)
            .frame(width: 580)
            .background(Theme.panel.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(projectColor.opacity(0.4), lineWidth: 1.5)
            )
            .cornerBracket(color: projectColor)
            .shadow(color: projectColor.opacity(0.18), radius: 30)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(projectColor)
                .frame(width: 10, height: 10)

            Text(session.project)
                .font(Theme.ui(17, weight: .bold))
                .foregroundStyle(Theme.ink1)

            // Dynamic model pill
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text(session.displayModel)
                    .font(Theme.mono(11, weight: .semibold))
            }
            .foregroundStyle(Theme.claudeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.claudeColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.claudeColor.opacity(0.3), lineWidth: 1))

            Spacer()

            StatusPill(active: session.isActive)

            Button {
                CockpitAudio.playPing()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Session Meta Bar

    private var sessionMetaBar: some View {
        HStack(spacing: 12) {
            // Session ID with click-to-copy
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
                CockpitAudio.playPing()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    copied = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? Theme.good : Theme.ink3)
                    Text(copied ? "COPIED ID" : session.id)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(copied ? Theme.good : Theme.ink2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(copied ? Theme.good.opacity(0.4) : Theme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Copy Session UUID")

            if !session.branch.isEmpty {
                HStack(spacing: 4) {
                    Text("⎇")
                        .font(Theme.mono(11))
                    Text(session.branch)
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            if session.toolUseCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                    Text("\(session.toolUseCount) actions")
                        .font(Theme.mono(10.5))
                }
                .foregroundStyle(Theme.ink3)
            }
        }
    }

    // MARK: - Hero Stats

    private var heroStats: some View {
        HStack(spacing: 12) {
            // Total Cost
            VStack(alignment: .leading, spacing: 4) {
                Text("TOTAL SESSION SPEND")
                    .font(Theme.mono(9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                Text(Formatters.usd(session.totalCost))
                    .font(Theme.mono(22, weight: .bold))
                    .foregroundStyle(Theme.good)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // Session duration — real wall-clock time reported by Claude Code.
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION LENGTH")
                    .font(Theme.mono(9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Formatters.duration(session.duration))
                        .font(Theme.mono(22, weight: .bold))
                        .foregroundStyle(session.duration == nil ? Theme.ink3 : Theme.ink1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

            // Total Tokens
            VStack(alignment: .leading, spacing: 4) {
                Text("TOKENS CONSUMED")
                    .font(Theme.mono(9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                Text(Formatters.tokens(session.totalTokens))
                    .font(Theme.mono(22, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: - Token Breakdown

    private var tokenBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOKEN CONSUMPTION BREAKDOWN")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if session.cacheHitRatio > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(Int(session.cacheHitRatio * 100))% CACHE HIT")
                            .font(Theme.mono(10, weight: .bold))
                    }
                    .foregroundStyle(Theme.good)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.good.opacity(0.12), in: Capsule())
                }
            }

            // Proportional Token Bar
            if session.totalTokens > 0 {
                proportionalTokenBar
            }

            // Grid of token values
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                TokenMetricCell(label: "INPUT TOKENS", value: session.inputTokens, color: Color.blue)
                TokenMetricCell(label: "OUTPUT TOKENS", value: session.outputTokens, color: Color.purple)
                TokenMetricCell(label: "THINKING TOKENS", value: session.thinkingTokens, color: Color.pink, footnote: "part of output")
                TokenMetricCell(label: "CACHE READ", value: session.cacheReadTokens, color: Color.teal)
                TokenMetricCell(label: "CACHE WRITE", value: session.cacheCreationTokens, color: Color.orange)
                TokenMetricCell(label: "TOTAL TOKENS", value: session.totalTokens, color: Theme.accent)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    private var proportionalTokenBar: some View {
        GeometryReader { proxy in
            let total = max(1, Double(session.totalTokens))
            let inW = (Double(session.inputTokens) / total) * proxy.size.width
            let outW = (Double(session.outputTokens) / total) * proxy.size.width
            let readW = (Double(session.cacheReadTokens) / total) * proxy.size.width
            let createW = (Double(session.cacheCreationTokens) / total) * proxy.size.width
            // Thinking tokens are part of output, so they are nested inside that
            // segment rather than added as a sixth one that overflows the bar.
            let thinkShare = session.outputTokens > 0
                ? Double(session.thinkingTokens) / Double(session.outputTokens) : 0

            HStack(spacing: 2) {
                if inW > 0 { Rectangle().fill(Color.blue).frame(width: max(2, inW)) }
                if outW > 0 {
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: max(2, outW))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.pink).frame(width: max(2, outW) * thinkShare)
                        }
                }
                if readW > 0 { Rectangle().fill(Color.teal).frame(width: max(2, readW)) }
                if createW > 0 { Rectangle().fill(Color.orange).frame(width: max(2, createW)) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }

    // MARK: - Model Breakdown

    private var modelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODELS UTILIZED")
                .font(Theme.mono(10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.ink3)

            VStack(spacing: 6) {
                ForEach(session.modelUsages.keys.sorted(), id: \.self) { modelKey in
                    if let usage = session.modelUsages[modelKey] {
                        HStack(spacing: 8) {
                            Text(modelKey)
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.ink1)
                            Spacer()
                            Text("\(Formatters.tokens(usage.totalTokens)) tokens")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.ink2)
                            if usage.costUSD > 0 {
                                Text(Formatters.usd(usage.costUSD))
                                    .font(Theme.mono(11, weight: .semibold))
                                    .foregroundStyle(Theme.good)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline2, lineWidth: 1))
    }

    // MARK: - Context Window

    private var contextWindowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONTEXT WINDOW UTILIZATION")
                    .font(Theme.mono(10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                Text("\(Formatters.tokens(session.contextTokens)) / \(Formatters.tokens(session.contextTotalTokens)) · \(Int(session.contextFraction * 100))%")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(session.contextFraction > 0.7 ? Theme.warning : Theme.claudeColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(session.contextFraction > 0.7 ? Theme.warning : Theme.claudeColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(session.contextFraction)))
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Footer Details

    private var footerDetails: some View {
        HStack(spacing: 16) {
            if !session.lastFile.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                    Text(URL(fileURLWithPath: session.lastFile).lastPathComponent)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
            }

            if !session.cwd.isEmpty {
                Button {
                    let url = URL(fileURLWithPath: session.cwd)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(URL(fileURLWithPath: session.cwd).lastPathComponent)
                            .font(Theme.mono(10.5))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Reveal workspace folder in Finder")
            }

            Spacer()

            if let lastSeen = session.lastSeen {
                Text("Seen \(lastSeen.formatted(date: .omitted, time: .standard))")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Subviews

private struct TokenMetricCell: View {
    let label: String
    let value: Int
    let color: Color
    /// Set for buckets that break down another figure instead of adding to it.
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(Theme.mono(9, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Text(Formatters.tokens(value))
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(Theme.ink1)
            if let footnote {
                Text(footnote)
                    .font(Theme.mono(8.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline2, lineWidth: 1))
    }
}

private struct StatusPill: View {
    let active: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Theme.good : Theme.ink3)
                .frame(width: 6, height: 6)
                .shadow(color: active ? Theme.good.opacity(0.85) : .clear, radius: 4)
            Text(active ? "ACTIVE" : "IDLE")
                .font(Theme.mono(11, weight: .semibold))
        }
        .foregroundStyle(active ? Theme.good : Theme.ink3)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background((active ? Theme.good : Color.white).opacity(active ? 0.13 : 0.05), in: Capsule())
    }
}
