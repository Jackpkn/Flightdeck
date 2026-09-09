import SwiftUI

/// Callout labels around a ring: a radial stub off the arc, an elbow, then the
/// text — so a slice states what it is in place, instead of making the reader
/// match colors against a legend.
///
/// Only slices above a share threshold get labeled; below that the lines
/// collide into spaghetti and the legend covers them instead. Labels are
/// de-collided vertically per side, which is the whole reason this can't just
/// be text pinned at each slice's mid-angle.
struct LeaderLabels: View {
    let nodes: [ChartNode]
    let sweep: Double
    let ringRadius: CGFloat
    let hovered: String?

    /// Below this share a label has nowhere to go without overlapping.
    private static let minFraction = 0.035
    private static let maxLabels = 8

    private struct Callout {
        let node: ChartNode
        let anchor: CGPoint      // on the ring
        let elbow: CGPoint       // just outside the ring
        var textY: CGFloat       // adjusted for collisions
        let isRight: Bool
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for callout in callouts(in: size, center: center) {
                draw(callout, in: &context, size: size, center: center)
            }
        }
        .allowsHitTesting(false)
    }

    private func callouts(in size: CGSize, center: CGPoint) -> [Callout] {
        let candidates = nodes
            .filter { $0.fraction >= Self.minFraction }
            .prefix(Self.maxLabels)

        var right: [Callout] = []
        var left: [Callout] = []

        for node in candidates {
            let mid = (node.start + node.end) / 2 * sweep
            let angle = (-90 + 360 * mid) * .pi / 180
            let onRing = CGPoint(
                x: center.x + ringRadius * cos(angle),
                y: center.y + ringRadius * sin(angle)
            )
            let elbow = CGPoint(
                x: center.x + (ringRadius + 13) * cos(angle),
                y: center.y + (ringRadius + 13) * sin(angle)
            )
            let callout = Callout(
                node: node,
                anchor: onRing,
                elbow: elbow,
                textY: elbow.y,
                isRight: cos(angle) >= 0
            )
            if callout.isRight { right.append(callout) } else { left.append(callout) }
        }

        return declutter(right, in: size) + declutter(left, in: size)
    }

    /// Pushes labels apart top-down, then shifts the whole column back inside
    /// the frame if it overflowed.
    private func declutter(_ callouts: [Callout], in size: CGSize) -> [Callout] {
        guard !callouts.isEmpty else { return [] }
        let gap: CGFloat = 15
        var sorted = callouts.sorted { $0.textY < $1.textY }

        for index in 1..<sorted.count {
            let minimum = sorted[index - 1].textY + gap
            if sorted[index].textY < minimum {
                sorted[index].textY = minimum
            }
        }

        if let last = sorted.last, last.textY > size.height - 8 {
            let overflow = last.textY - (size.height - 8)
            for index in sorted.indices {
                sorted[index].textY = max(8, sorted[index].textY - overflow)
            }
        }
        return sorted
    }

    private func draw(_ callout: Callout, in context: inout GraphicsContext, size: CGSize, center: CGPoint) {
        let isHovered = hovered == callout.node.id
        let textX = callout.isRight
            ? min(center.x + ringRadius + 46, size.width - 6)
            : max(center.x - ringRadius - 46, 6)

        var path = Path()
        path.move(to: callout.anchor)
        path.addLine(to: callout.elbow)
        path.addLine(to: CGPoint(x: textX, y: callout.textY))

        context.stroke(
            path,
            with: .color(callout.node.color.opacity(isHovered ? 1 : 0.55)),
            lineWidth: isHovered ? 1.4 : 1
        )
        context.fill(
            Path(ellipseIn: CGRect(x: callout.anchor.x - 1.6, y: callout.anchor.y - 1.6, width: 3.2, height: 3.2)),
            with: .color(callout.node.color)
        )

        let percent = Int((callout.node.fraction * 100).rounded())
        let label = Text(Self.trim(callout.node.name))
            .font(Theme.ui(10, weight: isHovered ? .semibold : .regular))
            .foregroundStyle(isHovered ? Theme.ink1 : Theme.ink2)
            + Text("  \(percent)%")
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(callout.node.color)

        context.draw(
            label,
            at: CGPoint(x: callout.isRight ? textX + 4 : textX - 4, y: callout.textY),
            anchor: callout.isRight ? .leading : .trailing
        )
    }

    private static func trim(_ name: String) -> String {
        name.count <= 16 ? name : String(name.prefix(15)) + "…"
    }
}
