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

        case "vitals":
            handleVitals(json: isJson)

        case "top":
            handleTop(flags: flags)

        case "ps", "processes":
            handleProcesses(json: isJson)

        case "ports", "port":
            handlePorts(flags: flags, arguments: arguments)

        case "kill-port":
            handleKillPort(arguments: arguments)

        case "clean", "cruft":
            handleClean(flags: flags)

        case "zombies", "zombie":
            handleZombies(flags: flags)

        case "kill-zombies":
            handleZombies(flags: flags, autoKill: true)

        case "mcp", "mcpservers", "mcp-servers":
            handleMCP(flags: flags, arguments: arguments)

        case "sessions":
            handleSessions(json: isJson)

        case "session", "replay":
            handleSessionReplay(flags: flags, arguments: arguments)

        case "tail":
            handleSessionReplay(flags: flags.union(["--tail"]), arguments: arguments)

        case "hotspots", "churn":
            handleHotspots(flags: flags, arguments: arguments)

        case "prune":
            handlePrune(flags: flags, arguments: arguments)

        case "redact":
            handleRedact(arguments: arguments)

        case "report", "postmortem", "export":
            handleReport(flags: flags, arguments: arguments)

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
        ⚡️ Flightdeck 0.2.0 — macOS Activity Monitor & Developer Cockpit

        USAGE:
          flightdeck <command> [options]

        COMMANDS:
          top                     Interactive real-time terminal HUD streaming CPU, RAM, ports & spend
          vitals                  Print immediate Mach kernel telemetry snapshot (CPU, RAM, Disk, Net)
          ps, processes           List active user applications by memory & CPU usage
          ports, port             List listening TCP ports with process names & PIDs
          kill-port <port>        Terminate process hogging a port (e.g. 3000, 8080)
          clean, cruft            Scan & reclaim disk space from developer caches (Xcode, SPM, NPM)
          zombies, zombie         Detect runaway orphaned developer background processes
          kill-zombies            Terminate all orphaned zombie processes to free RAM
          mcp, mcpservers         List configured & running Model Context Protocol (MCP) servers
          sessions                List locally tracked Claude Code sessions and spend telemetry
          session, replay [id]    Inspect turns, tools used, and tokens for a Claude Code session
          tail [session-id]       Stream live conversation turns and tool calls as they occur
          hotspots, churn         Detect files repeatedly rewritten across sessions with diagnosis
          report [session-id]     Export Markdown or JSON post-mortem of a Claude Code session
          prune                   Prune historical telemetry and SQLite database to reclaim disk
          redact [text]           Scrub secrets, API keys, and bearer tokens from text or stdin
          install-hooks           Configure Claude Code statusline & hooks in ~/.claude/settings.json
          version, -v, --version  Print Flightdeck version and architecture
          help, -h, --help        Print this help message

        OPTIONS:
          --json                  Output metrics as structured JSON
          --once                  Single non-interactive snapshot for 'top'
          --tail, -f              Stream newly appended turns live for 'session'
          --verbose, -v           Display complete prompts and tool outputs for 'session'
          --ping, --test          Run JSON-RPC 2.0 handshake and benchmark latency for 'mcp'
          --output <file>         Write post-mortem report to specified path for 'report'
          --dev-only              Filter to developer ports (< 49152) for 'ports'
          --dry-run               Preview changes without executing (install-hooks, clean, prune)
          --days <N>              Retention window in days for 'prune' (default 14)
          --limit <N>             Maximum items to display for 'hotspots' (default 20)
          --vacuum                Reclaim disk space with SQLite VACUUM for 'prune'
          --force, -f             Purge caches immediately without confirmation for 'clean'
          --kill, -k              Terminate detected zombie processes for 'zombies'

        EXAMPLES:
          flightdeck top
          flightdeck top --once
          flightdeck vitals
          flightdeck ports --dev-only
          flightdeck kill-port 3000
          flightdeck clean --dry-run
          flightdeck clean --force
          flightdeck zombies --kill
          flightdeck mcp
          flightdeck mcp ping
          flightdeck mcp --ping
          flightdeck sessions
          flightdeck session
          flightdeck session --verbose
          flightdeck tail
          flightdeck hotspots
          flightdeck report --output postmortem.md
          flightdeck prune --days 14 --vacuum
          echo "sk-ant-api03-..." | flightdeck redact
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
                "version": "0.2.0",
                "architecture": arch,
                "minimumOS": "macOS 14.0 (Sonoma)",
                "runtime": "native Swift / Mach kernel / POSIX"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Flightdeck 0.2.0")
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

    // MARK: - 3. Interactive Terminal Top Cockpit

    private static func handleTop(flags: Set<String>) -> Never {
        let isOnce = flags.contains("--once")
        let isJson = flags.contains("--json")

        if isJson {
            handleVitals(json: true)
        }

        let telemetry = SystemTelemetry.shared

        // Signal handler to restore cursor on Ctrl+C
        signal(SIGINT) { _ in
            fputs("\u{001B}[?25h\n", stdout)
            exit(0)
        }

        // Hide cursor for smooth terminal updates
        fputs("\u{001B}[?25l", stdout)

        repeat {
            // Sample telemetry with brief interval
            _ = telemetry.currentCPUUsage()
            _ = telemetry.currentNetworkThroughputKB()
            _ = telemetry.currentDiskThroughputKB()
            usleep(120_000)

            let cpuPercent = telemetry.currentCPUUsage()
            let perCore = telemetry.currentPerCoreCPU()
            let mem = telemetry.currentMemory()
            let netKB = telemetry.currentNetworkThroughputKB()
            let diskKB = telemetry.currentDiskThroughputKB()
            let gpu = telemetry.currentGPUTelemetry()

            // Fetch listening ports (< 49152)
            let ports = PortScanner.fetchListeningPorts().filter(\.isDevPort)

            // Fetch live sessions
            let liveSessions = ActivityDatabase.shared?.fetchLiveSessions() ?? []

            // Clear screen & home cursor
            fputs("\u{001B}[2J\u{001B}[H", stdout)

            let nowStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            print("┌──────────────────────────────────────────────────────────────────────────────┐")
            print("│ ⚡️ FLIGHTDECK COCKPIT TOP ── \(nowStr) ── (Ctrl+C to exit)                    │")
            print("└──────────────────────────────────────────────────────────────────────────────┘")

            // CPU Gauge
            let cpuBar = progressBar(fraction: cpuPercent / 100.0, width: 24)
            print("  CPU Usage:     \(cpuBar) \(String(format: "%5.1f%%", cpuPercent)) (\(perCore.count) cores)")

            // Memory Gauge
            let memFraction = mem.totalBytes > 0 ? Double(mem.usedBytes) / Double(mem.totalBytes) : 0
            let memBar = progressBar(fraction: memFraction, width: 24)
            let usedGB = String(format: "%.1f", Double(mem.usedBytes) / 1_073_741_824)
            let totalGB = String(format: "%.1f GB", Double(mem.totalBytes) / 1_073_741_824)
            print("  Physical RAM:  \(memBar) \(usedGB)/\(totalGB) (\(Int(memFraction * 100))%)")

            // I/O & GPU
            let netStr = "\(Formatters.bytes(Int64(netKB * 1024)))/s".padding(toLength: 12, withPad: " ", startingAt: 0)
            let diskStr = "\(Formatters.bytes(Int64(diskKB * 1024)))/s".padding(toLength: 12, withPad: " ", startingAt: 0)
            print("  Network:       \(netStr)  Disk I/O: \(diskStr)  GPU: \(Int(gpu.utilizationPercent))%")
            print("  " + String(repeating: "─", count: 76))

            // Active Listening Ports Section
            print("  LISTENING DEVELOPER PORTS:")
            if ports.isEmpty {
                print("  └─ No developer server ports active (< 49152)")
            } else {
                for p in ports.prefix(4) {
                    let portStr = ":\(p.port)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    let procStr = p.processName.padding(toLength: 18, withPad: " ", startingAt: 0)
                    print("  └─ \(portStr) \(procStr) (PID \(p.pid))")
                }
            }
            print("  " + String(repeating: "─", count: 76))

            // Active Claude Code Sessions Section
            print("  CLAUDE CODE LIVE SESSIONS:")
            if liveSessions.isEmpty {
                print("  └─ No active sessions in local ledger (Run 'flightdeck install-hooks')")
            } else {
                for s in liveSessions.prefix(3) {
                    let proj = (s.project.isEmpty ? s.sessionId : s.project).padding(toLength: 16, withPad: " ", startingAt: 0)
                    let model = s.model.padding(toLength: 14, withPad: " ", startingAt: 0)
                    let tok = "\(Formatters.tokens(s.contextTokens)) tok".padding(toLength: 12, withPad: " ", startingAt: 0)
                    let cost = Formatters.usd(s.totalCostUsd)
                    print("  └─ \(proj) \(model) \(tok) \(cost)")
                }
            }
            print("  " + String(repeating: "─", count: 76))

            if isOnce {
                fputs("\u{001B}[?25h", stdout)
                exit(0)
            }

            usleep(880_000)
        } while true
    }

    private static func progressBar(fraction: Double, width: Int) -> String {
        let clamped = max(0, min(1, fraction))
        let filled = Int(clamped * Double(width))
        let empty = max(0, width - filled)
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
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

    // MARK: - 5b. Claude Session Replay & Live Tail

    private static func handleSessionReplay(flags: Set<String>, arguments: [String]) -> Never {
        let isJson = flags.contains("--json")
        let isVerbose = flags.contains("--verbose") || flags.contains("-v")
        let isTail = flags.contains("--tail") || flags.contains("-f")

        let targetId = arguments.dropFirst().first { !$0.hasPrefix("-") }
        let sessions = DashboardStore.loadSessionsSync()

        let session: SessionAgg?
        let sessionFile: URL?

        if let targetId {
            session = sessions.first(where: { $0.id == targetId || $0.id.hasPrefix(targetId) })
            let actualId = session?.id ?? targetId
            sessionFile = ClaudeTranscriptReader.locateTranscriptFile(sessionId: actualId)
        } else {
            session = sessions.sorted(by: { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }).first
            if let sid = session?.id {
                sessionFile = ClaudeTranscriptReader.locateTranscriptFile(sessionId: sid)
            } else {
                sessionFile = nil
            }
        }

        guard let fileURL = sessionFile, FileManager.default.fileExists(atPath: fileURL.path) else {
            fputs("flightdeck: transcript file not found for session.\n", stderr)
            fputs("Check available sessions with 'flightdeck sessions'.\n", stderr)
            exit(1)
        }

        let turns = ClaudeTranscriptReader.parseTurns(from: fileURL)

        if isJson {
            let dict = ClaudeSessionReplay.turnsToJSON(turns: turns, session: session)
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            exit(0)
        }

        if isTail {
            print("⚡️ STREAMING CLAUDE CODE TRANSCRIPT: \(fileURL.lastPathComponent) (Ctrl+C to exit)\n")
            var printedCount = 0
            for turn in turns {
                print(ClaudeSessionReplay.formatTurn(turn, verbose: isVerbose))
                printedCount += 1
            }

            // Polling loop watching file for appended turns
            while true {
                usleep(850_000)
                let latestTurns = ClaudeTranscriptReader.parseTurns(from: fileURL)
                if latestTurns.count > printedCount {
                    for i in printedCount..<latestTurns.count {
                        print(ClaudeSessionReplay.formatTurn(latestTurns[i], verbose: isVerbose))
                    }
                    printedCount = latestTurns.count
                }
            }
        } else {
            let output = ClaudeSessionReplay.formatSessionReplay(turns: turns, session: session, verbose: isVerbose)
            print(output)
            exit(0)
        }
    }

    // MARK: - Hotspot Churn & Agent Diagnostics

    private static func handleHotspots(flags: Set<String>, arguments: [String]) -> Never {
        let isJson = flags.contains("--json")
        let limitArg = arguments.firstIndex(of: "--limit").flatMap { idx in
            idx + 1 < arguments.count ? Int(arguments[idx + 1]) : nil
        } ?? 20

        // Synchronously load transcripts and active sessions
        let sessions = DashboardStore.loadSessionsSync()
        let spots = ChurnAnalyzer.hotspots(in: sessions, limit: limitArg)

        if isJson {
            let list = spots.map { spot in
                [
                    "path": spot.path,
                    "fileName": spot.fileName,
                    "sessionCount": spot.sessionCount,
                    "projects": spot.projects,
                    "diagnosis": spot.diagnosis.rawValue,
                    "advice": spot.suggestedAction
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            exit(0)
        }

        print("""
        ┌───────────────────────────────────────────────────────────────────────────────┐
        │  🔥 Flightdeck Churn Hotspots & Agent Diagnostics                             │
        └───────────────────────────────────────────────────────────────────────────────┘
        """)

        if spots.isEmpty {
            print("  No files have been rewritten across multiple Claude Code sessions yet.\n")
            print("  Tip: As Claude Code edits files across sessions, Flightdeck automatically")
            print("  detects churn oscillation, missing CLAUDE.md instructions, and task splits.\n")
            exit(0)
        }

        let hFile = "FILE".padding(toLength: 28, withPad: " ", startingAt: 0)
        let hChurn = "CHURN".padding(toLength: 7, withPad: " ", startingAt: 0)
        let hDiag = "DIAGNOSIS".padding(toLength: 26, withPad: " ", startingAt: 0)
        print("  \(hFile)  \(hChurn)  \(hDiag)")
        print("  " + String(repeating: "─", count: 75))

        for spot in spots {
            let fileDisplay = (spot.fileName.count > 28 ? String(spot.fileName.prefix(25)) + "..." : spot.fileName)
                .padding(toLength: 28, withPad: " ", startingAt: 0)
            let churnDisplay = "\(spot.sessionCount)×".padding(toLength: 7, withPad: " ", startingAt: 0)
            let diagDisplay = spot.diagnosis.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0)
            print("  \(fileDisplay)  \(churnDisplay)  \(diagDisplay)")
            print("  └─ Path: \(spot.path)")
            print("     Advice: \(spot.suggestedAction)")
            print("")
        }
        exit(0)
    }

    // MARK: - Retention & Pruning

    private static func handlePrune(flags: Set<String>, arguments: [String]) -> Never {
        let isDryRun = flags.contains("--dry-run")
        let shouldVacuum = flags.contains("--vacuum")
        let daysArg = arguments.firstIndex(of: "--days").flatMap { idx in
            idx + 1 < arguments.count ? Int(arguments[idx + 1]) : nil
        } ?? 14

        guard let db = ActivityDatabase.shared else {
            fputs("flightdeck: could not open local SQLite activity database.\n", stderr)
            exit(1)
        }

        let sizeBefore = db.databaseSizeBytes()
        print("""
        ┌───────────────────────────────────────────────────────────────────────────────┐
        │  🧹 Flightdeck SQLite Retention & Storage Pruning                             │
        └───────────────────────────────────────────────────────────────────────────────┘
        """)
        print("  Current database size: \(Formatters.bytes(sizeBefore))")
        print("  Retention cutoff:      Older than \(daysArg) days")

        if isDryRun {
            print("  Mode:                  Dry Run (no records deleted)")
            print("  Run 'flightdeck prune --days \(daysArg) --vacuum' to execute.\n")
            exit(0)
        }

        do {
            let result = try db.prune(olderThanDays: daysArg, vacuumAfter: shouldVacuum)
            let sizeAfter = db.databaseSizeBytes()
            print("  ✓ Pruned \(result.deletedActivityCount) app activity records")
            print("  ✓ Pruned \(result.deletedEventsCount) AI hook events")
            print("  ✓ Pruned \(result.deletedLiveSessionsCount) stale live sessions")
            print("  New database size:     \(Formatters.bytes(sizeAfter))")
            if result.bytesReclaimed > 0 {
                print("  Reclaimed disk space:  \(Formatters.bytes(result.bytesReclaimed))")
            }
            print("")
        } catch {
            fputs("flightdeck prune failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        exit(0)
    }

    // MARK: - Secret Redaction CLI

    private static func handleRedact(arguments: [String]) -> Never {
        let textArgs = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let input: String
        if !textArgs.isEmpty {
            input = textArgs.joined(separator: " ")
        } else {
            // Read from standard input (e.g. piped text)
            let data = FileHandle.standardInput.readDataToEndOfFile()
            input = String(data: data, encoding: .utf8) ?? ""
        }

        let redacted = SecretRedactor.shared.redact(input)
        print(redacted, terminator: input.hasSuffix("\n") ? "" : "\n")
        exit(0)
    }

    // MARK: - Session Post-Mortem Report Exporter

    private static func handleReport(flags: Set<String>, arguments: [String]) -> Never {
        let isJson = flags.contains("--json")
        let outputPath = arguments.firstIndex(of: "--output").flatMap { idx in
            idx + 1 < arguments.count ? arguments[idx + 1] : nil
        }

        let targetSessionId = arguments.dropFirst().first { !$0.hasPrefix("-") }
        let sessions = DashboardStore.loadSessionsSync()

        let session: SessionAgg
        if let targetId = targetSessionId {
            guard let found = sessions.first(where: { $0.id == targetId || $0.id.hasPrefix(targetId) }) else {
                fputs("flightdeck: session '\(targetId)' not found in local transcripts.\n", stderr)
                exit(1)
            }
            session = found
        } else {
            guard let latest = sessions.sorted(by: { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }).first else {
                fputs("flightdeck: no Claude Code sessions found to generate a report.\n", stderr)
                exit(1)
            }
            session = latest
        }

        // Compute Git outcome if session has working directory
        let outcome: GitOutcome?
        if !session.cwd.isEmpty, !session.filesModified.isEmpty {
            outcome = GitOutcomeProbe.probe(
                cwd: session.cwd,
                files: session.filesModified,
                since: session.startedAt,
                until: session.lastSeen
            )
        } else {
            outcome = nil
        }

        let hotspots = ChurnAnalyzer.hotspots(in: sessions)
        let waste = WasteReport(sessions: [session])

        if isJson {
            let dict = SessionReportGenerator.generateJSON(session: session, outcome: outcome, hotspots: hotspots)
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                if let outputPath {
                    try? str.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    print("✓ JSON post-mortem written to \(outputPath)")
                } else {
                    print(str)
                }
            }
            exit(0)
        }

        let markdown = SessionReportGenerator.generateMarkdown(
            session: session,
            outcome: outcome,
            hotspots: hotspots,
            waste: waste
        )

        if let outputPath {
            do {
                try markdown.write(toFile: outputPath, atomically: true, encoding: .utf8)
                print("✓ Post-mortem report written to \(outputPath)")
            } catch {
                fputs("flightdeck: could not write report to \(outputPath): \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            print(markdown)
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

    // MARK: - 9. Listening Ports & Freeing

    private static func handlePorts(flags: Set<String>, arguments: [String]) -> Never {
        let isJson = flags.contains("--json")
        let devOnly = flags.contains("--dev-only") || flags.contains("--dev")

        var ports = PortScanner.fetchListeningPorts()
        if devOnly {
            ports = ports.filter(\.isDevPort)
        }

        if isJson {
            let list = ports.map { p in
                [
                    "port": p.port,
                    "pid": p.pid,
                    "process": p.processName,
                    "address": p.address,
                    "isDevPort": p.isDevPort
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if ports.isEmpty {
                print("No listening TCP ports found\(devOnly ? " (dev-only filter active)" : "").")
            } else {
                print("⚡️ FLIGHTDECK LISTENING TCP PORTS (\(ports.count) ACTIVE)")
                let hPort = "PORT".padding(toLength: 7, withPad: " ", startingAt: 0)
                let hPid = "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
                let hProcess = "PROCESS".padding(toLength: 22, withPad: " ", startingAt: 0)
                let hAddr = "ADDRESS".padding(toLength: 18, withPad: " ", startingAt: 0)
                print("\(hPort)  \(hPid)  \(hProcess)  \(hAddr)  KIND")
                print(String(repeating: "─", count: 68))
                for p in ports {
                    let portStr = "\(p.port)".padding(toLength: 7, withPad: " ", startingAt: 0)
                    let pidStr = "\(p.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    let procStr = String(p.processName.prefix(22)).padding(toLength: 22, withPad: " ", startingAt: 0)
                    let addrStr = String(p.address.prefix(18)).padding(toLength: 18, withPad: " ", startingAt: 0)
                    let kindStr = p.isDevPort ? "DEV" : "SYSTEM"
                    print("\(portStr)  \(pidStr)  \(procStr)  \(addrStr)  \(kindStr)")
                }
                print("────────────────────────────────────────────────────────────────────")
                print("Tip: Run 'flightdeck kill-port <port>' to free a blocked port.")
            }
        }
        exit(0)
    }

    private static func handleKillPort(arguments: [String]) -> Never {
        let targetArgs = arguments.filter { !$0.hasPrefix("-") }
        guard targetArgs.count >= 2, let portNum = Int(targetArgs[1]) else {
            fputs("Error: Missing or invalid port number.\n\n", stderr)
            fputs("Usage: flightdeck kill-port <port>\n", stderr)
            fputs("Example: flightdeck kill-port 3000\n", stderr)
            exit(1)
        }

        let result = PortScanner.killPort(portNum)
        if result.success {
            print("⚡️ \(result.message)")
            exit(0)
        } else {
            fputs("❌ \(result.message)\n", stderr)
            exit(1)
        }
    }

    // MARK: - 10. Developer Cruft & Cache Cleaner

    private static func handleClean(flags: Set<String>) -> Never {
        let isJson = flags.contains("--json")
        let isDryRun = flags.contains("--dry-run")
        let isForce = flags.contains("--force") || flags.contains("-f")

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let categories = DevCleaner.scanSynchronously()
        let nonRAM = categories.filter { !$0.isRAM }
        let totalBytes = nonRAM.reduce(0) { $0 + $1.sizeBytes }

        if isForce && !isDryRun {
            let freedBytes = DevCleaner.purgeSynchronously(categories: categories)
            if isJson {
                let dict: [String: Any] = [
                    "purged": true,
                    "reclaimedBytes": freedBytes,
                    "reclaimed": formatter.string(fromByteCount: freedBytes)
                ]
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("⚡️ FLIGHTDECK DEVELOPER CRUFT PURGED")
                print("Reclaimed \(formatter.string(fromByteCount: freedBytes)) across \(nonRAM.count) developer cache targets.")
            }
            exit(0)
        }

        if isJson {
            let list = nonRAM.map { c in
                [
                    "id": c.id,
                    "name": c.name,
                    "sizeBytes": c.sizeBytes,
                    "size": formatter.string(fromByteCount: c.sizeBytes),
                    "path": c.path.path
                ] as [String: Any]
            }
            let dict: [String: Any] = [
                "dryRun": isDryRun,
                "totalReclaimableBytes": totalBytes,
                "totalReclaimable": formatter.string(fromByteCount: totalBytes),
                "targets": list
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            let header = isDryRun ? "⚡️ FLIGHTDECK DEVELOPER CRUFT SCAN (DRY RUN)" : "⚡️ FLIGHTDECK DEVELOPER CRUFT DISCOVERY"
            print(header)
            let hName = "TARGET / CACHE".padding(toLength: 26, withPad: " ", startingAt: 0)
            let hSize = "RECLAIMABLE".padding(toLength: 14, withPad: " ", startingAt: 0)
            print("\(hName)  \(hSize)  PATH")
            print(String(repeating: "─", count: 75))
            for cat in nonRAM {
                let nameStr = String(cat.name.prefix(26)).padding(toLength: 26, withPad: " ", startingAt: 0)
                let sizeStr = formatter.string(fromByteCount: cat.sizeBytes).padding(toLength: 14, withPad: " ", startingAt: 0)
                let tildePath = cat.path.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                print("\(nameStr)  \(sizeStr)  \(tildePath)")
            }
            print("───────────────────────────────────────────────────────────────────────────")
            print("Total Reclaimable Space: \(formatter.string(fromByteCount: totalBytes))")
            if !isForce {
                print("\nRun 'flightdeck clean --force' to purge these caches and reclaim disk space.")
            }
        }
        exit(0)
    }

    // MARK: - 11. Runaway Zombie & Orphan Processes

    private static func handleZombies(flags: Set<String>, autoKill: Bool = false) -> Never {
        let isJson = flags.contains("--json")
        let shouldKill = autoKill || flags.contains("--kill") || flags.contains("-k")

        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory

        let orphans = ZombieDetector.discoverOrphans()
        let totalMemory = orphans.reduce(0) { $0 + $1.memoryBytes }

        if shouldKill && !orphans.isEmpty {
            let killed = ZombieDetector.killAllSync(orphans: orphans)
            if isJson {
                let dict: [String: Any] = [
                    "killed": true,
                    "terminatedCount": killed,
                    "reclaimedBytes": totalMemory,
                    "reclaimed": formatter.string(fromByteCount: totalMemory)
                ]
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("⚡️ FLIGHTDECK ZOMBIE PURGE COMPLETE")
                print("Terminated \(killed) runaway orphaned developer processes.")
                print("Reclaimed ~\(formatter.string(fromByteCount: totalMemory)) of leaked memory.")
            }
            exit(0)
        }

        if isJson {
            let list = orphans.map { o in
                [
                    "pid": o.pid,
                    "name": o.name,
                    "path": o.path,
                    "memoryBytes": o.memoryBytes,
                    "memory": formatter.string(fromByteCount: o.memoryBytes),
                    "isZombie": o.isZombie
                ] as [String: Any]
            }
            let dict: [String: Any] = [
                "count": orphans.count,
                "totalMemoryBytes": totalMemory,
                "totalMemory": formatter.string(fromByteCount: totalMemory),
                "orphans": list
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if orphans.isEmpty {
                print("⚡️ No runaway orphaned developer processes detected.")
                print("All developer background tasks have active controlling terminals.")
            } else {
                print("⚡️ RUNAWAY ORPHANED DEVELOPER PROCESSES (\(orphans.count) FOUND)")
                let hPid = "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
                let hName = "PROCESS".padding(toLength: 20, withPad: " ", startingAt: 0)
                let hMem = "MEMORY".padding(toLength: 12, withPad: " ", startingAt: 0)
                print("\(hPid)  \(hName)  \(hMem)  PATH")
                print(String(repeating: "─", count: 75))
                for o in orphans {
                    let pidStr = "\(o.pid)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    let nameStr = String(o.name.prefix(20)).padding(toLength: 20, withPad: " ", startingAt: 0)
                    let memStr = formatter.string(fromByteCount: o.memoryBytes).padding(toLength: 12, withPad: " ", startingAt: 0)
                    print("\(pidStr)  \(nameStr)  \(memStr)  \(o.path)")
                }
                print("───────────────────────────────────────────────────────────────────────────")
                print("Total Leaked Memory: \(formatter.string(fromByteCount: totalMemory))")
                print("\nTip: Run 'flightdeck zombies --kill' or 'flightdeck kill-zombies' to terminate all.")
            }
        }
        exit(0)
    }

    // MARK: - 12. Model Context Protocol (MCP) Servers & Diagnostic Probe

    private static func handleMCP(flags: Set<String>, arguments: [String] = []) -> Never {
        let isJson = flags.contains("--json")
        let isPing = flags.contains("--ping") || flags.contains("--test") || arguments.dropFirst().first == "ping" || arguments.dropFirst().first == "test"
        let pingTarget = arguments.dropFirst().filter { $0 != "ping" && $0 != "test" && !$0.hasPrefix("-") }.first

        let servers = MCPServerScanner.scanAllSync()

        if isPing {
            let targets: [MCPServerItem]
            if let pingTarget {
                targets = servers.filter { $0.name.lowercased().contains(pingTarget.lowercased()) || $0.id.lowercased().contains(pingTarget.lowercased()) }
                if targets.isEmpty {
                    fputs("flightdeck: no MCP server found matching '\(pingTarget)'.\n", stderr)
                    exit(1)
                }
            } else {
                targets = servers
            }

            if targets.isEmpty {
                print("No Model Context Protocol (MCP) servers configured to probe.")
                exit(0)
            }

            var results: [MCPPingResult] = []
            for s in targets {
                let res = MCPPingProbe.probe(server: s)
                results.append(res)
            }

            if isJson {
                let list = results.map { r in
                    [
                        "serverName": r.serverName,
                        "source": r.source,
                        "isHealthy": r.isHealthy,
                        "latencyMs": r.latencyMs,
                        "protocolVersion": r.protocolVersion as Any,
                        "serverTitle": r.serverTitle as Any,
                        "serverVersion": r.serverVersion as Any,
                        "error": r.errorDescription as Any
                    ] as [String: Any]
                }
                if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("⚡️ FLIGHTDECK MCP DIAGNOSTIC PING & HEALTH PROBE (\(results.count) PROBED)")
                let hName = "SERVER NAME".padding(toLength: 24, withPad: " ", startingAt: 0)
                let hStatus = "STATUS".padding(toLength: 10, withPad: " ", startingAt: 0)
                let hLatency = "LATENCY".padding(toLength: 10, withPad: " ", startingAt: 0)
                let hProto = "PROTOCOL".padding(toLength: 14, withPad: " ", startingAt: 0)
                print("\(hName)  \(hStatus)  \(hLatency)  \(hProto)  DETAILS / DIAGNOSTICS")
                print(String(repeating: "─", count: 80))

                for r in results {
                    let nameStr = String(r.serverName.prefix(24)).padding(toLength: 24, withPad: " ", startingAt: 0)
                    let statusStr = (r.isHealthy ? "✓ PASS" : "❌ FAIL").padding(toLength: 10, withPad: " ", startingAt: 0)
                    let latStr = (r.latencyMs > 0 ? "\(String(format: "%.1f", r.latencyMs))ms" : "-").padding(toLength: 10, withPad: " ", startingAt: 0)
                    let protoStr = (r.protocolVersion ?? "-").padding(toLength: 14, withPad: " ", startingAt: 0)
                    let detail = r.isHealthy ? (r.serverVersion ?? "OK") : (r.errorDescription ?? "Error")
                    print("\(nameStr)  \(statusStr)  \(latStr)  \(protoStr)  \(detail)")
                }
            }
            exit(0)
        }

        if isJson {
            let list = servers.map { s in
                [
                    "id": s.id,
                    "name": s.name,
                    "status": s.status.rawValue,
                    "source": s.source.rawValue,
                    "pid": s.pid as Any,
                    "cpuPercent": s.cpuPercent,
                    "memoryBytes": s.memoryBytes,
                    "tools": s.toolsExposed,
                    "command": s.command
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if servers.isEmpty {
                print("No Model Context Protocol (MCP) servers found across Claude or project configurations.")
            } else {
                print("⚡️ FLIGHTDECK MODEL CONTEXT PROTOCOL (MCP) SERVERS (\(servers.count) FOUND)")
                let hName = "SERVER NAME".padding(toLength: 22, withPad: " ", startingAt: 0)
                let hStatus = "STATUS".padding(toLength: 12, withPad: " ", startingAt: 0)
                let hHost = "HOST CLIENT".padding(toLength: 18, withPad: " ", startingAt: 0)
                let hPid = "PID".padding(toLength: 8, withPad: " ", startingAt: 0)
                print("\(hName)  \(hStatus)  \(hHost)  \(hPid)  TOOLS / COMMAND")
                print(String(repeating: "─", count: 75))
                for s in servers {
                    let nameStr = String(s.name.prefix(22)).padding(toLength: 22, withPad: " ", startingAt: 0)
                    let statusStr = s.status.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
                    let hostStr = String(s.source.rawValue.prefix(18)).padding(toLength: 18, withPad: " ", startingAt: 0)
                    let pidStr = (s.pid != nil ? "\(s.pid!)" : "-").padding(toLength: 8, withPad: " ", startingAt: 0)
                    let toolsDesc = s.toolsExposed.isEmpty ? (s.command.isEmpty ? "-" : s.command) : "\(s.toolsExposed.count) tools (\(s.toolsExposed.prefix(3).joined(separator: ", "))\(s.toolsExposed.count > 3 ? "..." : ""))"
                    print("\(nameStr)  \(statusStr)  \(hostStr)  \(pidStr)  \(toolsDesc)")
                }
            }
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
