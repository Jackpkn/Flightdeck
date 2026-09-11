import SwiftUI

/// One file-type row, resolved ahead of the view so `body` never type-checks
/// tuple arithmetic. `fraction` is the bar length relative to the largest row.
private struct DiskTypeRow: Identifiable {
    let category: FileCategory
    let bytes: Int64
    let count: Int
    let fraction: Double
    let index: Int

    var id: FileCategory { category }
}

/// Bytes per file type. Bars grow in on arrival with a slight per-row stagger,
/// and hovering a row surfaces the file count that isn't worth showing on
/// every row at rest.
struct DiskTypePanel: View {
    @Environment(DiskScanner.self) private var scanner

    @State private var grown = false
    @State private var hovered: FileCategory?

    private var rows: [DiskTypeRow] {
        let sorted = scanner.result.categoryBytes
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let maxBytes = Double(sorted.first?.value ?? 1)
        guard maxBytes > 0 else { return [] }

        return sorted.enumerated().map { index, entry in
            DiskTypeRow(
                category: entry.key,
                bytes: entry.value,
                count: scanner.result.categoryCounts[entry.key] ?? 0,
                fraction: Double(entry.value) / maxBytes,
                index: index
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bars
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.copilotColor)
        .cornerBracket(color: Theme.copilotColor)
        .onAppear { grown = true }
        .onChange(of: scanner.result.filesScanned) { _, _ in
            grown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { grown = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.copilotColor)
            Text("BY FILE TYPE").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
            Spacer()
            Text("\(scanner.result.filesScanned.formatted()) files")
                .font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
        }
    }

    private var bars: some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                TypeBar(row: row, isHovered: hovered == row.category, grown: grown)
                    .onHover { hovering in
                        if hovering {
                            hovered = row.category
                        } else if hovered == row.category {
                            hovered = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovered)
    }
}

/// A single labelled bar. Split out so the type-checker solves one small row
/// rather than the whole list inside `DiskTypePanel.body`.
private struct TypeBar: View {
    let row: DiskTypeRow
    let isHovered: Bool
    let grown: Bool

    private var accent: Color { isHovered ? Theme.copilotColor : Theme.ink3 }
    private var trailing: String {
        isHovered ? "\(row.count.formatted()) files" : Self.size(row.bytes)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.category.label)
                .font(Theme.mono(9.5, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(accent)
                .frame(width: 74, alignment: .leading)

            bar
                .frame(height: 13)

            Text(trailing)
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.copilotColor : Theme.ink2)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            isHovered ? Theme.copilotColor.opacity(0.07) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.copilotColor.opacity(isHovered ? 0.95 : 0.7))
                    .frame(width: Self.width(in: geo.size.width, fraction: row.fraction, grown: grown))
                    .shadow(color: isHovered ? Theme.copilotColor.opacity(0.7) : .clear, radius: 8)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.85).delay(Double(row.index) * 0.05),
                        value: grown
                    )
            }
        }
    }

    /// Collapsed bars keep a 2pt stub so the track still reads as a row.
    private static func width(in available: CGFloat, fraction: Double, grown: Bool) -> CGFloat {
        guard grown else { return minimumWidth }
        return max(minimumWidth, available * CGFloat(fraction))
    }

    private static let minimumWidth: CGFloat = 2

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
