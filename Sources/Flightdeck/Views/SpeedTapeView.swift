import SwiftUI

/// Scrolling vertical airspeed-style tape gauge showing real-time network
/// throughput in KB/s. The tape scrolls vertically and a fixed pointer on
/// the right edge indicates the current value.
struct SpeedTapeView: View {
    @Environment(ProcessMonitor.self) private var monitor
    let date: Date

    private var currentKB: Double { monitor.currentNetKB }
    private var history: [Double] { monitor.netHistory }

    /// Dynamic ceiling — round up to nearest nice number above peak.
    private var ceiling: Double {
        let peak = max(100, history.max() ?? 100, currentKB)
        if peak < 500 { return 500 }
        if peak < 1000 { return 1000 }
        if peak < 5000 { return 5000 }
        if peak < 10000 { return 10000 }
        return ceil(peak / 5000) * 5000
    }

    var body: some View {
        Canvas { context, size in
            let pointerY = size.height / 2

            drawTapeBackground(context: context, size: size)
            drawTickMarks(context: context, size: size, pointerY: pointerY)
            drawTrendVector(context: context, size: size, pointerY: pointerY)
            drawPointer(context: context, size: size, pointerY: pointerY)
            drawBugMarkers(context: context, size: size)
            drawLabel(context: context, size: size)
        }
    }

    // MARK: - Tape background

    private func drawTapeBackground(context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(Color(hex: 0x060810).opacity(0.85)))

        // Left border line
        var leftBorder = Path()
        leftBorder.move(to: CGPoint(x: 1, y: 0))
        leftBorder.addLine(to: CGPoint(x: 1, y: size.height))
        context.stroke(leftBorder, with: .color(Theme.accentSecondary.opacity(0.4)), lineWidth: 1)
    }

    // MARK: - Scrolling tick marks

    private func drawTickMarks(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        let pixelsPerKB = size.height / ceiling
        let currentOffset = currentKB * pixelsPerKB

        // Draw ticks from 0 to ceiling
        let majorInterval = ceiling > 2000 ? 1000.0 : (ceiling > 500 ? 200.0 : 100.0)
        let minorInterval = majorInterval / 5

        var value: Double = 0
        while value <= ceiling * 2 {
            let y = pointerY + currentOffset - value * pixelsPerKB

            if y < -20 || y > size.height + 20 {
                value += minorInterval
                continue
            }

            let isMajor = value.truncatingRemainder(dividingBy: majorInterval) < 0.1

            if isMajor {
                // Major tick + label
                var tick = Path()
                tick.move(to: CGPoint(x: 4, y: y))
                tick.addLine(to: CGPoint(x: 18, y: y))
                context.stroke(tick, with: .color(Theme.accentSecondary.opacity(0.6)), lineWidth: 1)

                let label: String
                if value >= 1000 {
                    label = String(format: "%.0fK", value / 1000)
                } else {
                    label = String(format: "%.0f", value)
                }
                context.draw(
                    Text(label).font(Theme.mono(8)).foregroundColor(Theme.accentSecondary.opacity(0.7)),
                    at: CGPoint(x: 22, y: y),
                    anchor: .leading
                )
            } else {
                // Minor tick
                var tick = Path()
                tick.move(to: CGPoint(x: 6, y: y))
                tick.addLine(to: CGPoint(x: 12, y: y))
                context.stroke(tick, with: .color(Theme.accentSecondary.opacity(0.2)), lineWidth: 0.7)
            }

            value += minorInterval
        }
    }

    // MARK: - Trend vector

    private func drawTrendVector(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        guard history.count >= 3 else { return }
        let recent = Array(history.suffix(5))
        let trend = (recent.last ?? 0) - (recent.first ?? 0) // KB/s change

        // Draw trend line extending from pointer
        let trendLength: CGFloat = min(40, max(5, abs(trend) * 0.5))
        let trendY = trend > 0 ? pointerY - trendLength : pointerY + trendLength

        var trendLine = Path()
        trendLine.move(to: CGPoint(x: size.width - 16, y: pointerY))
        trendLine.addLine(to: CGPoint(x: size.width - 16, y: trendY))
        context.stroke(trendLine, with: .color(Theme.accentSecondary.opacity(0.5)), lineWidth: 1)

        // Arrow tip
        let arrowDir: CGFloat = trend > 0 ? -1 : 1
        var arrow = Path()
        arrow.move(to: CGPoint(x: size.width - 16, y: trendY))
        arrow.addLine(to: CGPoint(x: size.width - 19, y: trendY + 4 * arrowDir))
        arrow.addLine(to: CGPoint(x: size.width - 13, y: trendY + 4 * arrowDir))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(Theme.accentSecondary.opacity(0.5)))
    }

    // MARK: - Fixed pointer with digital readout

    private func drawPointer(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        // Pointer arrow on right edge
        var pointer = Path()
        pointer.move(to: CGPoint(x: size.width, y: pointerY))
        pointer.addLine(to: CGPoint(x: size.width - 10, y: pointerY - 8))
        pointer.addLine(to: CGPoint(x: size.width - 10, y: pointerY + 8))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(Theme.accentSecondary))

        // Digital readout box
        let boxWidth: CGFloat = size.width - 14
        let boxHeight: CGFloat = 18
        let boxRect = CGRect(x: 4, y: pointerY - boxHeight / 2, width: boxWidth, height: boxHeight)
        context.fill(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(Color(hex: 0x0a0a14)))
        context.stroke(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(Theme.accentSecondary), lineWidth: 1)

        let label: String
        if currentKB >= 1000 {
            label = String(format: "%.1f MB/s", currentKB / 1000)
        } else {
            label = String(format: "%.0f KB/s", currentKB)
        }
        context.draw(
            Text(label).font(Theme.mono(8, weight: .bold)).foregroundColor(Theme.accentSecondary),
            at: CGPoint(x: boxRect.midX, y: boxRect.midY),
            anchor: .center
        )
    }

    // MARK: - Bug markers (threshold indicators)

    private func drawBugMarkers(context: GraphicsContext, size: CGSize) {
        let pixelsPerKB = size.height / ceiling
        let pointerY = size.height / 2
        let currentOffset = currentKB * pixelsPerKB

        let thresholds: [(Double, String)] = [(1000, "1M"), (10000, "10M")]

        for (threshold, _) in thresholds {
            if threshold > ceiling { continue }
            let y = pointerY + currentOffset - threshold * pixelsPerKB

            if y < 0 || y > size.height { continue }

            // Small amber triangle on left edge
            var bug = Path()
            bug.move(to: CGPoint(x: 0, y: y))
            bug.addLine(to: CGPoint(x: 6, y: y - 4))
            bug.addLine(to: CGPoint(x: 6, y: y + 4))
            bug.closeSubpath()
            context.fill(bug, with: .color(Theme.warning))
        }
    }

    // MARK: - Label

    private func drawLabel(context: GraphicsContext, size: CGSize) {
        context.draw(
            Text("NET").font(Theme.mono(7, weight: .bold)).foregroundColor(Theme.accentSecondary.opacity(0.5)),
            at: CGPoint(x: size.width / 2, y: 8),
            anchor: .center
        )
    }
}
