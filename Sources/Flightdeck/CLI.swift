import AppKit
import Darwin
import Foundation

/// Headless CLI router for Flightdeck.
/// Handles developer terminal inspection (vitals, ps, sessions, version, help)
/// as well as Claude Code integration hooks and statusline telemetry.
enum CLI {

    static func run(arguments: [String]) -> Never {
        let subcommand = arguments.first?.lowercased() ?? "help"
        let flags = Set(arguments.dropFirst().map { $0.lowercased() })
        let isJson = flags.contains("--json")
        let isDryRun = flags.contains("--dry-run")

        switch subcommand {
        case "help", "-h", "--help":
            handleHelp()

        case "version", "-v", "--version":
            handleVersion(json: isJson)

        case "vitals", "top":
            handleVitals(json: isJson)

        case "ps", "processes":
            handleProcesses(json: isJson)

        case "sessions":
            handleSessions(json: isJson)

        case "statusline":
            handleStatusline()

        case "hook":
            handleHook(arguments: arguments)

        case "install-hooks":
            handleInstallHooks(dryRun: isDryRun)

        default:
            fputs("flightdeck: unknown subcommand or option '\(arguments.first ?? "")'\n\n", stderr)
            fputs("Run 'flightdeck --help' for usage and available commands.\n", stderr)
            exit(1)
        }
        exit(0)
    }

    /// Backwards-compatible router accepting a single subcommand string.
    static func run(subcommand: String) -> Never {
        run(arguments: [subcommand])
    }

    // MARK: - 1. Help & Usage

    private static func handleHelp() -> Never {
        print("""
        ⚡️ Flightdeck 0.1.0 — macOS Activity Monitor & Developer Cockpit

        USAGE:
          flightdeck <command> [options]

        COMMANDS:
          vitals, top            Print live Mach kernel telemetry (CPU, RAM, Disk, Net, GPU)
          ps, processes          List active user applications by memory & CPU usage
          sessions               List locally tracked Claude Code sessions and spend telemetry
          install-hooks          Configure Claude Code statusline & hooks in ~/.claude/settings.json
          statusline             (Internal) Ingest Claude Code statusline JSON via stdin
          hook <event>           (Internal) Ingest Claude Code tool hook JSON via stdin
          version, -v, --version  Print Flightdeck version and architecture
          help, -h, --help        Print this help message

        OPTIONS:
          --json                 Output metrics as structured JSON (vitals, ps, sessions)
          --dry-run              Preview hook changes without writing to disk (install-hooks)

        EXAMPLES:
          flightdeck vitals
          flightdeck vitals --json
          flightdeck ps
          flightdeck sessions
          flightdeck install-hooks --dry-run
        """)
        exit(0)
    }

    // MARK: - 2. Version & Architecture

    private static func handleVersion(json: Bool) -> Never {
        #if arch(arm64)
        let arch = "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        let arch = "x86_64 (Intel)"
        #else
        let arch = "universal"
        #endif

        if json {
            let info: [String: Any] = [
                "version": "0.1.0",
                "architecture": arch,
                "minimumOS": "macOS 14.0 (Sonoma)",
                "runtime": "native Swift / Mach kernel / POSIX"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Flightdeck 0.1.0")
            print("Target: \(arch)")
            print("Requires: macOS 14.0+ (Sonoma, Sequoia)")
        }
        exit(0)
    }

    // MARK: - 3. Live Mach Kernel Telemetry (vitals)

    private static func handleVitals(json: Bool) -> Never {
        let telemetry = SystemTelemetry.shared
        // Prime CPU and I/O counters, sleep 120ms to measure active delta
        _ = telemetry.currentCPUUsage()
        _ = telemetry.currentNetworkThroughputKB()
        _ = telemetry.currentDiskThroughputKB()
        usleep(120_000)

        let cpuUsage = telemetry.currentCPUUsage()
        let perCore = telemetry.currentPerCoreCPU()
        let mem = telemetry.currentMemory()
        let netKB = telemetry.currentNetworkThroughputKB()
        let diskKB = telemetry.currentDiskThroughputKB()
        let gpu = telemetry.currentGPUTelemetry()

        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary

        if json {
            let dict: [String: Any] = [
                "cpu": [
                    "systemPercent": round(cpuUsage * 10) / 10.0,
                    "perCore": perCore.map { round($0 * 10) / 10.0 },
                    "coreCount": perCore.count
                ],
                "memory": [
                    "usedBytes": mem.usedBytes,
                    "totalBytes": mem.totalBytes,
                    "freeBytes": mem.freeBytes,
                    "activeBytes": mem.activeBytes,
                    "wiredBytes": mem.wiredBytes,
                    "compressedBytes": mem.compressedBytes,
                    "usedPercent": round(mem.fraction * 1000) / 10.0
                ],
                "network": [
                    "throughputKBps": round(netKB * 10) / 10.0
                ],
                "disk": [
                    "throughputKBps": round(diskKB * 10) / 10.0
                ],
                "gpu": [
                    "utilizationPercent": round(gpu.utilizationPercent * 10) / 10.0,
                    "memoryBytes": gpu.memoryBytes
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            let usedGB = formatter.string(fromByteCount: mem.usedBytes)
            let totalGB = formatter.string(fromByteCount: mem.totalBytes)
            let freeGB = formatter.string(fromByteCount: mem.freeBytes)
            let wiredGB = formatter.string(fromByteCount: mem.wiredBytes)
            let compressedGB = formatter.string(fromByteCount: mem.compressedBytes)
            let activeGB = formatter.string(fromByteCount: mem.activeBytes)

            print("⚡️ FLIGHTDECK MACH KERNEL TELEMETRY")
            print("───────────────────────────────────────────────────")
            print(String(format: "  CPU Load:        %5.1f%% (%d Cores)", cpuUsage, perCore.count))
            print(String(format: "  Memory:          %@ / %@ (%5.1f%% used)", usedGB, totalGB, mem.fraction * 100))
            print("    ├─ Active:     \(activeGB)")
            print("    ├─ Wired:      \(wiredGB)")
            print("    ├─ Compressed: \(compressedGB)")
            print("    └─ Free:       \(freeGB)")
            print(String(format: "  Network I/O:     %5.1f KB/s", netKB))
            print(String(format: "  Disk Storage:    %5.1f KB/s", diskKB))
            if gpu.utilizationPercent > 0 {
                print(String(format: "  GPU Load:        %5.1f%%", gpu.utilizationPercent))
            }
            print("───────────────────────────────────────────────────")
        }
        exit(0)
    }

    // MARK: - 4. Process Inspection (ps)

    private static func handleProcesses(json: Bool) -> Never {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else {
            fputs("Error: byteCount <= 0\n", stderr)
            exit(0)
        }

        // Prefetch GUI apps once to avoid blocking Mach IPC per PID
        var appMap: [pid_t: (name: String, bundleId: String)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appMap[app.processIdentifier] = (app.localizedName ?? "", app.bundleIdentifier ?? "")
        }

        let numPids = Int(byteCount) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: numPids)
        _ = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, byteCount)

        struct ProcItem {
            let pid: pid_t
            let name: String
            let bundleId: String
            let residentBytes: Int64
        }

        var items: [ProcItem] = []
        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let residentBytes = Int64(info.pti_resident_size)
            guard residentBytes > 10 * 1024 * 1024 else { continue } // Filter processes < 10MB

            var nameBuffer = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuffer, 1024)
            let procName = String(cString: nameBuffer)
            guard !procName.isEmpty else { continue }

            let cached = appMap[pid]
            let displayName = (cached?.name.isEmpty == false) ? cached!.name : procName
            let bundleId = cached?.bundleId ?? ""

            items.append(ProcItem(
                pid: pid,
                name: displayName,
                bundleId: bundleId,
                residentBytes: residentBytes
            ))
        }


        items.sort { $0.residentBytes > $1.residentBytes }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary

        if json {
            let list = items.map { item in
                [
                    "pid": item.pid,
                    "name": item.name,
                    "bundleId": item.bundleId,
                    "memoryBytes": item.residentBytes,
                    "memory": formatter.string(fromByteCount: item.residentBytes)
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("⚡️ FLIGHTDECK ACTIVE PROCESSES (TOP MEMORY)")
            let hPid = "PID".padding(toLength: 7, withPad: " ", startingAt: 0)
            let hName = "PROCESS / APP".padding(toLength: 28, withPad: " ", startingAt: 0)
            let hMem = "MEMORY".padding(toLength: 12, withPad: " ", startingAt: 0)
            print("\(hPid)  \(hName)  \(hMem)  BUNDLE ID")
            print(String(repeating: "─", count: 75))
            for item in items.prefix(25) {
                let memStr = formatter.string(fromByteCount: item.residentBytes)
                let pidStr = "\(item.pid)".padding(toLength: 7, withPad: " ", startingAt: 0)
                let nameStr = String(item.name.prefix(28)).padding(toLength: 28, withPad: " ", startingAt: 0)
                let memPadded = memStr.padding(toLength: 12, withPad: " ", startingAt: 0)
                print("\(pidStr)  \(nameStr)  \(memPadded)  \(item.bundleId)")
            }
            if items.count > 25 {
                print("... and \(items.count - 25) more processes using >10MB RAM.")
            }
        }
        exit(0)
    }

    // MARK: - 5. Claude Sessions Inspection

    private static func handleSessions(json: Bool) -> Never {
        let sessions = ActivityDatabase.shared?.fetchLiveSessions() ?? []

        if json {
            let list = sessions.map { s in
                [
                    "sessionId": s.sessionId,
                    "project": s.project,
                    "branch": s.branch,
                    "model": s.model,
                    "contextTokens": s.contextTokens,
                    "contextTotal": s.contextTotalTokens,
                    "totalCostUsd": s.totalCostUsd,
                    "updatedAt": ISO8601DateFormatter().string(from: s.updatedAt)
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if sessions.isEmpty {
                print("No Claude Code sessions found in Flightdeck's local ledger.")
                print("Tip: Run 'flightdeck install-hooks' to attach telemetry to Claude Code.")
            } else {
                print("⚡️ CLAUDE CODE LIVE SESSIONS (\(sessions.count) TRACKED)")
                let hProj = "PROJECT".padding(toLength: 16, withPad: " ", startingAt: 0)
                let hModel = "MODEL".padding(toLength: 18, withPad: " ", startingAt: 0)
                let hTok = "TOKENS".padding(toLength: 14, withPad: " ", startingAt: 0)
                let hCost = "COST".padding(toLength: 12, withPad: " ", startingAt: 0)
                print("\(hProj)  \(hModel)  \(hTok)  \(hCost)  SESSION ID")
                print(String(repeating: "─", count: 75))
                for s in sessions {
                    let project = String(s.project.prefix(16)).padding(toLength: 16, withPad: " ", startingAt: 0)
                    let model = String(s.model.prefix(18)).padding(toLength: 18, withPad: " ", startingAt: 0)
                    let tokens = "\(Formatters.tokens(s.contextTokens))/\(Formatters.tokens(s.contextTotalTokens))".padding(toLength: 14, withPad: " ", startingAt: 0)
                    let cost = Formatters.usd(s.totalCostUsd).padding(toLength: 12, withPad: " ", startingAt: 0)
                    print("\(project)  \(model)  \(tokens)  \(cost)  \(s.sessionId)")
                }
            }
        }
        exit(0)
    }

    // MARK: - 6. Statusline (Claude Code Internal Ingest)

    /// Claude Code pipes a JSON blob to stdin every ~1-2 seconds containing
    /// session_id, model, total_cost, context_window, cwd, git_branch.
    /// We upsert into the `session_live` GRDB table and exit.
    private static func handleStatusline() {
        guard let data = readStdin(), !data.isEmpty else { exit(0) }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(StatuslinePayload.self, from: data) else {
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

    // MARK: - 7. Hook (Claude Code Internal Ingest)

    /// Claude Code hook events arrive as JSON on stdin with `tool_name`, `tool_input`,
    /// and optionally `tool_output`.
    private static func handleHook(arguments: [String]) {
        let eventType = arguments.count > 1 ? arguments[1] : (CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "unknown")
        guard let data = readStdin(), !data.isEmpty else { exit(0) }

        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let toolName = parsed?["tool_name"] as? String
        let toolInput = parsed?["tool_input"] as? [String: Any]

        var detail: String?
        if let filePath = toolInput?["file_path"] as? String {
            detail = URL(fileURLWithPath: filePath).lastPathComponent
        } else if let command = toolInput?["command"] as? String {
            detail = String(command.prefix(80))
        }

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

    // MARK: - 8. Install Hooks

    /// Applies Flightdeck's statusline and hook entries to ~/.claude/settings.json.
    private static func handleInstallHooks(dryRun: Bool) {
        let binaryPath = ClaudeIntegrationInstaller.installCLIBinary()
        let settingsURL = ClaudeIntegrationInstaller.defaultSettingsURL()

        let settings: [String: Any]
        switch ClaudeIntegrationInstaller.readSettings(from: settingsURL) {
        case .missing:
            settings = [:]
        case .parsed(let existing):
            settings = existing
        case .unreadable(let reason):
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

        if dryRun {
            print("\n[DRY RUN] Would update \(settingsURL.path) with statusline and hook triggers.")
            print("[DRY RUN] No files modified on disk.")
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
