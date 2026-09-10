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

    /// Reads ~/.claude/settings.json, appends Flightdeck's statusline and hook entries
    /// if not already present, and writes back. Prints what was added.
    private static func handleInstallHooks() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude/settings.json")

        let appSupport = home.appendingPathComponent("Library/Application Support/Flightdeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let targetCLI = appSupport.appendingPathComponent("flightdeck-cli").path

        // Install or update the stable CLI binary at ~/Library/Application Support/Flightdeck/flightdeck-cli
        let currentExecutable = ProcessInfo.processInfo.arguments[0]
        if currentExecutable != targetCLI {
            try? FileManager.default.removeItem(atPath: targetCLI)
            do {
                try FileManager.default.copyItem(atPath: currentExecutable, toPath: targetCLI)
                print("✓ Installed CLI helper → \(targetCLI)")
            } catch {
                print("· Using current binary path: \(currentExecutable)")
            }
        }
        let binaryPath = FileManager.default.fileExists(atPath: targetCLI) ? targetCLI : currentExecutable


        // Read existing settings or start fresh
        var settings: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = [:]
        }

        var changed = false

        // 1. Add statusline if not present
        if settings["statusLine"] == nil {
            settings["statusLine"] = [
                "type": "command",
                "command": "\(binaryPath) statusline",
                "padding": 0,
            ] as [String: Any]
            changed = true
            print("✓ Added statusline → \(binaryPath) statusline")
        } else {
            print("· statusline already configured — skipping")
        }

        // 2. Add hooks if not present
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hookTypes: [(event: String, desc: String)] = [
            ("PostToolUse", "Flightdeck: track tool use in activity feed"),
            ("SessionStart", "Flightdeck: record session start"),
            ("Stop", "Flightdeck: record session stop / cost update"),
        ]

        for hookType in hookTypes {
            var eventHooks = hooks[hookType.event] as? [[String: Any]] ?? []

            // Check if Flightdeck hook already exists
            let alreadyInstalled = eventHooks.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains("flightdeck") == true
                    || ($0["command"] as? String)?.contains("Flightdeck") == true }
            }

            if !alreadyInstalled {
                let hookEntry: [String: Any] = [
                    "matcher": "*",
                    "hooks": [[
                        "type": "command",
                        "command": "\(binaryPath) hook \(hookType.event.lowercased())",
                        "async": true,
                        "timeout": 5,
                    ] as [String: Any]],
                    "description": hookType.desc,
                ]
                eventHooks.append(hookEntry)
                hooks[hookType.event] = eventHooks
                changed = true
                print("✓ Added \(hookType.event) hook")
            } else {
                print("· \(hookType.event) hook already installed — skipping")
            }
        }

        if changed {
            settings["hooks"] = hooks
            do {
                let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: settingsURL, options: .atomic)
                print("\n✓ Settings written to \(settingsURL.path)")
            } catch {
                fputs("✗ Failed to write settings: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print("\n· Nothing to update — Flightdeck hooks already installed.")
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
