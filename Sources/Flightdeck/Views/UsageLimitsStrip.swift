import SwiftUI

/// Account rate-limit consumption — the five-hour session budget and the weekly
/// budgets — read from the figures Claude Code caches locally.
///
/// Nothing here is derived or estimated. When the cache is stale or absent the strip
/// says so instead of drawing a number that looks live.
struct UsageLimitsStrip: View {
    @Environment(ClaudeUsageMonitor.self) private var usage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let snapshot = usage.snapshot {
                content(for: snapshot)
            } else {
                emptyState
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.claudeColor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.claudeColor)
            Text("PLAN LIMITS")
                .font(Theme.mono(9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Spacer()
            freshnessBadge
        }
    }

    /// The numbers are only as current as Claude Code's last refresh, so the age of
    /// the reading is shown next to it rather than implied to be live.
    @ViewBuilder
    private var freshnessBadge: some View {
        if let snapshot = usage.snapshot {
            let age = snapshot.age(now: usage.tick)
            let stale = snapshot.isStale(now: usage.tick)
            HStack(spacing: 4) {
                Circle()
                    .fill(stale ? Theme.ink3 : Theme.good)
                    .frame(width: 5, height: 5)
                Text(stale ? "cached · \(Formatters.relativeAge(age))" : "live")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.ink3)
            }
            .help(stale
                  ? "Claude Code last refreshed these figures \(Formatters.relativeAge(age)). They update while a session is running."
                  : "Refreshed by Claude Code moments ago")
        }
    }

    @ViewBuilder
    private func content(for snapshot: ClaudeUsageSnapshot) -> some View {
        let live = snapshot.liveLimits(now: usage.tick)
        if live.isEmpty {
            Text("Every reported window has passed its reset time — start a session to refresh.")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(live) { limit in
                    LimitGauge(limit: limit, now: usage.tick)
                }
                if snapshot.extraUsageEnabled {
                    extraUsagePill
                }
            }
        }
    }

    private var extraUsagePill: some View {
        Text("EXTRA USAGE ON")
            .font(Theme.mono(8.5, weight: .bold))
            .foregroundStyle(Theme.good)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Theme.good.opacity(0.14), in: Capsule())
            .help("Pay-as-you-go usage is enabled, so work continues past these limits at cost")
    }

    private var emptyState: some View {
        Text("No plan-limit data in ~/.claude.json yet. Claude Code writes it after a session talks to the API.")
            .font(Theme.mono(10.5))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One limit window: how much is gone, and how long until it resets.
private struct LimitGauge: View {
    let limit: ClaudeUsageLimit
    let now: Date

    private var color: Color {
        switch limit.effectiveSeverity {
        case .normal:   return Theme.good
        case .warning:  return Theme.warning
        case .critical: return Theme.critical
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(limit.label)
                    .font(Theme.mono(9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                if limit.isActive {
                    LiveDot(color: color)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(limit.percent)")
                    .font(Theme.mono(17, weight: .bold))
                    .foregroundStyle(Theme.ink1)
                Text("%")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 6)
                Text(Formatters.countdown(limit.timeUntilReset(now: now)))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * limit.fraction))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(helpText)
    }

    private var helpText: String {
        var parts = ["\(limit.percent)% of the \(limit.label.lowercased()) budget used"]
        if let resetsAt = limit.resetsAt {
            parts.append("resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }
}
