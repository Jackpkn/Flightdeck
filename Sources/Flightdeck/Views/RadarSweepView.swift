import SwiftUI

/// Rotating radar scope — plots zombie orphan processes and active ports
/// as bogeys on a PPI (Plan Position Indicator) display. The sweep arm
/// rotates once every ~4 seconds, leaving a gradient trail.
struct RadarSweepView: View {
    @Environment(ZombieDetector.self) private var zombies
    @Environment(PortScanner.self) private var ports
    let date: Date

    /// Seconds for one full revolution.
    private let period: Double = 4.0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 12

            drawBackground(context: context, center: center, radius: radius, size: size)
            drawRangeRings(context: context, center: center, radius: radius)
            drawCrosshairs(context: context, center: center, radius: radius)
            drawSweepArm(context: context, center: center, radius: radius)
            drawBogeys(context: context, center: center, radius: radius)
            drawCenterReadout(context: context, center: center, size: size)
        }
    }

    // MARK: - Sweep angle

    private var sweepAngle: Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return (elapsed.truncatingRemainder(dividingBy: period) / period) * 2 * .pi
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, center: CGPoint, radius: CGFloat, size: CGSize) {
        let outerRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: outerRect), with: .color(Color(hex: 0x060810).opacity(0.9)))
        context.stroke(Path(ellipseIn: outerRect), with: .color(Theme.accent.opacity(0.35)), lineWidth: 1.5)
    }

    // MARK: - Range rings

    private func drawRangeRings(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let ringFractions: [Double] = [0.33, 0.66, 1.0]
        let labels = ["64MB", "256MB", "1GB"]

        for (i, frac) in ringFractions.enumerated() {
            let r = radius * frac
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let dashStyle = StrokeStyle(lineWidth: 0.7, dash: [4, 6])
            context.stroke(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.18)), style: dashStyle)

            let labelAngle = -Double.pi / 4
            let labelPoint = CGPoint(
                x: center.x + r * cos(labelAngle) + 4,
                y: center.y + r * sin(labelAngle) - 6
            )
            context.draw(
                Text(labels[i]).font(Theme.mono(7.5)).foregroundColor(Theme.accent.opacity(0.45)),
                at: labelPoint,
                anchor: .leading
            )
        }
    }

    // MARK: - Crosshairs

    private func drawCrosshairs(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var hPath = Path()
        hPath.move(to: CGPoint(x: center.x - radius, y: center.y))
        hPath.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        context.stroke(hPath, with: .color(Theme.accent.opacity(0.1)), lineWidth: 0.6)

        var vPath = Path()
        vPath.move(to: CGPoint(x: center.x, y: center.y - radius))
        vPath.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        context.stroke(vPath, with: .color(Theme.accent.opacity(0.1)), lineWidth: 0.6)

        for spoke in stride(from: Double.pi / 4, to: 2 * .pi, by: Double.pi / 4) {
            var p = Path()
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + radius * cos(spoke), y: center.y + radius * sin(spoke)))
            context.stroke(p, with: .color(Theme.accent.opacity(0.06)), lineWidth: 0.5)
        }
    }

    // MARK: - Sweep arm with gradient trail

    private func drawSweepArm(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let angle = sweepAngle - .pi / 2

        let trailSpan = Double.pi / 2
        let segments = 30
        for i in 0..<segments {
            let frac = Double(i) / Double(segments)
            let segAngle = angle - trailSpan * (1 - frac)
            let nextAngle = angle - trailSpan * (1 - Double(i + 1) / Double(segments))
            let opacity = frac * frac * 0.15

            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius, startAngle: .radians(segAngle), endAngle: .radians(nextAngle), clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(Theme.accent.opacity(opacity)))
        }

        let tip = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        var line = Path()
        line.move(to: center)
        line.addLine(to: tip)
        context.stroke(line, with: .color(Theme.accent.opacity(0.9)), lineWidth: 1.5)

        let glowRect = CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: glowRect), with: .color(Theme.accent))

        let glowBig = CGRect(x: tip.x - 8, y: tip.y - 8, width: 16, height: 16)
        context.fill(Path(ellipseIn: glowBig), with: .color(Theme.accent.opacity(0.25)))
    }

    // MARK: - Bogeys (zombies + ports)

    private func drawBogeys(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let sweep = sweepAngle - .pi / 2

        for orphan in zombies.orphans {
            let memMB = max(1, Double(orphan.memoryBytes) / 1_048_576)
            let normalizedDist = min(1.0, log2(memMB) / log2(1024))
            let dist = radius * 0.15 + radius * 0.8 * normalizedDist

            let angle = Double(abs(orphan.pid.hashValue)) / Double(Int.max) * 2 * .pi - .pi / 2

            let angleDiff = normalizeAngle(sweep - angle)
            let visibility = angleDiff >= 0 && angleDiff < .pi * 1.5 ? max(0, 1.0 - angleDiff / (.pi * 1.5)) : 0

            if visibility > 0.05 {
                let pt = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
                let dotSize: CGFloat = orphan.isZombie ? 7 : 5

                let glowRect = CGRect(x: pt.x - dotSize, y: pt.y - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Path(ellipseIn: glowRect), with: .color(Theme.critical.opacity(0.3 * visibility)))

                let coreRect = CGRect(x: pt.x - dotSize / 2, y: pt.y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: coreRect), with: .color(Theme.critical.opacity(0.9 * visibility)))
            }
        }

        let devPorts = ports.ports.filter { $0.isDevPort }
        for port in devPorts {
            let normalizedDist = 0.2 + 0.7 * min(1.0, Double(port.port) / 49152.0)
            let dist = radius * normalizedDist

            let angle = Double(port.port.hashValue & 0xFFFF) / Double(0xFFFF) * 2 * .pi - .pi / 2

            let angleDiff = normalizeAngle(sweep - angle)
            let visibility = angleDiff >= 0 && angleDiff < .pi * 1.5 ? max(0, 1.0 - angleDiff / (.pi * 1.5)) : 0

            if visibility > 0.05 {
                let pt = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
                let dotSize: CGFloat = 4

                let glowRect = CGRect(x: pt.x - dotSize, y: pt.y - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Path(ellipseIn: glowRect), with: .color(Theme.good.opacity(0.25 * visibility)))

                let coreRect = CGRect(x: pt.x - dotSize / 2, y: pt.y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: coreRect), with: .color(Theme.good.opacity(0.85 * visibility)))
            }
        }
    }

    // MARK: - Center readout

    private func drawCenterReadout(context: GraphicsContext, center: CGPoint, size: CGSize) {
        let count = zombies.orphans.count
        let wastedMB = zombies.totalWastedBytes / 1_048_576

        let topText = count > 0 ? "\(count) ORPHAN\(count == 1 ? "" : "S")" : "CLEAR"
        let bottomText = count > 0 ? "\(wastedMB) MB" : "NO THREATS"

        context.draw(
            Text(topText)
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundColor(count > 0 ? Theme.critical : Theme.good),
            at: CGPoint(x: center.x, y: center.y - 6),
            anchor: .center
        )
        context.draw(
            Text(bottomText)
                .font(Theme.mono(7.5))
                .foregroundColor(count > 0 ? Theme.critical.opacity(0.7) : Theme.good.opacity(0.6)),
            at: CGPoint(x: center.x, y: center.y + 6),
            anchor: .center
        )

        let portCount = ports.ports.filter(\.isDevPort).count
        context.draw(
            Text("\(portCount) PORT\(portCount == 1 ? "" : "S") ACTIVE")
                .font(Theme.mono(7))
                .foregroundColor(Theme.accent.opacity(0.5)),
            at: CGPoint(x: center.x, y: center.y + 18),
            anchor: .center
        )
    }

    // MARK: - Helpers

    private func normalizeAngle(_ a: Double) -> Double {
        var result = a.truncatingRemainder(dividingBy: 2 * .pi)
        if result < 0 { result += 2 * .pi }
        return result
    }
}
