import SwiftUI

/// Captures the on-screen frame of any view tagged with a key, in the shared
/// "dashboard" coordinate space — the plumbing that lets a particle fly from a
/// session card to the top-bar ticker without the two views knowing about each other.
struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func reportFrame(_ key: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: FramePreferenceKey.self, value: [key: proxy.frame(in: .named("dashboard"))])
            }
        )
    }
}

/// One real cost event in flight from its session card to the ticker.
struct FountainParticle: Identifiable {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
    let spawnedAt: Date
    let duration: Double = 0.75
}

/// One expanding, fading ring — the shockwave for a real per-session event
/// (new cost landing, a tool error), not a decorative loop.
struct RippleInstance: Identifiable {
    let id = UUID()
    let spawnedAt: Date
    let color: Color
    let duration: Double = 0.9
}

struct RippleOverlay: View {
    let ripples: [RippleInstance]

    var body: some View {
        if ripples.isEmpty {
            Color.clear.allowsHitTesting(false)
        } else {
            animatedLayer
        }
    }

    private var animatedLayer: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height) * 0.72

                for r in ripples {
                    let t = now.timeIntervalSince(r.spawnedAt) / r.duration
                    guard t >= 0, t <= 1 else { continue }
                    let ease = 1 - pow(1 - t, 3) // fast start, slow finish — a real shockwave decelerates
                    let radius = maxRadius * ease
                    let opacity = pow(1 - t, 1.4)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

                    var ring = context
                    ring.opacity = opacity * 0.6
                    ring.stroke(Path(ellipseIn: rect), with: .color(r.color), lineWidth: 2.5 * (1 - CGFloat(t) * 0.5))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A brief red flash + shake — the visual for a real `tool_result.is_error` event,
/// not a constant effect: it decays back to normal within a fraction of a second.
struct GlitchEffect: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: active ? 2.5 : 0)
            .overlay(
                Rectangle()
                    .fill(Theme.critical.opacity(active ? 0.16 : 0))
                    .allowsHitTesting(false)
            )
            .animation(
                active ? .easeInOut(duration: 0.05).repeatCount(4, autoreverses: true) : .easeOut(duration: 0.18),
                value: active
            )
    }
}

extension View {
    func glitch(_ active: Bool) -> some View {
        modifier(GlitchEffect(active: active))
    }
}
