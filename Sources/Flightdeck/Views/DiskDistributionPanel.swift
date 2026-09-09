import SwiftUI

/// Bytes per size class — whether space is going to a handful of giants or a
/// mountain of mid-sized files. Columns rise in sequence on arrival, and a
/// hovered column reports its exact numbers above the bar.
struct DiskDistributionPanel: View {
    @Environment(DiskScanner.self) private var scanner

    @State private var risen = false
    @State private var hovered: SizeBucket?

    private var maxBytes: Int64 {
        SizeBucket.allCases.map { scanner.result.bucketBytes[$0] ?? 0 }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LiveDot(color: Theme.accentSecondary)
                Text("BY FILE SIZE").font(Theme.display(11)).tracking(0.6).foregroundStyle(Theme.ink3)
                Spacer()
                if let hovered {
                    Text("\((scanner.result.bucketCounts[hovered] ?? 0).formatted()) files")
                        .font(Theme.mono(9.5, weight: .semibold))
                        .foregroundStyle(Theme.accentSecondary)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(SizeBucket.allCases.enumerated()), id: \.element) { index, bucket in
                    column(bucket: bucket, index: index)
                }
            }
            .frame(height: 150, alignment: .bottom)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovered)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accentSecondary)
        .cornerBracket(color: Theme.accentSecondary)
        .onAppear { risen = true }
        .onChange(of: scanner.result.filesScanned) { _, _ in
            risen = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { risen = true }
        }
    }

    private func column(bucket: SizeBucket, index: Int) -> some View {
        let bytes = scanner.result.bucketBytes[bucket] ?? 0
        let count = scanner.result.bucketCounts[bucket] ?? 0
        let isHovered = hovered == bucket
        let height = 104 * CGFloat(Double(bytes) / Double(max(maxBytes, 1))) * (risen ? 1 : 0)

        return VStack(spacing: 5) {
            Text(Self.size(bytes))
                .font(Theme.mono(8.5, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(isHovered ? Theme.accentSecondary : Theme.ink3)

            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.accentSecondary.opacity(isHovered ? 0.95 : 0.7))
                .frame(width: isHovered ? 34 : 30, height: max(3, height))
                .shadow(color: isHovered ? Theme.accentSecondary.opacity(0.8) : .clear, radius: 10)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06),
                    value: risen
                )

            Text(bucket.label)
                .font(Theme.mono(8.5, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.ink1 : Theme.ink3)

            Text("\(count)")
                .font(Theme.mono(8.5))
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hovered = bucket
            } else if hovered == bucket {
                hovered = nil
            }
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
