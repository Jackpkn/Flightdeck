import SwiftUI

struct SessionBoard: View {
    @Environment(DashboardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSION BOARD")
                .font(Theme.mono(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.ink3)

            if store.activeSessions.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(store.activeSessions.prefix(3)) { session in
                        SessionCard(session: session, color: Theme.colorForProject(session.project))
                    }
                }
                .reportFrame("__board__")
            }
        }
    }

    private var emptyState: some View {
        Text("No Claude Code sessions found yet under ~/.claude/projects — open a session and it will appear here within a few seconds.")
            .font(Theme.ui(12.5))
            .foregroundStyle(Theme.ink3)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 10)
    }
}

private struct SessionCard: View {
    let session: SessionAgg
    let color: Color
    @State private var glitching = false
    @State private var ripples: [RippleInstance] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 2) {
                Text(session.lastFile.isEmpty ? "no file touched yet" : URL(fileURLWithPath: session.lastFile).lastPathComponent)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                // Always render this row, even with a placeholder — a conditional
                // row here is exactly what made cards different heights before.
                Text(session.branch.isEmpty ? "no branch" : "⎇ \(session.branch)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            ContextMeter(fraction: session.contextFraction, tokens: session.contextTokens)
            HStack(alignment: .bottom) {
                (Text(Formatters.usd(session.burnRatePerMin)).font(Theme.mono(16, weight: .semibold))
                 + Text("/min").font(Theme.mono(11)).foregroundStyle(Theme.ink3))
                    .reportFrame(session.id)
                Spacer()
                Sparkline(values: session.sparkline, color: color)
                    .frame(width: 90, height: 28)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(session.isActive ? color.opacity(0.45) : Theme.hairline, lineWidth: session.isActive ? 1.5 : 1)
        )
        .shadow(color: session.isActive ? color.opacity(0.22) : .clear, radius: session.isActive ? 10 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RippleOverlay(ripples: ripples))
        .glitch(glitching)
        .onChange(of: session.lastErrorAt) { _, newValue in
            guard let newValue, newValue.timeIntervalSinceNow > -2 else { return }
            glitching = true
            spawnRipple(color: Theme.critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { glitching = false }
        }
        .onChange(of: session.costLedger.count) { _, _ in
            spawnRipple(color: color)
        }
    }

    private func spawnRipple(color: Color) {
        ripples.append(RippleInstance(spawnedAt: Date(), color: color))
        let cutoff = Date().addingTimeInterval(-1.2)
        ripples.removeAll { $0.spawnedAt < cutoff }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                    Text(session.project).font(Theme.ui(15, weight: .semibold))
                }
                Text(session.model.isEmpty ? "model unknown" : session.model)
                    .font(Theme.mono(11)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            StatusPill(active: session.isActive)
        }
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

private struct ContextMeter: View {
    let fraction: Double
    let tokens: Int

    private var fillColor: Color { fraction > 0.7 ? Theme.warning : Theme.claudeColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("CONTEXT").font(Theme.mono(11)).foregroundStyle(Theme.ink3)
                Spacer()
                Text("\(Formatters.tokens(tokens)) / 200,000 · \(Int(fraction * 100))%")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.ink1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(fillColor).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maxV = values.max(), maxV > 0 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                let v = values[i] / maxV
                return CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(v) * size.height)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .color(color.opacity(0.16)))
            context.stroke(line, with: .color(color), lineWidth: 1.6)

            let end = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
        }
    }
}
