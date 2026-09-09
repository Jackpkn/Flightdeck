import SwiftUI

/// Bytes per file type. Bars grow in on arrival with a slight per-row stagger,
/// and hovering a row surfaces the file count that isn't worth showing on
/// every row at rest.
struct DiskTypePanel: View {
    @Environment(DiskScanner.self) private var scanner

    @State private var grown = false
    @State private var hovered: FileCategory?

    private var rows: [(category: FileCategory, bytes: Int64, count: Int)] {
        scanner.result.categoryBytes
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, bytes: $0.value, count: scanner.result.categoryCounts[$0.key] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.copilotColor)
                Text("BY FILE TYPE").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                Text("\(scanner.result.filesScanned.formatted()) files")
                    .font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
            }

            let maxBytes = rows.first?.bytes ?? 1
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.category) { index, row in
                    let isHovered = hovered == row.category
                    HStack(spacing: 8) {
                        Text(row.category.label)
                            .font(Theme.mono(9.5, weight: isHovered ? .semibold : .regular))
                            .foregroundStyle(isHovered ? Theme.copilotColor : Theme.ink3)
                            .frame(width: 74, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.copilotColor.opacity(isHovered ? 0.95 : 0.7))
                                    .frame(
                                        width: max(
                                            2,
                                            geo.size.width * Double(row.bytes) / Double(maxBytes) * (grown ? 1 : 0)
                                        )
                                    )
                                    .shadow(color: isHovered ? Theme.copilotColor.opacity(0.7) : .clear, radius: 8)
                                    .animation(
                                        .spring(response: 0.55, dampingFraction: 0.85)
                                            .delay(Double(index) * 0.05),
                                        value: grown
                                    )
                            }
                        }
                        .frame(height: 13)

                        Text(isHovered ? "\(row.count.formatted()) files" : Self.size(row.bytes))
                            .font(Theme.mono(10, weight: .semibold))
                            .foregroundStyle(isHovered ? Theme.copilotColor : Theme.ink2)
                            .frame(width: 74, alignment: .trailing)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(
                        isHovered ? Theme.copilotColor.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contentShape(Rectangle())
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

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
