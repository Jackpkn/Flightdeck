import Foundation

/// Headless CLI router for Flightdeck. Invoked by Claude Code's statusline and hooks —
/// the user never runs these subcommands manually. Each subcommand reads JSON from stdin,
/// writes to GRDB, and exits. No GUI, no RunLoop, no AppKit.
enum CLI {

    static func run(subcommand: String) -> Never {
        switch subcommand {
        case "statusline":
            handleStatusline()
            // handleStatusline calls exit() internally
        case "hook":
            handleHook()
            // handleHook calls exit() internally
        case "install-hooks":
            handleInstallHooks()
            // handleInstallHooks calls exit() internally
        default:
            fputs("flightdeck: unknown subcommand '\(subcommand)'\n", stderr)
            fputs("usage: flightdeck [statusline | hook | install-hooks]\n", stderr)
            exit(1)
        }
        exit(0)
    }

    // MARK: - Statusline

    /// Claude Code pipes a JSON blob to stdin every ~1-2 seconds containing
    /// session_id, model, total_cost, context_window, cwd, git_branch.
    /// We upsert into the `session_live` GRDB table and exit.
    private static func handleStatusline() {
        guard let data = readStdin(), !data.isEmpty else { exit(0) }

        let decoder = JSONDecoder()
        // Claude Code's statusline JSON uses flexible date formats — we decode dates manually
        guard let payload = try? decoder.decode(StatuslinePayload.self, from: data) else {
            // Silently exit — malformed input shouldn't crash or log spam
            exit(0)
        }

        guard let sessionId = payload.session_id, !sessionId.isEmpty else { exit(0) }

        let project: String
        if let cwd = payload.cwd, !cwd.isEmpty {
            project = URL(fileURLWithPath: cwd).lastPathComponent
        } else {
            project = ""
        }

        let record = SessionLiveRecord(
            sessionId: sessionId,
            project: project,
            branch: payload.git_branch ?? "",
            model: payload.model ?? "",
            contextTokens: payload.context_window?.used ?? 0,
            contextTotalTokens: payload.context_window?.total ?? 200_000,
            totalCostUsd: payload.total_cost ?? 0,
            lastFile: "",
            updatedAt: Date()
        )

        ActivityDatabase.shared?.upsertSession(record)
        exit(0)
    }

    // MARK: - Hook

    /// Claude Code hook events arrive as JSON on stdin with `tool_name`, `tool_input`,
    /// and optionally `tool_output`. The event type is passed as the second CLI argument
    /// (e.g. `flightdeck hook post-tool-use`).
    private static func handleHook() {
        let eventType = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "unknown"
        guard let data = readStdin(), !data.isEmpty else { exit(0) }

        // Parse the hook payload — we only need a few fields
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        let toolName = parsed?["tool_name"] as? String
        let toolInput = parsed?["tool_input"] as? [String: Any]

        // Extract a useful detail string
        var detail: String?
        if let filePath = toolInput?["file_path"] as? String {
            detail = URL(fileURLWithPath: filePath).lastPathComponent
        } else if let command = toolInput?["command"] as? String {
            detail = String(command.prefix(80))
        }

        // We need a session ID — try to extract from the hook payload
        // Claude Code hooks include session_id at the top level
        let sessionId = parsed?["session_id"] as? String ?? "unknown"

        let record = AIEventRecord(
            id: nil,
            sessionId: sessionId,
            event: eventType,
            toolName: toolName,
            detail: detail,
            timestamp: Date()
        )

        ActivityDatabase.shared?.insertEvent(record)
        exit(0)
    }

    // MARK: - Install Hooks

    /// Applies Flightdeck's statusline and hook entries to ~/.claude/settings.json.
    /// The GUI setup sheet drives the same `ClaudeIntegrationInstaller`, so there is
    /// exactly one implementation of what "installed" means.
    private static func handleInstallHooks() {
        let binaryPath = ClaudeIntegrationInstaller.installCLIBinary()
        let settingsURL = ClaudeIntegrationInstaller.defaultSettingsURL()

        let settings: [String: Any]
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            settings = [:]
        case .parsed(let existing):
            settings = existing
        case .unreadable(let reason):
            // The file exists and holds real configuration we simply could not parse.
            // Writing now would replace all of it with Flightdeck's keys alone.
            fputs("Refusing to modify \(settingsURL.path): \(reason)\n", stderr)
            exit(1)
        }

        let baseline = ClaudeIntegrationInstaller.currentBytes(of: settingsURL)
        let change = ClaudeIntegrationInstaller.applyInstall(to: settings, binaryPath: binaryPath)

        for note in change.notes { print("· \(note)") }

        guard change.didChange else {
            print("\nNothing to update — Flightdeck is already installed.")
            exit(0)
        }

        do {
            let backup = try ClaudeIntegrationInstaller.write(
                change.settings, to: settingsURL, expecting: baseline
            )
            if let backup {
                print("\nBacked up your previous settings → \(backup.path)")
            }
            print("Settings written to \(settingsURL.path)")
        } catch {
            fputs("Failed to write settings: \(error)\n", stderr)
            exit(1)
        }
        exit(0)
    }

    // MARK: - Helpers

    private static func readStdin() -> Data? {
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 8192)
        defer { buf.deallocate() }
        while true {
            let count = fread(buf, 1, 8192, stdin)
            if count == 0 { break }
            data.append(buf, count: count)
        }
        return data.isEmpty ? nil : data
    }
}
