import SwiftUI

/// One instrument, four lenses on the same tree, one shared drill-down state.
/// Four separate panels of the same numbers would just be redundant; switching
/// the rendering keeps the comparison honest and the focus consistent.
struct DiskExplorerPanel: View {
    @Environment(DiskScanner.self) private var scanner
    @Environment(FileBrowser.self) private var browser

    enum Mode: String, CaseIterable {
        case donut = "DONUT"
        case sunburst = "SUNBURST"
        case bubbles = "BUBBLES"
        case treemap = "TREEMAP"
    }

    @State private var mode: Mode = .donut
    @State private var focus: String?
    @State private var hovered: String?
    @State private var sweep: Double = 0
    @State private var settled = false

    private var rootPath: String {
        focus ?? scanner.scannedRoot?.path ?? ""
    }

    private var nodes: [ChartNode] {
        let children = scanner.result.tree.childNodes(of: rootPath)
        let total = max(children.reduce(Int64(0)) { $0 + $1.bytes }, 1)

        var cursor = 0.0
        return children.prefix(12).enumerated().map { index, child in
            let fraction = Double(child.bytes) / Double(total)
            let node = ChartNode(
                path: child.path,
                name: child.name,
                bytes: child.bytes,
                fraction: fraction,
                start: cursor,
                end: cursor + fraction,
                color: Theme.sizeRamp[index % Theme.sizeRamp.count],
                hasChildren: child.hasChildren
            )
            cursor += fraction
            return node
        }
    }

    private var hoveredNode: ChartNode? {
        nodes.first { $0.id == hovered }
    }

    private var focusBytes: Int64 {
        scanner.result.tree.sizes[rootPath] ?? scanner.result.totalBytes
    }

    /// Path from the scan root down to the focused folder.
    private var trail: [(name: String, path: String)] {
        guard let root = scanner.scannedRoot?.path else { return [] }
        var result: [(String, String)] = [(URL(fileURLWithPath: root).lastPathComponent, root)]
        guard let focus, focus != root, focus.hasPrefix(root) else { return result }

        var prefix = root
        for component in focus.dropFirst(root.count).split(separator: "/") {
            prefix += "/" + component
            result.append((String(component), prefix))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            trailBar

            ZStack {
                switch mode {
                case .donut:
                    ZStack {
                        DonutChart(nodes: nodes, sweep: sweep, hovered: $hovered, onDrill: drill)
                            .frame(width: 240, height: 240)
                            .overlay(centerReadout.allowsHitTesting(false))
                        LeaderLabels(nodes: nodes, sweep: sweep, ringRadius: 120, hovered: hovered)
                    }
                    .frame(height: 300)
                case .sunburst:
                    SunburstChart(
                        nodes: nodes,
                        childrenOf: { node in
                            scanner.result.tree.childNodes(of: node.path)
                                .map { (name: $0.name, bytes: $0.bytes, path: $0.path) }
                        },
                        sweep: sweep,
                        hovered: $hovered,
                        onDrill: drill
                    )
                    .frame(width: 280, height: 280)
                    .overlay(centerReadout.allowsHitTesting(false))
                    .overlay(
                        LeaderLabels(nodes: nodes, sweep: sweep, ringRadius: 140, hovered: hovered)
                            .frame(width: 620, height: 300)
                    )
                case .bubbles:
                    BubbleChart(nodes: nodes, settled: settled, hovered: $hovered, onDrill: drill)
                        .frame(height: 300)
                case .treemap:
                    TreemapChart(nodes: nodes, settled: settled, hovered: $hovered, onDrill: drill)
                        .frame(height: 300)
                }
            }
            .frame(maxWidth: .infinity)

            legend
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .onAppear(perform: replay)
        .onChange(of: scanner.result.filesScanned) { _, _ in
            focus = nil
            replay()
        }
        .onChange(of: mode) { _, _ in replay() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LiveDot(color: Theme.accent)
            Text("SPACE EXPLORER").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)

            Spacer(minLength: 8)

            if let hoveredNode {
                Text("\(hoveredNode.name) · \(Self.size(hoveredNode.bytes)) · \(Int((hoveredNode.fraction * 100).rounded()))%")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(hoveredNode.color)
                    .lineLimit(1)
            }

            HStack(spacing: 2) {
                ForEach(Mode.allCases, id: \.self) { option in
                    Button { mode = option } label: {
                        Text(option.rawValue)
                            .font(Theme.mono(9, weight: .semibold))
                            .foregroundStyle(mode == option ? Theme.accent : Theme.ink3)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(
                                mode == option ? Theme.accent.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Theme.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Drill trail — click any level to jump back up to it.
    private var trailBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.right.circle").font(.system(size: 10)).foregroundStyle(Theme.ink3)
            ForEach(Array(trail.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").font(Theme.mono(10)).foregroundStyle(Theme.ink3.opacity(0.6))
                }
                Button {
                    focus = index == 0 ? nil : crumb.path
                    replay()
                } label: {
                    Text(crumb.name.isEmpty ? "/" : crumb.name)
                        .font(Theme.mono(10, weight: index == trail.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == trail.count - 1 ? Theme.ink1 : Theme.ink3)
                }
                .buttonStyle(.plain)
            }
            Spacer()

            Button {
                browser.navigate(to: URL(fileURLWithPath: rootPath))
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text("VIEW IN FILES")
                        .font(Theme.mono(8.5, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Open this folder in the Files browser")

            Text(Self.size(focusBytes)).font(Theme.mono(10, weight: .semibold)).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.track.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
    }

    private var centerReadout: some View {
        VStack(spacing: 1) {
            if let hoveredNode {
                Text(hoveredNode.name)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(hoveredNode.color).lineLimit(1)
                Text(Self.size(hoveredNode.bytes))
                    .font(Theme.mono(13, weight: .bold)).foregroundStyle(Theme.ink1)
                Text("\(Int((hoveredNode.fraction * 100).rounded()))%")
                    .font(Theme.mono(8.5)).foregroundStyle(Theme.ink3)
            } else {
                Text(Self.size(focusBytes))
                    .font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.ink1)
                Text(nodes.isEmpty ? "no children" : "\(nodes.count) folders")
                    .font(Theme.mono(8.5)).foregroundStyle(Theme.ink3)
            }
        }
        .frame(width: 96)
    }

    private var legend: some View {
        // Wraps, so a wide panel uses its width instead of leaving it empty.
        FlowLayout(spacing: 6) {
            ForEach(nodes) { node in
                let isHovered = hovered == node.id
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(node.color).frame(width: 7, height: 7)
                        .shadow(color: isHovered ? node.color : .clear, radius: 4)
                    Text(node.name).font(Theme.ui(10.5)).foregroundStyle(isHovered ? Theme.ink1 : Theme.ink2).lineLimit(1)
                    Text("\(Int((node.fraction * 100).rounded()))%")
                        .font(Theme.mono(9.5, weight: .semibold)).foregroundStyle(isHovered ? node.color : Theme.ink3)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(
                    isHovered ? node.color.opacity(0.12) : Color.white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { hovered = node.id } else if hovered == node.id { hovered = nil }
                }
                .onTapGesture { drill(node) }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovered)
    }

    private func drill(_ node: ChartNode) {
        guard node.hasChildren else { return }
        focus = node.path
        hovered = nil
        replay()
    }

    /// Re-runs the entrance animation so a drill or a mode switch reads as the
    /// data landing rather than swapping instantly.
    private func replay() {
        sweep = 0
        settled = false
        withAnimation(.easeOut(duration: 0.7)) { sweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { settled = true }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Minimal wrapping layout — the legend can be any number of chips and should
/// use the panel's full width rather than one long row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
