import SwiftUI

/// One arc of a ring. Animatable so a ring can sweep into existence rather
/// than popping in, and a real Shape so SwiftUI hit-tests the actual filled
/// wedge — no hand-rolled angle math for hover.
struct DonutSliceShape: Shape {
    var startFraction: Double
    var endFraction: Double
    var innerRatio: Double = 0.6

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startFraction, endFraction) }
        set {
            startFraction = newValue.first
            endFraction = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let start = Angle.degrees(-90 + 360 * startFraction)
        let end = Angle.degrees(-90 + 360 * endFraction)

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// One folder as drawn by any of the four chart modes.
struct ChartNode: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Int64
    let fraction: Double
    let start: Double
    let end: Double
    let color: Color
    let hasChildren: Bool
}

// MARK: - Donut

struct DonutChart: View {
    let nodes: [ChartNode]
    let sweep: Double
    @Binding var hovered: String?
    let onDrill: (ChartNode) -> Void

    var body: some View {
        ZStack {
            ForEach(nodes) { node in
                slice(for: node)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
    }

    private func slice(for node: ChartNode) -> some View {
        let shape = DonutSliceShape(startFraction: node.start * sweep, endFraction: node.end * sweep)
        let isHovered = hovered == node.id
        return shape
            .fill(node.color)
            .overlay(shape.stroke(Theme.panel, lineWidth: 2))
            .scaleEffect(isHovered ? 1.06 : 1)
            .opacity(hovered == nil || isHovered ? 1 : 0.3)
            .shadow(color: isHovered ? node.color.opacity(0.85) : .clear, radius: 14)
            .onHover { hover(node, $0) }
            .onTapGesture { onDrill(node) }
    }

    private func hover(_ node: ChartNode, _ hovering: Bool) {
        if hovering { hovered = node.id } else if hovered == node.id { hovered = nil }
    }
}

// MARK: - Sunburst

/// Two concentric rings: the focused folder's children inside, their own
/// biggest children outside, each spanning its parent's arc.
struct SunburstChart: View {
    let nodes: [ChartNode]
    let childrenOf: (ChartNode) -> [(name: String, bytes: Int64, path: String)]
    let sweep: Double
    @Binding var hovered: String?
    let onDrill: (ChartNode) -> Void

    var body: some View {
        ZStack {
            ForEach(nodes) { node in
                innerSlice(for: node)
            }

            ForEach(nodes) { node in
                outerRing(for: node)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
    }

    private func innerSlice(for node: ChartNode) -> some View {
        let shape = DonutSliceShape(
            startFraction: node.start * sweep,
            endFraction: node.end * sweep,
            innerRatio: 0.38
        )
        let isHovered = hovered == node.id
        return shape
            .fill(node.color)
            .overlay(shape.stroke(Theme.panel, lineWidth: 2))
            .opacity(hovered == nil || isHovered ? 1 : 0.3)
            .shadow(color: isHovered ? node.color.opacity(0.8) : .clear, radius: 12)
            .onHover { hover(node.id, $0) }
            .onTapGesture { onDrill(node) }
            .padding(30)
    }

    @ViewBuilder
    private func outerRing(for parent: ChartNode) -> some View {
        let kids = childrenOf(parent)
        let total = max(kids.reduce(Int64(0)) { $0 + $1.bytes }, 1)
        let span = parent.end - parent.start
        // Only the parent's own arc is subdivided, so the ring stays truthful
        // even when a folder's children don't sum to its full size.
        let scale = span * min(1, Double(kids.reduce(Int64(0)) { $0 + $1.bytes }) / Double(max(parent.bytes, 1)))

        ZStack {
            ForEach(Array(kids.prefix(8).enumerated()), id: \.element.path) { index, kid in
                let priorFraction = kids.prefix(index).reduce(Int64(0)) { $0 + $1.bytes }
                let start = parent.start + scale * Double(priorFraction) / Double(total)
                let end = start + scale * Double(kid.bytes) / Double(total)
                outerSlice(start: start, end: end, parent: parent, kid: kid)
            }
        }
    }

    private func outerSlice(
        start: Double,
        end: Double,
        parent: ChartNode,
        kid: (name: String, bytes: Int64, path: String)
    ) -> some View {
        let shape = DonutSliceShape(startFraction: start * sweep, endFraction: end * sweep, innerRatio: 0.78)
        let isHovered = hovered == kid.path
        let label = ByteCountFormatter.string(fromByteCount: kid.bytes, countStyle: .file)
        return shape
            .fill(parent.color.opacity(isHovered ? 0.95 : 0.55))
            .overlay(shape.stroke(Theme.panel, lineWidth: 1.5))
            .shadow(color: isHovered ? parent.color : .clear, radius: 8)
            .onHover { hover(kid.path, $0) }
            .help("\(kid.name) · \(label)")
    }

    private func hover(_ id: String, _ hovering: Bool) {
        if hovering { hovered = id } else if hovered == id { hovered = nil }
    }
}

// MARK: - Bubble pack

/// Circles areas-proportional to size, positioned by a repulsion relaxation —
/// physics as the layout algorithm rather than as decoration. The solve is a
/// pure function run once per data change; the settling look comes from
/// animating into the solved positions, so nothing spins the CPU at rest.
struct BubbleChart: View {
    let nodes: [ChartNode]
    let settled: Bool
    @Binding var hovered: String?
    let onDrill: (ChartNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = Self.pack(nodes, in: geo.size)
            ZStack {
                ForEach(nodes) { node in
                    if let placed = layout[node.id] {
                        let isHovered = hovered == node.id
                        Circle()
                            .fill(node.color.opacity(isHovered ? 0.95 : 0.72))
                            .overlay(Circle().stroke(node.color, lineWidth: isHovered ? 1.5 : 0.8))
                            .frame(width: placed.radius * 2, height: placed.radius * 2)
                            .shadow(color: isHovered ? node.color.opacity(0.9) : .clear, radius: 14)
                            .overlay {
                                if placed.radius > 26 {
                                    VStack(spacing: 1) {
                                        Text(node.name)
                                            .font(Theme.mono(9, weight: .semibold))
                                            .lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: node.bytes, countStyle: .file))
                                            .font(Theme.mono(8))
                                    }
                                    .foregroundStyle(Theme.page)
                                    .padding(.horizontal, 4)
                                    .allowsHitTesting(false)
                                }
                            }
                            .position(
                                x: settled ? placed.center.x : geo.size.width / 2,
                                y: settled ? placed.center.y : geo.size.height / 2
                            )
                            .scaleEffect(settled ? (isHovered ? 1.08 : 1) : 0.1)
                            .onHover { hovering in
                                if hovering { hovered = node.id } else if hovered == node.id { hovered = nil }
                            }
                            .onTapGesture { onDrill(node) }
                            .help("\(node.name) · \(ByteCountFormatter.string(fromByteCount: node.bytes, countStyle: .file))")
                    }
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.72), value: settled)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovered)
        }
    }

    private struct Placed {
        var center: CGPoint
        var radius: CGFloat
    }

    /// Area ∝ bytes (so radius ∝ √bytes), then relax overlaps while pulling
    /// weakly toward the center. Deterministic: same data lands the same way.
    private static func pack(_ nodes: [ChartNode], in size: CGSize) -> [String: Placed] {
        guard !nodes.isEmpty, size.width > 0, size.height > 0 else { return [:] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxBytes = Double(nodes.map(\.bytes).max() ?? 1)
        let maxRadius = min(size.width, size.height) * 0.30

        var placed: [(id: String, p: Placed)] = nodes.enumerated().map { index, node in
            let radius = max(9, maxRadius * CGFloat((Double(node.bytes) / maxBytes).squareRoot()))
            // Seeded on a spiral so the starting state is stable, not random.
            let angle = Double(index) * 2.399
            let spread = 26.0 * Double(index).squareRoot()
            return (
                node.id,
                Placed(
                    center: CGPoint(
                        x: center.x + CGFloat(cos(angle) * spread),
                        y: center.y + CGFloat(sin(angle) * spread)
                    ),
                    radius: radius
                )
            )
        }

        for _ in 0..<260 {
            for i in placed.indices {
                // Weak pull to center keeps the cluster compact.
                let toCenter = CGVector(
                    dx: center.x - placed[i].p.center.x,
                    dy: center.y - placed[i].p.center.y
                )
                placed[i].p.center.x += toCenter.dx * 0.012
                placed[i].p.center.y += toCenter.dy * 0.012

                for j in placed.indices where j != i {
                    let dx = placed[i].p.center.x - placed[j].p.center.x
                    let dy = placed[i].p.center.y - placed[j].p.center.y
                    let distance = max(sqrt(dx * dx + dy * dy), 0.01)
                    let minimum = placed[i].p.radius + placed[j].p.radius + 3
                    guard distance < minimum else { continue }
                    let push = (minimum - distance) / 2
                    let nx = dx / distance
                    let ny = dy / distance
                    placed[i].p.center.x += nx * push
                    placed[i].p.center.y += ny * push
                    placed[j].p.center.x -= nx * push
                    placed[j].p.center.y -= ny * push
                }
            }
        }

        // Keep every circle inside the frame.
        for i in placed.indices {
            let r = placed[i].p.radius
            placed[i].p.center.x = min(max(placed[i].p.center.x, r), size.width - r)
            placed[i].p.center.y = min(max(placed[i].p.center.y, r), size.height - r)
        }

        return Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0.p) })
    }
}

// MARK: - Treemap

/// Recursive weight-balanced binary split, alternating orientation — gives
/// reasonable aspect ratios without the edge cases of a squarified row solver.
struct TreemapChart: View {
    let nodes: [ChartNode]
    let settled: Bool
    @Binding var hovered: String?
    let onDrill: (ChartNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = Self.layout(
                nodes,
                in: CGRect(origin: .zero, size: geo.size),
                horizontal: geo.size.width >= geo.size.height
            )
            ZStack(alignment: .topLeading) {
                ForEach(nodes) { node in
                    if let rect = rects[node.id] {
                        let isHovered = hovered == node.id
                        RoundedRectangle(cornerRadius: 4)
                            .fill(node.color.opacity(isHovered ? 0.95 : 0.72))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.panel, lineWidth: 2))
                            .overlay(alignment: .topLeading) {
                                if rect.width > 62 && rect.height > 28 {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(node.name)
                                            .font(Theme.mono(9, weight: .semibold))
                                            .lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: node.bytes, countStyle: .file))
                                            .font(Theme.mono(8))
                                    }
                                    .foregroundStyle(Theme.page)
                                    .padding(5)
                                    .allowsHitTesting(false)
                                }
                            }
                            .shadow(color: isHovered ? node.color.opacity(0.8) : .clear, radius: 12)
                            .frame(width: max(2, rect.width - 2), height: max(2, rect.height - 2))
                            .offset(x: rect.minX + 1, y: rect.minY + 1)
                            .opacity(settled ? 1 : 0)
                            .scaleEffect(settled ? 1 : 0.9)
                            .onHover { hovering in
                                if hovering { hovered = node.id } else if hovered == node.id { hovered = nil }
                            }
                            .onTapGesture { onDrill(node) }
                            .help("\(node.name) · \(ByteCountFormatter.string(fromByteCount: node.bytes, countStyle: .file))")
                    }
                }
            }
            .animation(.easeOut(duration: 0.45), value: settled)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovered)
        }
    }

    private static func layout(_ nodes: [ChartNode], in rect: CGRect, horizontal: Bool) -> [String: CGRect] {
        guard !nodes.isEmpty else { return [:] }
        if nodes.count == 1 {
            return [nodes[0].id: rect]
        }

        let total = nodes.reduce(0.0) { $0 + Double($1.bytes) }
        guard total > 0 else { return [:] }

        // Split where cumulative weight first reaches half.
        var running = 0.0
        var splitIndex = 0
        for (index, node) in nodes.enumerated() {
            running += Double(node.bytes)
            if running >= total / 2 {
                splitIndex = max(1, min(index + 1, nodes.count - 1))
                break
            }
        }

        let firstWeight = nodes.prefix(splitIndex).reduce(0.0) { $0 + Double($1.bytes) }
        let ratio = firstWeight / total

        let (rectA, rectB): (CGRect, CGRect) = horizontal
            ? (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width * ratio, height: rect.height),
                CGRect(x: rect.minX + rect.width * ratio, y: rect.minY, width: rect.width * (1 - ratio), height: rect.height)
            )
            : (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * ratio),
                CGRect(x: rect.minX, y: rect.minY + rect.height * ratio, width: rect.width, height: rect.height * (1 - ratio))
            )

        var result = layout(Array(nodes.prefix(splitIndex)), in: rectA, horizontal: rectA.width >= rectA.height)
        result.merge(layout(Array(nodes.dropFirst(splitIndex)), in: rectB, horizontal: rectB.width >= rectB.height)) { a, _ in a }
        return result
    }
}
