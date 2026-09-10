import SwiftUI

/// Classic avionics attitude indicator — sky/ground split that tilts based
/// on CPU vs GPU load ratio, with pitch ladder shifting by total system load.
struct ArtificialHorizonView: View {
    @Environment(ProcessMonitor.self) private var monitor
    let date: Date

    private var cpuLoad: Double { monitor.cpuHistory.last ?? 0 }
    private var gpuLoad: Double { monitor.currentGPU.utilizationPercent }
    private var totalLoad: Double { min(100, (cpuLoad + gpuLoad) / 2) }

    /// Bank angle: -30° to +30° based on CPU/GPU imbalance.
    private var bankAngle: Double {
        let diff = cpuLoad - gpuLoad // Positive = CPU dominant
        return max(-30, min(30, diff * 0.3))
    }

    /// Pitch offset: 0% load = centered, 100% = pitched down.
    private var pitchOffset: Double {
        totalLoad / 100.0 * 40 // Max 40pt shift
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8

            // Clip sky and ground to circular instrument face
            let clipRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let clipPath = Path(ellipseIn: clipRect)

            var clipped = context
            clipped.clip(to: clipPath)
            clipped.translateBy(x: center.x, y: center.y)
            clipped.rotate(by: .degrees(bankAngle))
            clipped.translateBy(x: -center.x, y: -center.y)

            drawSkyGround(context: clipped, center: center, radius: radius)
            drawPitchLadder(context: clipped, center: center, radius: radius)

            // Non-rotated overlay elements
            drawBankIndicator(context: context, center: center, radius: radius)
            drawAircraftSymbol(context: context, center: center)
            drawReadouts(context: context, center: center, radius: radius)
            drawOuterRing(context: context, center: center, radius: radius)
        }
    }

    // MARK: - Sky & Ground

    private func drawSkyGround(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let horizonY = center.y + pitchOffset

        // Sky — dark blue gradient
        let skyRect = CGRect(x: center.x - radius * 2, y: horizonY - radius * 4, width: radius * 4, height: radius * 4)
        context.fill(Path(skyRect), with: .color(Color(hex: 0x0a1628)))

        // Ground — dark brown gradient
        let groundRect = CGRect(x: center.x - radius * 2, y: horizonY, width: radius * 4, height: radius * 4)
        context.fill(Path(groundRect), with: .color(Color(hex: 0x1a0e08)))

        // Horizon line — bright
        var horizonLine = Path()
        horizonLine.move(to: CGPoint(x: center.x - radius * 2, y: horizonY))
        horizonLine.addLine(to: CGPoint(x: center.x + radius * 2, y: horizonY))
        context.stroke(horizonLine, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
    }

    // MARK: - Pitch Ladder

    private func drawPitchLadder(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let horizonY = center.y + pitchOffset
        let pitchAngles: [Int] = [-20, -10, 10, 20]
        let pixelsPerDegree: CGFloat = 3.0

        for deg in pitchAngles {
            let y = horizonY - CGFloat(deg) * pixelsPerDegree
            let halfWidth: CGFloat = deg > 0 ? 30 : 25

            var line = Path()
            line.move(to: CGPoint(x: center.x - halfWidth, y: y))
            line.addLine(to: CGPoint(x: center.x + halfWidth, y: y))
            let dashStyle = StrokeStyle(lineWidth: 0.8, dash: deg < 0 ? [4, 4] : [])
            context.stroke(line, with: .color(Color.white.opacity(0.5)), style: dashStyle)

            // Degree labels
            context.draw(
                Text("\(abs(deg))").font(Theme.mono(7)).foregroundColor(Color.white.opacity(0.45)),
                at: CGPoint(x: center.x - halfWidth - 12, y: y),
                anchor: .center
            )
            context.draw(
                Text("\(abs(deg))").font(Theme.mono(7)).foregroundColor(Color.white.opacity(0.45)),
                at: CGPoint(x: center.x + halfWidth + 12, y: y),
                anchor: .center
            )
        }
    }

    // MARK: - Bank Indicator Arc

    private func drawBankIndicator(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let arcRadius = radius - 6
        let tickAngles: [Double] = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]

        for deg in tickAngles {
            let angle = (.pi / 2 + deg * .pi / 180) * -1 + .pi / 2
            let isMajor = abs(deg).truncatingRemainder(dividingBy: 30) == 0
            let outerR = arcRadius
            let innerR = arcRadius - (isMajor ? 8 : 4)

            var tick = Path()
            tick.move(to: CGPoint(x: center.x + innerR * cos(angle - .pi / 2), y: center.y + innerR * sin(angle - .pi / 2)))
            tick.addLine(to: CGPoint(x: center.x + outerR * cos(angle - .pi / 2), y: center.y + outerR * sin(angle - .pi / 2)))
            context.stroke(tick, with: .color(Color.white.opacity(isMajor ? 0.6 : 0.3)), lineWidth: isMajor ? 1.5 : 1)
        }

        // Moving triangle at current bank angle
        let triangleAngle = -(.pi / 2) + bankAngle * .pi / 180
        let triTip = CGPoint(x: center.x + (arcRadius - 10) * cos(triangleAngle), y: center.y + (arcRadius - 10) * sin(triangleAngle))
        let triBase1 = CGPoint(x: center.x + (arcRadius - 2) * cos(triangleAngle - 0.04), y: center.y + (arcRadius - 2) * sin(triangleAngle - 0.04))
        let triBase2 = CGPoint(x: center.x + (arcRadius - 2) * cos(triangleAngle + 0.04), y: center.y + (arcRadius - 2) * sin(triangleAngle + 0.04))

        var tri = Path()
        tri.move(to: triTip)
        tri.addLine(to: triBase1)
        tri.addLine(to: triBase2)
        tri.closeSubpath()
        context.fill(tri, with: .color(Theme.accent))
    }

    // MARK: - Aircraft Symbol (fixed center reticle)

    private func drawAircraftSymbol(context: GraphicsContext, center: CGPoint) {
        // Left wing
        var leftWing = Path()
        leftWing.move(to: CGPoint(x: center.x - 50, y: center.y))
        leftWing.addLine(to: CGPoint(x: center.x - 18, y: center.y))
        leftWing.addLine(to: CGPoint(x: center.x - 18, y: center.y + 6))
        context.stroke(leftWing, with: .color(Theme.accent), lineWidth: 2)

        // Right wing
        var rightWing = Path()
        rightWing.move(to: CGPoint(x: center.x + 50, y: center.y))
        rightWing.addLine(to: CGPoint(x: center.x + 18, y: center.y))
        rightWing.addLine(to: CGPoint(x: center.x + 18, y: center.y + 6))
        context.stroke(rightWing, with: .color(Theme.accent), lineWidth: 2)

        // Center dot
        let dotRect = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: dotRect), with: .color(Theme.accent))
    }

    // MARK: - Digital Readouts

    private func drawReadouts(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // CPU readout — left
        context.draw(
            Text("CPU").font(Theme.mono(7, weight: .bold)).foregroundColor(Theme.accent.opacity(0.6)),
            at: CGPoint(x: center.x - radius + 20, y: center.y + radius - 30),
            anchor: .leading
        )
        context.draw(
            Text(String(format: "%.0f%%", cpuLoad)).font(Theme.mono(11, weight: .bold)).foregroundColor(Theme.accent),
            at: CGPoint(x: center.x - radius + 20, y: center.y + radius - 18),
            anchor: .leading
        )

        // GPU readout — right
        context.draw(
            Text("GPU").font(Theme.mono(7, weight: .bold)).foregroundColor(Theme.gpuColor.opacity(0.6)),
            at: CGPoint(x: center.x + radius - 20, y: center.y + radius - 30),
            anchor: .trailing
        )
        context.draw(
            Text(String(format: "%.0f%%", gpuLoad)).font(Theme.mono(11, weight: .bold)).foregroundColor(Theme.gpuColor),
            at: CGPoint(x: center.x + radius - 20, y: center.y + radius - 18),
            anchor: .trailing
        )
    }

    // MARK: - Outer Ring

    private func drawOuterRing(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let outerRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: outerRect), with: .color(Theme.ink3.opacity(0.5)), lineWidth: 2)

        // Thin inner ring
        let innerR = radius - 3
        let innerRect = CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)
        context.stroke(Path(ellipseIn: innerRect), with: .color(Theme.ink3.opacity(0.15)), lineWidth: 0.5)
    }
}
