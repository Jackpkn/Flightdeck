import SwiftUI

/// A horizontal row of 4 circular tachometer-style gauges for CPU, GPU, RAM,
/// and Disk I/O. Each draws a 270° arc with tick marks, a sweep needle, a
/// red danger zone, and a digital readout below.
struct EngineGaugesView: View {
    @Environment(ProcessMonitor.self) private var monitor
    let date: Date

    var body: some View {
        HStack(spacing: 20) {
            SingleGauge(
                label: "CPU",
                value: monitor.currentSystemCPU,
                maxValue: 100,
                unit: "%",
                color: Theme.accent,
                date: date
            )
            SingleGauge(
                label: "GPU",
                value: monitor.currentGPU.utilizationPercent,
                maxValue: 100,
                unit: "%",
                color: Theme.gpuColor,
                date: date
            )
            SingleGauge(
                label: "RAM",
                value: memoryPercent,
                maxValue: 100,
                unit: "%",
                color: Theme.copilotColor,
                date: date
            )
            SingleGauge(
                label: "DSK",
                value: min(diskNormalized, 100),
                maxValue: 100,
                unit: "%",
                color: Theme.warning,
                date: date
            )
        }
        .padding(.horizontal, 16)
    }

    private var memoryPercent: Double {
        guard let snap = monitor.memorySnapshot else { return 0 }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = Double(snap.usedBytes)
        return min(100, used / total * 100)
    }

    /// Disk I/O normalized: peak of recent history → 100%.
    private var diskNormalized: Double {
        let current = monitor.currentDiskKB
        let peak = max(1, monitor.diskHistory.max() ?? 1)
        return current / peak * 100
    }
}

// MARK: - Single Tachometer Gauge

private struct SingleGauge: View {
    let label: String
    let value: Double
    let maxValue: Double
    let unit: String
    let color: Color
    let date: Date

    /// Smoothed value for needle animation — avoids jumpy needle.
    @State private var displayValue: Double = 0

    private let startAngle: Double = 135 // degrees
    private let sweepAngle: Double = 270 // degrees
    private let majorTicks = 10
    private let minorTicksPerMajor = 5

    var body: some View {
        VStack(spacing: 6) {
            // Label
            Text(label)
                .font(Theme.mono(8, weight: .bold))
                .foregroundStyle(color.opacity(0.6))
                .tracking(1)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
                let radius = min(size.width, size.height) / 2 - 10

                drawTrackArc(context: context, center: center, radius: radius)
                drawDangerZone(context: context, center: center, radius: radius)
                drawTickMarks(context: context, center: center, radius: radius)
                drawNeedle(context: context, center: center, radius: radius)
                drawCenterHub(context: context, center: center)
                drawDigitalReadout(context: context, center: center, radius: radius)
            }
            .frame(width: 110, height: 110)
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                displayValue = newValue
            }
        }
        .onAppear {
            displayValue = value
        }
    }

    // MARK: - Track arc (background)

    private func drawTrackArc(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false
        )
        context.stroke(arc, with: .color(Theme.track), lineWidth: 4)
    }

    // MARK: - Danger zone (last 20%)

    private func drawDangerZone(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let dangerStart = startAngle + sweepAngle * 0.8
        let dangerEnd = startAngle + sweepAngle

        var dangerArc = Path()
        dangerArc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(dangerStart),
            endAngle: .degrees(dangerEnd),
            clockwise: false
        )
        context.stroke(dangerArc, with: .color(Theme.critical.opacity(0.35)), lineWidth: 5)
    }

    // MARK: - Tick marks

    private func drawTickMarks(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let totalMinorTicks = majorTicks * minorTicksPerMajor

        for i in 0...totalMinorTicks {
            let frac = Double(i) / Double(totalMinorTicks)
            let angle = (startAngle + sweepAngle * frac) * .pi / 180
            let isMajor = i % minorTicksPerMajor == 0

            let outerR = radius + 2
            let innerR = radius - (isMajor ? 8 : 4)

            var tick = Path()
            tick.move(to: CGPoint(x: center.x + innerR * cos(angle), y: center.y + innerR * sin(angle)))
            tick.addLine(to: CGPoint(x: center.x + outerR * cos(angle), y: center.y + outerR * sin(angle)))

            let tickColor = frac > 0.8 ? Theme.critical.opacity(isMajor ? 0.8 : 0.4) : color.opacity(isMajor ? 0.5 : 0.2)
            context.stroke(tick, with: .color(tickColor), lineWidth: isMajor ? 1.5 : 0.8)

            // Major tick number labels
            if isMajor {
                let labelR = radius - 14
                let labelValue = Int(maxValue * frac)
                context.draw(
                    Text("\(labelValue)").font(Theme.mono(6.5)).foregroundColor(Theme.ink3.opacity(0.6)),
                    at: CGPoint(x: center.x + labelR * cos(angle), y: center.y + labelR * sin(angle)),
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Needle

    private func drawNeedle(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let clampedValue = max(0, min(maxValue, displayValue))
        let frac = clampedValue / maxValue
        let angle = (startAngle + sweepAngle * frac) * .pi / 180

        let needleLength = radius - 6
        let tip = CGPoint(x: center.x + needleLength * cos(angle), y: center.y + needleLength * sin(angle))

        // Needle body (tapered)
        let perpAngle = angle + .pi / 2
        let baseWidth: CGFloat = 3
        let base1 = CGPoint(x: center.x + baseWidth * cos(perpAngle), y: center.y + baseWidth * sin(perpAngle))
        let base2 = CGPoint(x: center.x - baseWidth * cos(perpAngle), y: center.y - baseWidth * sin(perpAngle))

        var needle = Path()
        needle.move(to: tip)
        needle.addLine(to: base1)
        needle.addLine(to: base2)
        needle.closeSubpath()
        context.fill(needle, with: .color(frac > 0.8 ? Theme.critical : color))

        // Needle glow
        var glowLine = Path()
        glowLine.move(to: center)
        glowLine.addLine(to: tip)
        context.stroke(glowLine, with: .color((frac > 0.8 ? Theme.critical : color).opacity(0.3)), lineWidth: 1)
    }

    // MARK: - Center hub

    private func drawCenterHub(context: GraphicsContext, center: CGPoint) {
        let hubRect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: hubRect), with: .color(Theme.raised))
        context.stroke(Path(ellipseIn: hubRect), with: .color(color.opacity(0.6)), lineWidth: 1)
    }

    // MARK: - Digital readout

    private func drawDigitalReadout(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let readoutY = center.y + radius * 0.45

        let displayStr: String
        if unit == "%" {
            displayStr = String(format: "%.0f%@", displayValue, unit)
        } else {
            displayStr = String(format: "%.1f%@", displayValue, unit)
        }

        // Background box
        let boxWidth: CGFloat = 40
        let boxHeight: CGFloat = 14
        let boxRect = CGRect(x: center.x - boxWidth / 2, y: readoutY - boxHeight / 2, width: boxWidth, height: boxHeight)
        context.fill(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(Color(hex: 0x0a0a14)))
        context.stroke(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(color.opacity(0.3)), lineWidth: 0.5)

        context.draw(
            Text(displayStr).font(Theme.mono(9, weight: .bold)).foregroundColor(color),
            at: CGPoint(x: center.x, y: readoutY),
            anchor: .center
        )
    }
}
