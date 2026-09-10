import SwiftUI

/// Vertical scrolling altimeter-style tape showing memory pressure in GB.
/// Mirrors the SpeedTape on the left for symmetry. Features a barber-pole
/// ceiling at total physical RAM and swap-depth indicator.
struct AltitudeTapeView: View {
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(HardwareVitals.self) private var vitals
    let date: Date

    private var currentBytes: Double {
        monitor.memoryHistory.last ?? 0
    }
    private var currentGB: Double { currentBytes / 1_073_741_824 }
    private var history: [Double] { monitor.memoryHistory }

    /// Total physical RAM as ceiling.
    private var totalRAM: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// Swap in GB.
    private var swapGB: Double {
        Double(vitals.swap.usedBytes) / 1_073_741_824
    }

    var body: some View {
        Canvas { context, size in
            let pointerY = size.height / 2

            drawTapeBackground(context: context, size: size)
            drawBarberPole(context: context, size: size)
            drawTickMarks(context: context, size: size, pointerY: pointerY)
            drawSwapIndicator(context: context, size: size, pointerY: pointerY)
            drawTrendArrow(context: context, size: size, pointerY: pointerY)
            drawPointer(context: context, size: size, pointerY: pointerY)
            drawLabel(context: context, size: size)
        }
    }

    // MARK: - Background

    private func drawTapeBackground(context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(Color(hex: 0x060810).opacity(0.85)))

        // Right border line
        var rightBorder = Path()
        rightBorder.move(to: CGPoint(x: size.width - 1, y: 0))
        rightBorder.addLine(to: CGPoint(x: size.width - 1, y: size.height))
        context.stroke(rightBorder, with: .color(Theme.copilotColor.opacity(0.4)), lineWidth: 1)
    }

    // MARK: - Barber pole (RAM ceiling)

    private func drawBarberPole(context: GraphicsContext, size: CGSize) {
        let pixelsPerGB = size.height / max(1, totalRAM * 1.2)
        let pointerY = size.height / 2
        let ceilingY = pointerY + currentGB * pixelsPerGB - totalRAM * pixelsPerGB

        if ceilingY > 0 {
            // Draw red/white striped band above ceiling
            let stripeHeight: CGFloat = 3
            var y = max(0, ceilingY - 30)
            while y < ceilingY {
                let isRed = Int((y / stripeHeight).rounded()) % 2 == 0
                let stripeRect = CGRect(x: 0, y: y, width: size.width, height: stripeHeight)
                context.fill(
                    Path(stripeRect),
                    with: .color(isRed ? Theme.critical.opacity(0.3) : Color.white.opacity(0.08))
                )
                y += stripeHeight
            }

            // Ceiling line
            var ceilingLine = Path()
            ceilingLine.move(to: CGPoint(x: 0, y: ceilingY))
            ceilingLine.addLine(to: CGPoint(x: size.width, y: ceilingY))
            context.stroke(ceilingLine, with: .color(Theme.critical.opacity(0.7)), lineWidth: 1)

            context.draw(
                Text("MAX").font(Theme.mono(6, weight: .bold)).foregroundColor(Theme.critical.opacity(0.7)),
                at: CGPoint(x: size.width / 2, y: ceilingY - 4),
                anchor: .center
            )
        }
    }

    // MARK: - Tick marks

    private func drawTickMarks(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        let displayCeiling = totalRAM * 1.2
        let pixelsPerGB = size.height / max(1, displayCeiling)
        let currentOffset = currentGB * pixelsPerGB

        let majorInterval: Double = totalRAM > 16 ? 4.0 : (totalRAM > 8 ? 2.0 : 1.0)
        let minorInterval = majorInterval / 4

        var value: Double = 0
        while value <= displayCeiling * 2 {
            let y = pointerY + currentOffset - value * pixelsPerGB

            if y < -20 || y > size.height + 20 {
                value += minorInterval
                continue
            }

            let isMajor = value.truncatingRemainder(dividingBy: majorInterval) < 0.01

            if isMajor {
                var tick = Path()
                tick.move(to: CGPoint(x: size.width - 4, y: y))
                tick.addLine(to: CGPoint(x: size.width - 18, y: y))
                context.stroke(tick, with: .color(Theme.copilotColor.opacity(0.6)), lineWidth: 1)

                context.draw(
                    Text(String(format: "%.0fG", value)).font(Theme.mono(8)).foregroundColor(Theme.copilotColor.opacity(0.7)),
                    at: CGPoint(x: size.width - 22, y: y),
                    anchor: .trailing
                )
            } else {
                var tick = Path()
                tick.move(to: CGPoint(x: size.width - 6, y: y))
                tick.addLine(to: CGPoint(x: size.width - 12, y: y))
                context.stroke(tick, with: .color(Theme.copilotColor.opacity(0.2)), lineWidth: 0.7)
            }

            value += minorInterval
        }
    }

    // MARK: - Swap indicator

    private func drawSwapIndicator(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        guard swapGB > 0.01 else { return }

        let displayCeiling = totalRAM * 1.2
        let pixelsPerGB = size.height / max(1, displayCeiling)
        let swapPixels = swapGB * pixelsPerGB

        // Amber band below pointer showing swap depth
        let swapRect = CGRect(x: 0, y: pointerY + 2, width: 6, height: min(swapPixels, size.height - pointerY - 4))
        context.fill(Path(swapRect), with: .color(Theme.warning.opacity(0.4)))

        context.draw(
            Text("SWAP").font(Theme.mono(6, weight: .bold)).foregroundColor(Theme.warning.opacity(0.7)),
            at: CGPoint(x: 10, y: pointerY + swapPixels / 2 + 2),
            anchor: .leading
        )
    }

    // MARK: - Trend arrow

    private func drawTrendArrow(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        guard history.count >= 3 else { return }
        let recent = Array(history.suffix(5))
        let trendBytes = (recent.last ?? 0) - (recent.first ?? 0)
        let trendGB = trendBytes / 1_073_741_824

        let trendLength: CGFloat = min(30, max(3, abs(trendGB) * 20))
        let trendY = trendGB > 0 ? pointerY - trendLength : pointerY + trendLength

        var trendLine = Path()
        trendLine.move(to: CGPoint(x: 16, y: pointerY))
        trendLine.addLine(to: CGPoint(x: 16, y: trendY))
        context.stroke(trendLine, with: .color(Theme.copilotColor.opacity(0.4)), lineWidth: 1)

        let arrowDir: CGFloat = trendGB > 0 ? -1 : 1
        var arrow = Path()
        arrow.move(to: CGPoint(x: 16, y: trendY))
        arrow.addLine(to: CGPoint(x: 13, y: trendY + 4 * arrowDir))
        arrow.addLine(to: CGPoint(x: 19, y: trendY + 4 * arrowDir))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(Theme.copilotColor.opacity(0.4)))
    }

    // MARK: - Pointer + digital readout

    private func drawPointer(context: GraphicsContext, size: CGSize, pointerY: CGFloat) {
        // Pointer arrow on left edge
        var pointer = Path()
        pointer.move(to: CGPoint(x: 0, y: pointerY))
        pointer.addLine(to: CGPoint(x: 10, y: pointerY - 8))
        pointer.addLine(to: CGPoint(x: 10, y: pointerY + 8))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(Theme.copilotColor))

        // Digital readout box
        let boxWidth: CGFloat = size.width - 14
        let boxHeight: CGFloat = 18
        let boxRect = CGRect(x: 10, y: pointerY - boxHeight / 2, width: boxWidth, height: boxHeight)
        context.fill(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(Color(hex: 0x0a0a14)))
        context.stroke(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(Theme.copilotColor), lineWidth: 1)

        context.draw(
            Text(String(format: "%.1f GB", currentGB)).font(Theme.mono(8, weight: .bold)).foregroundColor(Theme.copilotColor),
            at: CGPoint(x: boxRect.midX, y: boxRect.midY),
            anchor: .center
        )
    }

    // MARK: - Label

    private func drawLabel(context: GraphicsContext, size: CGSize) {
        context.draw(
            Text("MEM").font(Theme.mono(7, weight: .bold)).foregroundColor(Theme.copilotColor.opacity(0.5)),
            at: CGPoint(x: size.width / 2, y: 8),
            anchor: .center
        )
    }
}
