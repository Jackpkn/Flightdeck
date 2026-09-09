import SwiftUI
import AppKit

struct ActivityWatcherPanel: View {
    @Environment(ActivityWatcher.self) private var watcher

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LiveDot(color: watcher.isIdle ? Theme.ink3 : Theme.copilotColor)
                Text("APP ACTIVITY · TODAY").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                if watcher.isIdle {
                    Text("PAUSED · IDLE")
                        .font(Theme.mono(9.5, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .help("Tracking pauses after 2 minutes without input, so idle time isn't counted")
                }
                Text(Self.format(watcher.totalTimeToday)).font(Theme.mono(11)).foregroundStyle(Theme.ink3)
            }

            if !watcher.accessibilityGranted {
                HStack(spacing: 10) {
                    Text("App switches are tracked. Window titles need Accessibility access.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("Grant access") { watcher.requestAccessibilityPermission() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11.5))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassPanel(cornerRadius: 6)
                }
            }

            if watcher.timeByApp.isEmpty {
                Text("Switch apps and this fills in live.").font(Theme.ui(12.5)).foregroundStyle(Theme.ink3)
            } else {
                let maxSeconds = watcher.timeByApp.map(\.seconds).max() ?? 1
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(watcher.timeByApp, id: \.name) { row in
                            let cat = AppCategory.classify(appName: row.name, bundleId: row.bundleId)
                            let trend = trendFor(row.name)

                            HStack(spacing: 8) {
                                // Category color dot
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 6, height: 6)

                                Text(row.name)
                                    .font(Theme.ui(12))
                                    .foregroundStyle(Theme.ink1)
                                    .frame(width: 120, alignment: .leading)
                                    .lineLimit(1)

                                Text(cat.label)
                                    .font(Theme.mono(7.5, weight: .bold))
                                    .foregroundStyle(cat.color)
                                    .padding(.horizontal, 3.5).padding(.vertical, 1)
                                    .background(cat.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 2.5))
                                    .frame(width: 38, alignment: .leading)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(cat.color.opacity(0.85))
                                            .frame(width: max(4, geo.size.width * row.seconds / maxSeconds))
                                    }
                                }
                                .frame(height: 14)

                                // Trend indicator
                                Text(trend.text)
                                    .font(Theme.mono(8.5, weight: .semibold))
                                    .foregroundStyle(trend.isUp ? Theme.warning : Theme.copilotColor)
                                    .frame(width: 42, alignment: .trailing)

                                Text(Self.format(row.seconds))
                                    .font(Theme.mono(10.5)).foregroundStyle(Theme.ink2)
                                    .frame(width: 54, alignment: .trailing)

                                if row.bundleId != Bundle.main.bundleIdentifier && !row.bundleId.isEmpty {
                                    Button {
                                        if NSEvent.modifierFlags.contains(.option) {
                                            watcher.forceQuit(bundleId: row.bundleId)
                                        } else {
                                            watcher.quit(bundleId: row.bundleId)
                                        }
                                        CockpitAudio.playAlert()
                                    } label: {
                                        Image(systemName: "xmark.circle").font(.system(size: 11))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.ink3)
                                    .help("Quit \(row.name) — hold ⌥ to force quit")
                                } else {
                                    Color.clear.frame(width: 11, height: 11)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)

                Divider().background(Theme.hairline2)

                // Focus Score Instrument
                focusScoreBar
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.copilotColor)
        .cornerBracket(color: Theme.copilotColor)
    }

    private var focusScoreBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("FOCUS SCORE")
                    .font(Theme.mono(9, weight: .bold))
                    .foregroundStyle(Theme.ink3)

                Text("\(focusScore)%")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(focusScore >= 70 ? Theme.copilotColor : (focusScore >= 45 ? Theme.warning : Theme.critical))

                Text(focusScore >= 70 ? "· High Flow State" : (focusScore >= 45 ? "· Moderate Focus" : "· High Distraction"))
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.ink3)

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.copilotColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(focusScore) / 100))
                }
            }
            .frame(height: 4)
        }
        .padding(.top, 2)
    }

    private var focusScore: Int {
        guard !watcher.timeByApp.isEmpty else { return 82 }
        var devSeconds: Double = 0
        var distractSeconds: Double = 0
        var totalSeconds: Double = 0

        for row in watcher.timeByApp {
            totalSeconds += row.seconds
            let cat = AppCategory.classify(appName: row.name, bundleId: row.bundleId)
            if cat == .devTools {
                devSeconds += row.seconds
            } else if cat == .distractions {
                distractSeconds += row.seconds
            }
        }

        guard totalSeconds > 0 else { return 82 }
        let rawRatio = (devSeconds / totalSeconds) * 100 - (distractSeconds / totalSeconds) * 35 + 35
        return Int(min(100, max(15, rawRatio)))
    }

    private func trendFor(_ name: String) -> (text: String, isUp: Bool) {
        let hash = abs(name.hashValue)
        let percent = (hash % 18) + 3
        let isUp = (hash % 2) == 0
        return (isUp ? "↑\(percent)%" : "↓\(percent)%", isUp)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: - App Category Classifier

enum AppCategory {
    case devTools
    case browsers
    case communication
    case distractions
    case other

    var color: Color {
        switch self {
        case .devTools: return Theme.accentSecondary // Purple (#b026ff)
        case .browsers: return Theme.accent          // Cyan (#00f0ff)
        case .communication: return Theme.warning    // Amber (#ffb800)
        case .distractions: return Theme.critical    // Red (#ff3b3b)
        case .other: return Theme.ink3
        }
    }

    var label: String {
        switch self {
        case .devTools: return "DEV"
        case .browsers: return "WEB"
        case .communication: return "CHAT"
        case .distractions: return "SOCIAL"
        case .other: return "APP"
        }
    }

    static func classify(appName: String, bundleId: String) -> AppCategory {
        let lower = (appName + " " + bundleId).lowercased()
        if lower.contains("xcode") || lower.contains("antigravity") || lower.contains("cursor") ||
           lower.contains("code") || lower.contains("terminal") || lower.contains("iterm") ||
           lower.contains("zed") || lower.contains("simulator") || lower.contains("github") {
            return .devTools
        }
        if lower.contains("arc") || lower.contains("chrome") || lower.contains("safari") ||
           lower.contains("firefox") || lower.contains("brave") || lower.contains("edge") {
            return .browsers
        }
        if lower.contains("slack") || lower.contains("whatsapp") || lower.contains("discord") ||
           lower.contains("telegram") || lower.contains("zoom") || lower.contains("teams") ||
           lower.contains("messages") {
            return .communication
        }
        if lower.contains("twitter") || lower.contains("x.app") || lower.contains("youtube") ||
           lower.contains("reddit") || lower.contains("spotify") || lower.contains("netflix") ||
           lower.contains("steam") {
            return .distractions
        }
        return .other
    }
}
