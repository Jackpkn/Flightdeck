import SwiftUI

/// A high-frequency, Metal-accelerated timeline scrubber rendering a live
/// dual-layer telemetry heatmap (CPU, GPU, Network) across a rolling 10-minute ring buffer.
/// Features a glowing playhead, real-time scrubbing HUD, and historical inspection.
struct TimelineScrubber: View {
    @State private var store = TimelineStore.shared
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = store.points
        let count = data.count
        let activePoint = store.scrubbedPoint

        VStack(spacing: 4) {
            // Header Bar with Inspector Telemetry Readout
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    LiveDot(color: store.scrubFraction == nil ? Theme.accent : Theme.warning)
                    Text(store.scrubFraction == nil ? "LIVE STREAM" : "HISTORICAL SCRUB")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(store.scrubFraction == nil ? Theme.accent : Theme.warning)
                }

                if let pt = activePoint {
                    let timeStr = pt.timestamp.formatted(date: .omitted, time: .standard)
                    HStack(spacing: 10) {
                        Text(timeStr)
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.ink1)

                        HStack(spacing: 3) {
                            Text("CPU").font(Theme.mono(7.5, weight: .bold)).foregroundStyle(Theme.ink3)
                            Text(String(format: "%.1f%%", pt.cpu))
                                .font(Theme.mono(8.5, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }

                        HStack(spacing: 3) {
                            Text("GPU").font(Theme.mono(7.5, weight: .bold)).foregroundStyle(Theme.ink3)
                            Text(String(format: "%.1f%%", pt.gpu))
                                .font(Theme.mono(8.5, weight: .semibold))
                                .foregroundStyle(Theme.gpuColor)
                        }

                        HStack(spacing: 3) {
                            Text("NET").font(Theme.mono(7.5, weight: .bold)).foregroundStyle(Theme.ink3)
                            Text(String(format: "%.0f KB/s", pt.netKB))
                                .font(Theme.mono(8.5, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                        }

                        HStack(spacing: 3) {
                            Text("RAM").font(Theme.mono(7.5, weight: .bold)).foregroundStyle(Theme.ink3)
                            Text(ByteCountFormatter.string(fromByteCount: pt.memBytes, countStyle: .memory))
                                .font(Theme.mono(8.5, weight: .semibold))
                                .foregroundStyle(Theme.copilotColor)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.track.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline2, lineWidth: 0.5))
                }

                Spacer()

                if store.scrubFraction != nil {
                    Button {
                        CockpitAudio.playPing()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            store.scrubFraction = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "forward.fill").font(.system(size: 7))
                            Text("RETURN TO LIVE").font(Theme.mono(8, weight: .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }

                Text("\(count)s RECORDED · 10M BUFFER")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.ink3.opacity(0.7))
            }
            .padding(.horizontal, 4)

            // The Interactive Canvas Heatmap
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        guard count > 0 else {
                            // Empty state scanning grid
                            let line = Path { p in
                                p.move(to: CGPoint(x: 0, y: size.height / 2))
                                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                            }
                            context.stroke(line, with: .color(Theme.hairline), lineWidth: 1)
                            return
                        }

                        let barWidth = max(1.5, width / CGFloat(max(1, count)))

                        for (idx, pt) in data.enumerated() {
                            let x = (CGFloat(idx) / CGFloat(max(1, count))) * width
                            let cpuFrac = min(1.0, max(0.02, CGFloat(pt.cpu) / 100.0))
                            let gpuFrac = min(1.0, max(0.0, CGFloat(pt.gpu) / 100.0))
                            let netFrac = min(1.0, max(0.0, CGFloat(pt.netKB) / 2000.0))

                            let totalH = max(2.0, cpuFrac * height * 0.75)
                            let gpuH = gpuFrac * height * 0.35
                            let netH = netFrac * height * 0.20

                            // CPU bar: cyan gradient
                            let cpuRect = CGRect(
                                x: x,
                                y: height - totalH,
                                width: barWidth,
                                height: totalH
                            )
                            let cpuAlpha = 0.25 + (pt.cpu / 100.0) * 0.70
                            context.fill(Path(cpuRect), with: .color(Theme.accent.opacity(cpuAlpha)))

                            // GPU peak bar overlay: magenta
                            if gpuH > 1.5 {
                                let gpuRect = CGRect(
                                    x: x,
                                    y: height - totalH - gpuH,
                                    width: barWidth,
                                    height: gpuH
                                )
                                context.fill(Path(gpuRect), with: .color(Theme.gpuColor.opacity(0.8)))
                            }

                            // Network throughput bottom line: amber
                            if netH > 1.0 {
                                let netRect = CGRect(
                                    x: x,
                                    y: height - netH,
                                    width: barWidth,
                                    height: netH
                                )
                                context.fill(Path(netRect), with: .color(Theme.warning.opacity(0.9)))
                            }
                        }

                        // Playhead Rendering
                        let currentFrac = store.scrubFraction ?? 1.0
                        let playheadX = min(width - 1, max(0, currentFrac * width))

                        // Glowing Aura
                        var glow = Path()
                        glow.move(to: CGPoint(x: playheadX, y: 0))
                        glow.addLine(to: CGPoint(x: playheadX, y: height))
                        context.stroke(glow, with: .color(Theme.accent.opacity(0.35)), lineWidth: 5.0)

                        // Core Razor Line
                        var line = Path()
                        line.move(to: CGPoint(x: playheadX, y: 0))
                        line.addLine(to: CGPoint(x: playheadX, y: height))
                        context.stroke(line, with: .color(Color.white.opacity(0.95)), lineWidth: 1.5)
                    }

                    // Interactive Gestures Overlay
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let frac = min(1.0, max(0.0, val.location.x / width))
                                    store.scrubFraction = frac
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                isHovering = true
                                hoverLocation = loc
                            case .ended:
                                isHovering = false
                                hoverLocation = nil
                            }
                        }
                }
            }
            .frame(height: 38)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.panel.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.hairline2, lineWidth: 1)
            )
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassPanel(cornerRadius: 10, accent: Theme.accent)
    }
}
