import SwiftUI
import AppKit
import QuartzCore

/// The real thing the earlier Canvas-based fountain was standing in for: an
/// actual CAEmitterLayer particle burst, GPU-composited on Core Animation's
/// own render server — not simulated per-frame in a SwiftUI Canvas. One
/// throwaway emitter layer is spawned per cost event and removed once its
/// particles finish fading, so nothing accumulates.
struct EmitterTrailOverlay: NSViewRepresentable {
    let particles: [FountainParticle]
    var color: Color = Theme.accent

    func makeNSView(context: Context) -> EmitterHostView {
        EmitterHostView(frame: .zero)
    }

    func updateNSView(_ nsView: EmitterHostView, context: Context) {
        nsView.sync(particles: particles, color: NSColor(color))
    }
}

final class EmitterHostView: NSView {
    private var firedIds: Set<UUID> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    /// This view draws particle trails over the whole dashboard but must never
    /// steal a click meant for a button underneath it — always pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func sync(particles: [FountainParticle], color: NSColor) {
        for p in particles where !firedIds.contains(p.id) {
            firedIds.insert(p.id)
            fire(p, color: color)
        }
        if firedIds.count > 300 {
            firedIds.subtract(firedIds.subtracting(particles.map(\.id)))
        }
    }

    private func fire(_ particle: FountainParticle, color: NSColor) {
        guard let hostLayer = layer else { return }

        let cell = CAEmitterCell()
        cell.contents = Self.sparkImage
        cell.lifetime = 0.4
        cell.lifetimeRange = 0.15
        cell.velocity = 24
        cell.velocityRange = 16
        cell.emissionRange = .pi * 2
        cell.scale = 0.22
        cell.scaleRange = 0.12
        cell.alphaSpeed = -2.2
        cell.color = color.cgColor
        cell.birthRate = 160

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.emitterSize = .zero
        emitter.emitterCells = [cell]
        emitter.frame = bounds
        emitter.emitterPosition = particle.start
        hostLayer.addSublayer(emitter)

        let path = CGMutablePath()
        path.move(to: particle.start)
        let mid = CGPoint(x: (particle.start.x + particle.end.x) / 2, y: min(particle.start.y, particle.end.y) - 30)
        path.addQuadCurve(to: particle.end, control: mid)

        let anim = CAKeyframeAnimation(keyPath: "emitterPosition")
        anim.path = path
        anim.duration = particle.duration
        anim.calculationMode = .paced
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        emitter.add(anim, forKey: "flight")
        emitter.emitterPosition = particle.end

        DispatchQueue.main.asyncAfter(deadline: .now() + particle.duration) {
            cell.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + particle.duration + Double(cell.lifetime) + 0.15) { [weak emitter] in
            emitter?.removeFromSuperlayer()
        }
    }

    private static let sparkImage: CGImage = {
        let size = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
            endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: CGFloat(size / 2),
            options: []
        )
        return ctx.makeImage()!
    }()
}
