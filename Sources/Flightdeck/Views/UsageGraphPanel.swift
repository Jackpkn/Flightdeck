import SwiftUI

/// Real telemetry timeline — total CPU% and total resident memory across
/// tracked apps, sampled every 2s by ProcessMonitor, last 2 minutes.
/// Features interactive peaks, metric series toggles ([CPU], [MEM], [NET], [DISK]),
/// and crosshair hover tooltips.
struct UsageGraphPanel: View {
    @Environment(ProcessMonitor.self) private var monitor
    @State private var showCPU = true
    @State private var showGPU = true
    @State private var showMem = true
    @State private var showNet = false
    @State private var showDisk = false
    @State private var hoverX: CGFloat?
    @State private var peakJumped = false

    private var currentCPU: Double { monitor.cpuHistory.last ?? 0 }
    private var currentMemory: Double { monitor.memoryHistory.last ?? 0 }

    // Real hardware network and disk throughput history from ProcessMonitor
    private var netHistory: [Double] { monitor.netHistory }
    private var diskHistory: [Double] { monitor.diskHistory }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Stacked Telemetry Graphs with unified crosshair
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 8) {
                        if showCPU {
                            SeriesChart(
                                values: monitor.cpuHistory,
                                color: Theme.accent,
                                floorMax: 20,
                                markPeak: true,
                                onPeakClick: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        peakJumped = true
                                    }
                                    CockpitAudio.playPing()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        peakJumped = false
                                    }
                                }
                            )
                            .frame(height: showGPU || showMem || showNet || showDisk ? 116 : 180)
                        }

                        if showGPU {
                            SeriesChart(
                                values: monitor.gpuHistory,
                                color: Theme.gpuColor,
                                floorMax: 20,
                                markPeak: true
                            )
                            .frame(height: showCPU || showMem || showNet || showDisk ? 72 : 180)
                        }

                        if showMem {
                            SeriesChart(
                                values: monitor.memoryHistory,
                                color: Theme.copilotColor,
                                floorMax: 1_073_741_824, // 1 GB
                                markPeak: false
                            )
                            .frame(height: 54)
                        }

                        if showNet {
                            SeriesChart(
                                values: netHistory,
                                color: Theme.accentSecondary,
                                floorMax: 40,
                                markPeak: false
                            )
                            .frame(height: 48)
                        }

                        if showDisk {
                            SeriesChart(
                                values: diskHistory,
                                color: Theme.warning,
                                floorMax: 30,
                                markPeak: false
                            )
                            .frame(height: 48)
                        }
                    }

                    // Hover Crosshair and floating Cyberpunk tooltip
                    if let hx = hoverX, hx >= 0, hx <= geo.size.width {
                        // Vertical scanline
                        Rectangle()
                            .fill(Theme.accent.opacity(0.45))
                            .frame(width: 1)
                            .offset(x: hx)
                            .allowsHitTesting(false)

                        // Floating HUD Tooltip
                        hoverTooltip(at: hx, width: geo.size.width)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverX = location.x
                    case .ended:
                        hoverX = nil
                    }
                }
            }
            .frame(height: computedGraphHeight)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: peakJumped ? Theme.warning : Theme.accent)
        .cornerBracket(color: peakJumped ? Theme.warning : Theme.accent)
        .shadow(color: peakJumped ? Theme.warning.opacity(0.3) : Color.clear, radius: 14)
    }

    private var computedGraphHeight: CGFloat {
        var h: CGFloat = 0
        let others = showGPU || showMem || showNet || showDisk
        if showCPU { h += (others ? 116 : 180) }
        if showGPU { h += ((showCPU || showMem || showNet || showDisk) ? 72 : 180) + (showCPU ? 8 : 0) }
        if showMem { h += 54 + 8 }
        if showNet { h += 48 + 8 }
        if showDisk { h += 48 + 8 }
        return max(100, h)
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("SYSTEM LOAD · LAST 2 MIN")
                .font(Theme.display(12, weight: .bold)).tracking(0.6).foregroundStyle(Theme.ink2)

            if peakJumped {
                Text("PEAK JUMP")
                    .font(Theme.mono(10.5, weight: .bold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(Theme.warning.opacity(0.18), in: RoundedRectangle(cornerRadius: 3.5))
            }

            Spacer()

            // Metric Toggle Pills
            HStack(spacing: 4) {
                metricToggle(title: "CPU", color: Theme.accent, isOn: $showCPU)
                metricToggle(title: "GPU", color: Theme.gpuColor, isOn: $showGPU)
                metricToggle(title: "MEM", color: Theme.copilotColor, isOn: $showMem)
                metricToggle(title: "NET", color: Theme.accentSecondary, isOn: $showNet)
                metricToggle(title: "DISK", color: Theme.warning, isOn: $showDisk)
            }
        }
    }

    private func metricToggle(title: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Theme.ink3)
                    .frame(width: 5.5, height: 5.5)
                Text(title)
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Theme.ink1 : Theme.ink3)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                isOn.wrappedValue ? color.opacity(0.16) : Theme.track.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isOn.wrappedValue ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func hoverTooltip(at x: CGFloat, width: CGFloat) -> some View {
        let count = max(1, monitor.cpuHistory.count)
        let ratio = max(0, min(1, x / width))
        let index = min(count - 1, Int(round(ratio * CGFloat(count - 1))))
        let cpuVal = monitor.cpuHistory.indices.contains(index) ? monitor.cpuHistory[index] : currentCPU
        let memVal = monitor.memoryHistory.indices.contains(index) ? monitor.memoryHistory[index] : currentMemory
        let secondsAgo = (count - 1 - index) * 2
        let time = Date().addingTimeInterval(TimeInterval(-secondsAgo))

        HStack(spacing: 8) {
            Text(time.formatted(date: .omitted, time: .standard))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.ink3)

            Text("•")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.ink3.opacity(0.5))

            HStack(spacing: 3) {
                Text("CPU:").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                Text(String(format: "%.0f%%", cpuVal)).font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.accent)
            }

            if showGPU {
                let gpuVal = monitor.gpuHistory.indices.contains(index) ? monitor.gpuHistory[index] : monitor.currentGPU.utilizationPercent
                HStack(spacing: 3) {
                    Text("GPU:").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                    Text(String(format: "%.0f%%", gpuVal)).font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.gpuColor)
                }
            }

            HStack(spacing: 3) {
                Text("MEM:").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                Text(ByteCountFormatter.string(fromByteCount: Int64(memVal), countStyle: .memory))
                    .font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.copilotColor)
            }

            if showNet && netHistory.indices.contains(index) {
                HStack(spacing: 3) {
                    Text("NET:").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                    Text(String(format: "%.0f KB/s", netHistory[index]))
                        .font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.accentSecondary)
                }
            }

            if showDisk && diskHistory.indices.contains(index) {
                HStack(spacing: 3) {
                    Text("DISK:").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                    Text(String(format: "%.0f KB/s", diskHistory[index]))
                        .font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5).stroke(Theme.accent.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 6)
        .offset(x: min(max(8, x - 120), width - 340), y: -6)
        .allowsHitTesting(false)
    }
}

private struct SeriesChart: View {
    let values: [Double]
    let color: Color
    let floorMax: Double
    let markPeak: Bool
    var onPeakClick: (() -> Void)? = nil

    var body: some View {
        Canvas { context, size in
            let topInset: CGFloat = markPeak ? 22 : 6
            let bottomInset: CGFloat = 4
            let usableHeight = max(10, size.height - topInset - bottomInset)

            for fraction in [0.0, 0.5, 1.0] {
                let y = topInset + usableHeight * (1 - fraction)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Theme.hairline2), lineWidth: 1)
            }

            guard values.count > 1 else { return }
            let maxV = max(values.max() ?? floorMax, floorMax)
            let stepX = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { i, v in
                CGPoint(
                    x: CGFloat(i) * stepX,
                    y: topInset + (1.0 - CGFloat(min(v / maxV, 1.0))) * usableHeight
                )
            }

            let line = Self.smoothed(points)

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            var glow = context
            glow.addFilter(.blur(radius: 2.5))
            glow.stroke(line, with: .color(color.opacity(0.6)), lineWidth: 3)
            context.stroke(line, with: .color(color), lineWidth: 1.6)

            if markPeak, let peakIndex = values.indices.max(by: { values[$0] < values[$1] }), values[peakIndex] > 0 {
                let p = points[peakIndex]
                context.stroke(
                    Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                    with: .color(color),
                    lineWidth: 1.8
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                    with: .color(Theme.warning)
                )

                let label = Text(String(format: "PEAK %.0f%%", values[peakIndex]))
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.warning)

                // Place horizontally without overflowing canvas edges
                let labelWidth: CGFloat = 64
                let textX: CGFloat
                if p.x + labelWidth + 8 > size.width {
                    textX = max(p.x - 42, 34)
                } else {
                    textX = p.x + 36
                }

                // Place vertically so it never hides on top
                let textY: CGFloat = p.y < 24 ? p.y + 16 : p.y - 12

                // Floating contrast badge background for crisp visibility
                let badgeRect = CGRect(x: textX - 30, y: textY - 8, width: 60, height: 16)
                context.fill(Path(roundedRect: badgeRect, cornerRadius: 3.5), with: .color(Theme.panel.opacity(0.92)))
                context.stroke(Path(roundedRect: badgeRect, cornerRadius: 3.5), with: .color(Theme.warning.opacity(0.5)), lineWidth: 0.8)

                context.draw(label, at: CGPoint(x: textX, y: textY))
            }

            let end = points[points.count - 1]
            context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
        }
        .overlay(alignment: .topTrailing) {
            if markPeak, let onPeakClick {
                Button(action: onPeakClick) {
                    Color.clear.frame(width: 80, height: 36)
                }
                .buttonStyle(.plain)
                .help("Jump to peak activity in feed")
            }
        }
    }

    private static func smoothed(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) / 2,
                y: (points[i].y + points[i + 1].y) / 2
            )
            if i == 0 {
                path.addLine(to: mid)
            } else {
                path.addQuadCurve(to: mid, control: points[i])
            }
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
