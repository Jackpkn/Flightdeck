import SwiftUI

/// High-performance developer instrument discovering active listening ports (e.g. :3000, :5173, :8080, :5432)
/// with 1-click single process termination and multi-select "checkout-style" batch port freeing.
struct PortHunterPanel: View {
    @Environment(PortScanner.self) private var scanner
    @FocusState private var searchFocused: Bool
    @State private var confirmingFreeAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            checkoutToolbar

            let items = scanner.filteredPorts
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { port in
                            PortRow(port: port)
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
            "Free all \(scanner.ports.filter(\.isDevPort).count) active developer ports?",
            isPresented: $confirmingFreeAll,
            titleVisibility: .visible
        ) {
            Button("Free All Dev Ports", role: .destructive) {
                scanner.freeAllDevPorts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will terminate all local dev processes (Vite, Next.js, Django, Postgres, etc.) currently listening on ports under 49152.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: Theme.accent)
            Text("LISTENING PORTS")
                .font(Theme.display(12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.ink2)

            let devCount = scanner.ports.filter(\.isDevPort).count
            Text("\(devCount) ACTIVE")
                .font(Theme.mono(10.5, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(Theme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accent)

            Spacer(minLength: 8)

            inlineSearch
            devFilterToggle

            Button {
                scanner.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(scanner.isScanning ? Theme.accent : Theme.ink3)
                    .rotationEffect(scanner.isScanning ? .degrees(360) : .zero)
                    .animation(scanner.isScanning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: scanner.isScanning)
            }
            .buttonStyle(.plain)
            .help("Refresh listening ports")
        }
    }

    // MARK: - Inline Search

    private var inlineSearch: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.ink3)

            TextField("Port / Name", text: Bindable(scanner).searchQuery)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink1)
                .focused($searchFocused)
                .frame(width: 96)

            if !scanner.searchQuery.isEmpty {
                Button {
                    scanner.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3.5)
        .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(searchFocused ? Theme.accent.opacity(0.5) : Theme.hairline2, lineWidth: 0.8)
        )
    }

    // MARK: - Dev Filter Toggle

    private var devFilterToggle: some View {
        Button {
            scanner.showDevOnly.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: scanner.showDevOnly ? "bolt.fill" : "bolt")
                    .font(.system(size: 10))
                Text("DEV ONLY")
                    .font(Theme.mono(10.5, weight: .bold))
            }
            .padding(.horizontal, 7).padding(.vertical, 3.5)
            .background(
                scanner.showDevOnly ? Theme.accent.opacity(0.18) : Theme.track.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .foregroundStyle(scanner.showDevOnly ? Theme.accent : Theme.ink3)
        }
        .buttonStyle(.plain)
        .help(scanner.showDevOnly ? "Showing standard dev ports (<49152)" : "Showing all system & ephemeral ports")
    }

    // MARK: - Checkout Toolbar (Multi-Select Batch Freeing)

    private var checkoutToolbar: some View {
        HStack(spacing: 10) {
            let selectedCount = scanner.selectedPortIds.count

            // Select All Checkbox
            Button {
                if scanner.areAllFilteredSelected {
                    scanner.deselectAll()
                } else {
                    scanner.selectAllFiltered()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: scanner.areAllFilteredSelected ? "checkmark.square.fill" : (selectedCount > 0 ? "minus.square.fill" : "square"))
                        .font(.system(size: 12))
                        .foregroundStyle(selectedCount > 0 ? Theme.accent : Theme.ink3)
                    Text(scanner.areAllFilteredSelected ? "DESELECT" : "SELECT ALL")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if selectedCount > 0 {
                // Checkout-style Free Selected Button
                Button {
                    scanner.freeSelected()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 10.5))
                        Text("FREE SELECTED (\(selectedCount))")
                            .font(Theme.mono(11, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10).padding(.vertical, 4.5)
                    .background(Theme.critical.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.critical, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                // Quick Free All Dev Ports Button
                Button {
                    confirmingFreeAll = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 9.5))
                        Text("FREE ALL DEV")
                            .font(Theme.mono(10.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.warning.opacity(0.3), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Terminate all active developer server ports (<49152)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent.opacity(0.5))

            Text("NO CONFLICTING PORTS")
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.ink1)

            Text("All developer ports are idle. No lingering zombie servers.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Port Row

private struct PortRow: View {
    let port: ListeningPort
    @Environment(PortScanner.self) private var scanner
    @State private var isHovered = false

    private var isSelected: Bool {
        scanner.isSelected(id: port.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                scanner.toggleSelection(id: port.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.ink3.opacity(0.6))
            }
            .buttonStyle(.plain)

            // Port Pill
            HStack(spacing: 2) {
                Text(":")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.ink3)
                Text(String(port.port))
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(port.isDevPort ? Theme.accent : Theme.ink2)
            }
            .frame(width: 68, alignment: .leading)

            // Process Name & PID
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(port.processName)
                        .font(Theme.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink1)
                        .lineLimit(1)

                    Text("PID \(port.pid)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Theme.track.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                }

                Text(port.address)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink3.opacity(0.75))
            }

            Spacer()

            // Individual 1-Click FREE Button
            Button {
                scanner.freePort(port)
            } label: {
                Text("FREE")
                    .font(Theme.mono(10.5, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : Theme.critical)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(isHovered ? Theme.critical : Theme.critical.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.critical.opacity(0.4), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help("Terminate PID \(port.pid) to free port :\(port.port)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.accent.opacity(0.08) : (isHovered ? Theme.track.opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.accent.opacity(0.35) : Theme.hairline2, lineWidth: isSelected ? 1 : 0.5)
        )
        .onHover { isHovered = $0 }
    }
}
