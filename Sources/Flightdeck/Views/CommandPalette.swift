import SwiftUI
import AppKit

/// One thing you can do from the palette — a real action, not a placeholder row.
struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let run: () -> Void
}

/// Raycast's actual pattern: ⌘K opens a floating, blurred-backdrop search bar,
/// arrow keys move a highlighted row, Enter runs it, Escape dismisses.
struct CommandPalette: View {
    @Environment(DashboardStore.self) private var store
    @Binding var isPresented: Bool
    @Binding var showGraph: Bool
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private var actions: [PaletteAction] {
        var items: [PaletteAction] = [
            PaletteAction(
                title: showGraph ? "Go to Dashboard" : "Go to Session Graph",
                subtitle: "⌘⇧G",
                run: { showGraph.toggle() }
            ),
            PaletteAction(
                title: "Copy last 24h spend",
                subtitle: Formatters.usd(store.last24hSpend),
                run: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(Formatters.usd(store.last24hSpend), forType: .string)
                }
            ),
            PaletteAction(
                title: "Kill all AI agents",
                subtitle: "Terminate active Claude Code & Cursor agent CLI sessions",
                run: {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                    task.arguments = ["-f", "claude|cursor"]
                    try? task.run()
                    CockpitAudio.playAlert()
                }
            ),
            PaletteAction(
                title: "Open Downloads folder",
                subtitle: "~/Downloads",
                run: {
                    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    NSWorkspace.shared.open(downloads)
                    CockpitAudio.playSuccess()
                }
            ),
            PaletteAction(
                title: "Toggle Audio Effects",
                subtitle: CockpitAudio.isSoundEnabled ? "Currently ON · Click to mute" : "Currently MUTED · Click to enable",
                run: {
                    CockpitAudio.isSoundEnabled.toggle()
                    if CockpitAudio.isSoundEnabled { CockpitAudio.playPing() }
                }
            ),
        ]
        for session in store.activeSessions.prefix(20) {
            items.append(PaletteAction(
                title: "Session · \(session.project)",
                subtitle: session.branch.isEmpty ? (session.model.isEmpty ? "no branch" : session.model) : "⎇ \(session.branch)",
                run: {}
            ))
        }
        guard !query.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.ink3)
                    TextField("Search Flightdeck…", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(15))
                        .focused($searchFocused)
                        .onSubmit(runSelected)
                        .onChange(of: query) { _, _ in selected = 0 }
                    Text("esc").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.track, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(14)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title).font(Theme.ui(13.5, weight: .medium))
                                    Text(action.subtitle).font(Theme.mono(11)).foregroundStyle(Theme.ink3)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(
                                i == selected ? Theme.accent.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selected = i; runSelected() }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 480)
            .glassPanel(cornerRadius: 14)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        }
        .onAppear { searchFocused = true }
        .onExitCommand { isPresented = false }
        .onMoveCommand { direction in
            switch direction {
            case .down: selected = min(selected + 1, max(actions.count - 1, 0))
            case .up: selected = max(selected - 1, 0)
            default: break
            }
        }
    }

    private func runSelected() {
        guard actions.indices.contains(selected) else { return }
        actions[selected].run()
        isPresented = false
    }
}
