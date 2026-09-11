import SwiftUI
import AppKit

/// Setup sheet for Flightdeck's Claude Code integration.
///
/// Flightdeck can read transcripts on its own, but the live channel — context-window
/// size, running cost, and tool events as they happen — only exists if Claude Code is
/// configured to feed it. This shows exactly what is wired up, what is not, and
/// whether data is actually arriving, rather than leaving it to a CLI flag.
struct IntegrationSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var status: ClaudeIntegrationInstaller.Status?
    @State private var liveRowCount: Int = 0
    @State private var lastLiveUpdate: Date?
    @State private var notes: [String] = []
    @State private var backupPath: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var settingsURL: URL { ClaudeIntegrationInstaller.defaultSettingsURL() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explanation
                    checklist
                    dataFlow
                    if !notes.isEmpty { resultLog }
                    if let errorMessage { errorBanner(errorMessage) }
                }
                .padding(18)
            }

            Divider().background(Theme.hairline)
            footer
        }
        .frame(width: 620, height: 560)
        .background(Theme.page)
        .onAppear(perform: refresh)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.claudeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("CLAUDE CODE INTEGRATION")
                    .font(Theme.display(13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink1)
                Text(settingsURL.path)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if let status, status.isFullyInstalled {
                pill("CONNECTED", color: Theme.good)
            } else {
                pill("NOT CONNECTED", color: Theme.warning)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
    }

    private var explanation: some View {
        Text("""
        Flightdeck reads your session transcripts directly, so history works with no setup. \
        Installing the statusline and hooks adds the things transcripts don't record: the real \
        context-window size, running cost as it changes, and tool events the moment they happen.
        """)
        .font(Theme.ui(12))
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("WHAT GETS INSTALLED")

            if let status {
                checkRow(
                    done: status.statuslineInstalled,
                    blocked: status.hasStatuslineConflict,
                    title: "Statusline",
                    detail: status.hasStatuslineConflict
                        ? "You already have a different statusline configured — Flightdeck won't replace it."
                        : "Feeds live context-window size and running cost every few seconds."
                )
                ForEach(ClaudeIntegrationInstaller.requiredHooks, id: \.event) { hook in
                    checkRow(
                        done: status.installedHooks.contains(hook.event),
                        blocked: false,
                        title: "\(hook.event) hook",
                        detail: hookPurpose(hook.event)
                    )
                }
            } else {
                Text("Reading settings…")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    /// Installed is not the same as working — this reports whether rows are actually
    /// landing in the local database, which is the only proof the wiring holds.
    private var dataFlow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("IS DATA ARRIVING?")
            HStack(spacing: 10) {
                Circle()
                    .fill(liveRowCount > 0 ? Theme.good : Theme.ink3)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(liveRowCount > 0
                         ? "\(liveRowCount) live session row\(liveRowCount == 1 ? "" : "s") recorded"
                         : "No live session rows yet")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(liveRowCount > 0 ? Theme.ink1 : Theme.ink3)
                    Text(dataFlowDetail)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Button("Recheck") { refresh() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.accent)
            }
            .padding(10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var dataFlowDetail: String {
        if let lastLiveUpdate {
            return "last update \(Formatters.relativeAge(Date().timeIntervalSince(lastLiveUpdate)))"
        }
        if status?.isFullyInstalled == true {
            return "Start or resume a Claude Code session — rows appear within a few seconds."
        }
        return "Install the integration above, then start a Claude Code session."
    }

    private var resultLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("LAST RUN")
            ForEach(notes, id: \.self) { note in
                Text("· \(note)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.ink2)
            }
            if let backupPath {
                Text("Your previous settings were backed up to \(backupPath)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(Theme.mono(10.5))
            .foregroundStyle(Theme.critical)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.critical.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reveal settings.json") {
                NSWorkspace.shared.activateFileViewerSelecting([settingsURL])
            }
            .font(Theme.ui(12))

            Spacer()

            if status?.installedHooks.isEmpty == false || status?.statuslineInstalled == true {
                Button("Remove", role: .destructive) { runUninstall() }
                    .font(Theme.ui(12))
                    .disabled(isWorking)
            }

            Button("Close") { dismiss() }
                .font(Theme.ui(12))
                .keyboardShortcut(.cancelAction)

            Button(status?.isFullyInstalled == true ? "Reinstall" : "Install") { runInstall() }
                .font(Theme.ui(12, weight: .semibold))
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 14, trailing: 18))
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(9.5, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(Theme.ink3)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.mono(9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func checkRow(done: Bool, blocked: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: blocked ? "exclamationmark.triangle.fill"
                            : done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(blocked ? Theme.warning : done ? Theme.good : Theme.ink3)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.mono(11.5, weight: .medium))
                    .foregroundStyle(Theme.ink1)
                Text(detail)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func hookPurpose(_ event: String) -> String {
        switch event {
        case "PostToolUse":  return "Records each tool call as it completes, for the activity feed."
        case "SessionStart": return "Marks when a session begins, so its length is real."
        case "Stop":         return "Captures the final cost and token totals when a session ends."
        default:             return "Reports \(event) events to Flightdeck."
        }
    }

    // MARK: - Actions

    private func refresh() {
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            status = ClaudeIntegrationInstaller.status(in: [:])
            errorMessage = nil
        case .parsed(let settings):
            status = ClaudeIntegrationInstaller.status(in: settings)
            errorMessage = nil
        case .unreadable(let reason):
            status = nil
            errorMessage = "Can't read \(settingsURL.path): \(reason)\n\nFlightdeck won't modify it until it parses — fix the file, then press Recheck."
        }
        let live = ActivityDatabase.shared?.fetchLiveSessions() ?? []
        liveRowCount = live.count
        lastLiveUpdate = live.map(\.updatedAt).max()
    }

    private func runInstall() {
        perform { binaryPath, settings in
            ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binaryPath)
        }
    }

    private func runUninstall() {
        perform { _, settings in
            ClaudeIntegrationInstaller.applyUninstall(to: settings)
        }
    }

    private func perform(
        _ body: (String, [String: Any]) -> ClaudeIntegrationInstaller.Change
    ) {
        isWorking = true
        errorMessage = nil
        backupPath = nil
        defer { isWorking = false }

        let settings: [String: Any]
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            settings = [:]
        case .parsed(let existing):
            settings = existing
        case .unreadable(let reason):
            // Never write over a file we could not parse: it still holds the user's
            // real configuration, and our output would contain only Flightdeck's keys.
            notes = []
            errorMessage = "Can't read \(settingsURL.path): \(reason)\n\nNothing was changed."
            return
        }

        // Captured before the edit so a concurrent write by Claude Code is detected
        // rather than silently overwritten.
        let baseline = ClaudeIntegrationInstaller.currentBytes(of: settingsURL)
        let binaryPath = ClaudeIntegrationInstaller.installCLIBinary()
        let change = body(binaryPath, settings)
        notes = change.notes.isEmpty ? ["Nothing to change"] : change.notes

        guard change.didChange else {
            refresh()
            return
        }
        do {
            let backup = try ClaudeIntegrationInstaller.write(
                change.settings, to: settingsURL, expecting: baseline
            )
            backupPath = backup?.path
        } catch {
            errorMessage = "Couldn't write \(settingsURL.path): \(error.localizedDescription)"
        }
        refresh()
    }
}
