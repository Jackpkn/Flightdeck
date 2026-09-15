import SwiftUI

// MARK: - 1. Emerald Energy Orb (Dev Cruft)

/// 3D glossy emerald orb with orbiting data debris particles and radiant glow rings.
struct EmeraldOrbArt: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        let elapsed = date.timeIntervalSinceReferenceDate

        // Outer Ambient Glow
        let glowRect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x10b981).opacity(0.35), Color(hex: 0x10b981).opacity(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: radius * 1.5
            )
        )

        // Orbiting Ring (Tilted ellipse)
        var ringPath = Path()
        let ringRx = radius * 1.35
        let ringRy = radius * 0.55
        let ringAngle: Angle = .degrees(-25)

        var ringTransform = CGAffineTransform.identity
        ringTransform = ringTransform.translatedBy(x: center.x, y: center.y)
        ringTransform = ringTransform.rotated(by: CGFloat(ringAngle.radians))
        ringTransform = ringTransform.translatedBy(x: -center.x, y: -center.y)

        let unrotatedRing = Path(ellipseIn: CGRect(x: center.x - ringRx, y: center.y - ringRy, width: ringRx * 2, height: ringRy * 2))
        ringPath.addPath(unrotatedRing, transform: ringTransform)
        context.stroke(ringPath, with: .color(Color(hex: 0x34d399).opacity(0.4)), lineWidth: 1.5)

        // Orbiting Particles
        let particleCount = 4
        for i in 0..<particleCount {
            let pAngle = elapsed * 1.8 + Double(i) * (.pi * 2 / Double(particleCount))
            let px = ringRx * CGFloat(cos(pAngle))
            let py = ringRy * CGFloat(sin(pAngle))
            let cosA = CGFloat(cos(ringAngle.radians))
            let sinA = CGFloat(sin(ringAngle.radians))
            let rotatedPx = px * cosA - py * sinA
            let rotatedPy = px * sinA + py * cosA
            let pt = CGPoint(x: center.x + rotatedPx, y: center.y + rotatedPy)

            let pSize: CGFloat = (sin(pAngle) > 0) ? 4.5 : 3.0
            let pGlow = CGRect(x: pt.x - pSize, y: pt.y - pSize, width: pSize * 2, height: pSize * 2)
            context.fill(Path(ellipseIn: pGlow), with: .color(Color(hex: 0x6ee7b7)))
        }

        // 3D Spherical Body
        let orbRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: orbRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0x34d399),
                    Color(hex: 0x059669),
                    Color(hex: 0x064e3b),
                    Color(hex: 0x022c22)
                ]),
                center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
                startRadius: 2,
                endRadius: radius * 1.8
            )
        )

        // Specular Highlight
        let highlightRect = CGRect(
            x: center.x - radius * 0.55,
            y: center.y - radius * 0.55,
            width: radius * 0.65,
            height: radius * 0.4
        )
        context.fill(
            Path(ellipseIn: highlightRect),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)]),
                center: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                startRadius: 1,
                endRadius: radius * 0.35
            )
        )
    }
}

// MARK: - 2. Crimson Threat Reticle (Threat Defense)

/// 3D glossy magenta/crimson shield with rotating targeting crosshair and locking brackets.
struct CrimsonReticleArt: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        let elapsed = date.timeIntervalSinceReferenceDate

        // Outer Ambient Glow
        let glowRect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xf43f5e).opacity(0.35), Color(hex: 0xf43f5e).opacity(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: radius * 1.5
            )
        )

        // 3D Hexagonal / Rounded Shield Plate
        var shield = Path()
        let corners = 6
        for i in 0..<corners {
            let angle = Double(i) * (.pi / 3.0) - .pi / 6.0
            let pt = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            if i == 0 { shield.move(to: pt) } else { shield.addLine(to: pt) }
        }
        shield.closeSubpath()

        context.fill(
            shield,
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0xfb7185),
                    Color(hex: 0xe11d48),
                    Color(hex: 0x881337),
                    Color(hex: 0x4c0519)
                ]),
                center: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.3),
                startRadius: 2,
                endRadius: radius * 1.7
            )
        )
        context.stroke(shield, with: .color(Color(hex: 0xffa4b3).opacity(0.6)), lineWidth: 1.5)

        // Rotating Reticle Crosshair
        let reticleAngle = elapsed * 1.2
        var reticleCtx = context
        reticleCtx.translateBy(x: center.x, y: center.y)
        reticleCtx.rotate(by: .radians(reticleAngle))
        reticleCtx.translateBy(x: -center.x, y: -center.y)

        let rSize = radius * 0.55
        let rCircle = CGRect(x: center.x - rSize, y: center.y - rSize, width: rSize * 2, height: rSize * 2)
        reticleCtx.stroke(
            Path(ellipseIn: rCircle),
            with: .color(Color.white.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
        )

        // 4 Reticle Ticks
        for i in 0..<4 {
            let a = Double(i) * (.pi / 2.0)
            let cosA = CGFloat(cos(a))
            let sinA = CGFloat(sin(a))
            var tick = Path()
            tick.move(to: CGPoint(x: center.x + (rSize - 4) * cosA, y: center.y + (rSize - 4) * sinA))
            tick.addLine(to: CGPoint(x: center.x + (rSize + 6) * cosA, y: center.y + (rSize + 6) * sinA))
            reticleCtx.stroke(tick, with: .color(Color.white), lineWidth: 2)
        }

        // Pulsing Warning Center Dot
        let pulse = (sin(elapsed * 4.0) + 1.0) / 2.0
        let dotRadius: CGFloat = 3.0 + CGFloat(pulse) * 2.0
        let dotRect = CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(Color.white))
    }
}

// MARK: - 3. Amber Performance Gauge (RAM & CPU Tuning)

/// 3D glossy amber badge with rotating swept tachometer arc and electrical sparks.
struct AmberPerformanceArt: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        let elapsed = date.timeIntervalSinceReferenceDate

        // Ambient Glow
        let glowRect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xf59e0b).opacity(0.35), Color(hex: 0xf59e0b).opacity(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: radius * 1.5
            )
        )

        // 3D Glass Badge
        let badgeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let badgePath = Path(roundedRect: badgeRect, cornerRadius: radius * 0.4)
        context.fill(
            badgePath,
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0xfcd34d),
                    Color(hex: 0xd97706),
                    Color(hex: 0x92400e),
                    Color(hex: 0x451a03)
                ]),
                center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.3),
                startRadius: 2,
                endRadius: radius * 1.7
            )
        )
        context.stroke(badgePath, with: .color(Color(hex: 0xfde68a).opacity(0.6)), lineWidth: 1.5)

        // Tachometer Arc Track
        let trackRadius = radius * 0.65
        var track = Path()
        track.addArc(
            center: center,
            radius: trackRadius,
            startAngle: .degrees(135),
            endAngle: .degrees(405),
            clockwise: false
        )
        context.stroke(track, with: .color(Color.black.opacity(0.35)), lineWidth: 4)

        // Swept Meter Arc (Animated)
        let sweepPercent = 0.5 + sin(elapsed * 2.0) * 0.3
        let sweepEnd = 135.0 + sweepPercent * 270.0
        var meter = Path()
        meter.addArc(
            center: center,
            radius: trackRadius,
            startAngle: .degrees(135),
            endAngle: .degrees(sweepEnd),
            clockwise: false
        )
        context.stroke(
            meter,
            with: .color(Color.white),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )

        // Lightning Bolt in center
        var bolt = Path()
        bolt.move(to: CGPoint(x: center.x + 2, y: center.y - radius * 0.4))
        bolt.addLine(to: CGPoint(x: center.x - radius * 0.25, y: center.y))
        bolt.addLine(to: CGPoint(x: center.x - 2, y: center.y + 2))
        bolt.addLine(to: CGPoint(x: center.x - radius * 0.1, y: center.y + radius * 0.4))
        bolt.addLine(to: CGPoint(x: center.x + radius * 0.25, y: center.y - 2))
        bolt.addLine(to: CGPoint(x: center.x + 2, y: center.y - 4))
        bolt.closeSubpath()
        context.fill(bolt, with: .color(Color.white.opacity(0.9)))
    }
}

// MARK: - 4. Violet Radio Rings (Port Perimeter)

/// 3D glossy violet badge with outward pulsing radar broadcast waves.
struct VioletRadioArt: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        let elapsed = date.timeIntervalSinceReferenceDate

        // Ambient Glow
        let glowRect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x8b5cf6).opacity(0.35), Color(hex: 0x8b5cf6).opacity(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: radius * 1.5
            )
        )

        // 3D Diamond / Shield
        var diamond = Path()
        diamond.move(to: CGPoint(x: center.x, y: center.y - radius))
        diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y + radius))
        diamond.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        diamond.closeSubpath()

        context.fill(
            diamond,
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0xc4b5fd),
                    Color(hex: 0x7c3aed),
                    Color(hex: 0x4c1d95),
                    Color(hex: 0x2e1065)
                ]),
                center: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.3),
                startRadius: 2,
                endRadius: radius * 1.7
            )
        )
        context.stroke(diamond, with: .color(Color(hex: 0xddd6fe).opacity(0.6)), lineWidth: 1.5)

        // Expanding Radio Wave Pulses
        let waveCount = 3
        for i in 0..<waveCount {
            let phase = (elapsed * 1.5 + Double(i) / Double(waveCount)).truncatingRemainder(dividingBy: 1.0)
            let waveR = radius * 0.2 + radius * 0.6 * CGFloat(phase)
            let waveRect = CGRect(x: center.x - waveR, y: center.y - waveR, width: waveR * 2, height: waveR * 2)
            let opacity = max(0, 1.0 - phase)

            context.stroke(
                Path(ellipseIn: waveRect),
                with: .color(Color.white.opacity(opacity * 0.7)),
                lineWidth: 1.5
            )
        }

        // Center Transmitter Beacon
        let beaconRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: beaconRect), with: .color(Color.white))
    }
}

// MARK: - 5. Teal Laser Vault (Workspace Clutter)

/// 3D glossy teal folder/vault with an animated vertical cyan laser scan line.
struct TealVaultArt: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        let elapsed = date.timeIntervalSinceReferenceDate

        // Ambient Glow
        let glowRect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x06b6d4).opacity(0.35), Color(hex: 0x06b6d4).opacity(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: radius * 1.5
            )
        )

        // 3D Folder / Box Path
        let w = radius * 1.8
        let h = radius * 1.4
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let folderPath = Path(roundedRect: rect, cornerRadius: 8)

        context.fill(
            folderPath,
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0x67e8f9),
                    Color(hex: 0x0891b2),
                    Color(hex: 0x164e63),
                    Color(hex: 0x083344)
                ]),
                center: CGPoint(x: center.x - w * 0.25, y: center.y - h * 0.25),
                startRadius: 2,
                endRadius: radius * 1.6
            )
        )
        context.stroke(folderPath, with: .color(Color(hex: 0xa5f3fc).opacity(0.6)), lineWidth: 1.5)

        // Vertical Scanning Laser Beam
        let scanCycle = (sin(elapsed * 2.8) + 1.0) / 2.0 // 0.0 to 1.0
        let scanY = rect.minY + CGFloat(scanCycle) * rect.height

        // Laser line
        var laser = Path()
        laser.move(to: CGPoint(x: rect.minX + 4, y: scanY))
        laser.addLine(to: CGPoint(x: rect.maxX - 4, y: scanY))
        context.stroke(laser, with: .color(Color.white), lineWidth: 2)

        // Laser glow band
        let laserGlow = CGRect(x: rect.minX + 4, y: scanY - 5, width: rect.width - 8, height: 10)
        context.fill(
            Path(laserGlow),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x67e8f9).opacity(0.6), Color(hex: 0x67e8f9).opacity(0)]),
                center: CGPoint(x: laserGlow.midX, y: laserGlow.midY),
                startRadius: 1,
                endRadius: 6
            )
        )
    }
}
