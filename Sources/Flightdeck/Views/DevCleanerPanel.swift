import SwiftUI

/// Developer cache and inactive RAM purger docked at the bottom-right of the Activity tab.
/// Reclaims multi-gigabyte build sludge across Xcode, SPM, Node, Gradle, CocoaPods in 1 click.
struct DevCleanerPanel: View {
    @Environment(DevCleaner.self) private var cleaner
    @State private var confirmingPurgeAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            actionToolbar

            let items = cleaner.categories
            if items.allSatisfy({ $0.sizeBytes == 0 }) && !cleaner.isScanning {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { category in
                            CruftRow(category: category)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(accent: Theme.accent)
        .cornerBracket(color: Theme.accent)
        .confirmationDialog(
            "Purge all developer build caches?",
            isPresented: $confirmingPurgeAll,
            titleVisibility: .visible
        ) {
            Button("Purge All Caches", role: .destructive) {
                cleaner.purgeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let totalStr = ByteCountFormatter.string(fromByteCount: cleaner.totalCruftBytes, countStyle: .file)
            Text("This will safely remove \(totalStr) of accumulated build outputs (DerivedData, npm cache, Gradle caches). Clean builds will regenerate what they need.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("BUILD CACHE CLEANUP")
                .font(Theme.display(12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink2)

            let total = cleaner.totalCruftBytes
            if total > 0 {
                let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                Text("\(totalStr) RECLAIMABLE")
                    .font(Theme.mono(10.5, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 8)

            Button {
                cleaner.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(cleaner.isScanning ? Theme.accent : Theme.ink3)
                    .rotationEffect(cleaner.isScanning ? .degrees(360) : .zero)
                    .animation(cleaner.isScanning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: cleaner.isScanning)
            }
            .buttonStyle(.plain)
            .help("Re-scan cache sizes")
        }
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 8) {
            let total = cleaner.totalCruftBytes

            Button {
                confirmingPurgeAll = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash.fill").font(.system(size: 9.5))
                    Text("PURGE ALL CRUFT")
                        .font(Theme.mono(10.5, weight: .bold))
                }
                .foregroundStyle(total > 0 ? Color.white : Theme.ink3)
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(
                    total > 0 ? Theme.critical.opacity(0.85) : Theme.track.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(total == 0)

            Spacer()

            Button {
                cleaner.flushRAM()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "memorychip").font(.system(size: 9.5))
                    Text("FLUSH INACTIVE RAM")
                        .font(Theme.mono(10.5, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help("Release inactive system memory pages")
        }
        .padding(.horizontal, 7).padding(.vertical, 4.5)
        .background(Theme.track.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "leaf.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.good)

            Text("ALL CLEAN · ZERO BUILD SLUDGE")
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.ink1)

            Text("All developer caches are lean. No wasted gigabytes on disk.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cruft Row

private struct CruftRow: View {
    let category: CruftCategory
    @Environment(DevCleaner.self) private var cleaner
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            // Icon
            Image(systemName: category.icon)
                .font(.system(size: 13))
                .foregroundStyle(category.sizeBytes > 0 ? Theme.accent : Theme.ink3)
                .frame(width: 18)

            // Name & Path
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink1)

                Text(category.path.path)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Size readout
            let sizeStr = ByteCountFormatter.string(fromByteCount: category.sizeBytes, countStyle: .file)
            Text(category.sizeBytes > 0 ? sizeStr : "0 B")
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(category.sizeBytes > 100_000_000 ? Theme.warning : Theme.ink2)

            // Purge Button
            if category.sizeBytes > 0 {
                Button {
                    cleaner.purge(category: category)
                } label: {
                    Text("PURGE")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(isHovered ? Color.white : Theme.critical)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(isHovered ? Theme.critical : Theme.critical.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.critical.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Purge \(category.name) files")
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.good.opacity(0.6))
                    .frame(width: 36)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isHovered ? Theme.track.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline2, lineWidth: 0.5))
        .onHover { isHovered = $0 }
    }
}
