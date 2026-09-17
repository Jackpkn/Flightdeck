import Foundation
import Observation

/// Execution status of an MCP server.
enum MCPStatus: String, Sendable, CaseIterable {
    case running = "RUNNING"
    case configured = "CONFIGURED"
    case stopped = "STOPPED"
    case error = "ERROR"
}

/// The host or client that configured/launched the MCP server.
enum MCPSource: String, Sendable, CaseIterable {
    case claudeCode = "Claude Code"
    case claudeDesktop = "Claude Desktop"
    case codex = "Codex / ChatGPT"
    case systemProcess = "System Process"
    case projectWorkspace = "Project Workspace"
}

/// A representation of a Model Context Protocol (MCP) server.
struct MCPServerItem: Identifiable, Equatable {
    let id: String
    var name: String
    var status: MCPStatus
    var source: MCPSource
    var pid: pid_t?
    var cpuPercent: Double = 0.0
    var memoryBytes: Int64 = 0
    var command: String = ""
    var args: [String] = []
    var envVars: [String] = []
    var socketOrPipePath: String? = nil
    var toolsExposed: [String] = []
    var uptime: String = ""
    var callCount: Int = 0
    var lastError: String? = nil

    var isRunning: Bool {
        status == .running && pid != nil
    }
}

/// Live discovery engine and health monitor for all Model Context Protocol (MCP) servers on macOS.
@Observable
final class MCPServerScanner {
    static let shared = MCPServerScanner()

    var servers: [MCPServerItem] = []
    var isScanning: Bool = false
    private var scanTimer: Timer?

    init() {
        refresh()
    }

    func start() {
        refresh()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    func refresh() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let running = Self.scanRunningProcesses()
            let configured = Self.scanConfigFiles()

            // Merge running and configured servers
            var mergedMap: [String: MCPServerItem] = [:]

            for s in running {
                mergedMap[s.id] = s
            }

            for c in configured {
                if var existing = mergedMap[c.id] {
                    // Enrich with config metadata (e.g. tools, envVars)
                    if existing.toolsExposed.isEmpty {
                        existing.toolsExposed = c.toolsExposed
                    }
                    if existing.envVars.isEmpty {
                        existing.envVars = c.envVars
                    }
                    mergedMap[c.id] = existing
                } else {
                    mergedMap[c.id] = c
                }
            }

            let sorted = Array(mergedMap.values).sorted { a, b in
                if a.isRunning != b.isRunning {
                    return a.isRunning && !b.isRunning
                }
                return a.name.lowercased() < b.name.lowercased()
            }

            await MainActor.run { [weak self] in
                self?.servers = sorted
            }
        }
    }

    /// Terminates a running MCP daemon process.
    func stopServer(pid: pid_t) {
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    /// Synchronously scans all running MCP processes and configured servers across macOS.
    static func scanAllSync() -> [MCPServerItem] {
        let running = scanRunningProcesses()
        let configured = scanConfigFiles()

        var mergedMap: [String: MCPServerItem] = [:]
        for s in running {
            mergedMap[s.id] = s
        }
        for c in configured {
            if var existing = mergedMap[c.id] {
                if existing.toolsExposed.isEmpty {
                    existing.toolsExposed = c.toolsExposed
                }
                if existing.envVars.isEmpty {
                    existing.envVars = c.envVars
                }
                mergedMap[c.id] = existing
            } else {
                mergedMap[c.id] = c
            }
        }

        return Array(mergedMap.values).sorted { a, b in
            if a.isRunning != b.isRunning {
                return a.isRunning && !b.isRunning
            }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    // MARK: - Process Table Discovery

    static func scanRunningProcesses() -> [MCPServerItem] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid,%cpu,rss,etime,command"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            let output = String(decoding: data, as: UTF8.self)
            return parsePSOutput(output)
        } catch {
            return []
        }
    }

    static func parsePSOutput(_ output: String) -> [MCPServerItem] {
        var items: [MCPServerItem] = []
        let lines = output.split(separator: "\n")

        for line in lines.dropFirst() {
            let lineStr = line.trimmingCharacters(in: .whitespaces)
            guard !lineStr.isEmpty else { continue }

            let lower = lineStr.lowercased()
            guard lower.contains("mcp") ||
                  lower.contains("modelcontextprotocol") ||
                  lower.contains("chrome-devtools-mcp") ||
                  lower.contains("codex-app-tools") else {
                continue
            }

            // Exclude self grep / ps commands, Flightdeck itself, and Electron renderer/utility workers
            if lower.contains("grep") ||
               lower.contains("/bin/ps") ||
               lower.contains("flightdeck") ||
               lower.contains("--type=renderer") ||
               lower.contains("--type=gpu-process") ||
               lower.contains("--type=utility") {
                continue
            }

            let parts = lineStr.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pidInt = Int32(parts[0]),
                  let cpuDouble = Double(parts[1]),
                  let rssKb = Int64(parts[2]) else {
                continue
            }

            let etime = String(parts[3])
            let command = String(parts[4])

            // Determine friendly server name and source
            let (name, source, socket) = extractServerMetadata(from: command)

            var server = MCPServerItem(
                id: "pid-\(pidInt)-\(name)",
                name: name,
                status: .running,
                source: source,
                pid: pidInt,
                cpuPercent: cpuDouble,
                memoryBytes: rssKb * 1024,
                command: command,
                args: [],
                envVars: [],
                socketOrPipePath: socket,
                toolsExposed: defaultToolsForKnownServer(name: name),
                uptime: etime,
                callCount: 0
            )

            // Special handling for codex_app tools
            if name.contains("codex-app-tools") || command.contains("mcp_servers.codex_app") {
                server.toolsExposed = [
                    "automation_update",
                    "create_thread",
                    "send_message_to_thread",
                    "fork_thread",
                    "handoff_thread"
                ]
            }

            items.append(server)
        }

        return items
    }

    private static func extractServerMetadata(from cmd: String) -> (name: String, source: MCPSource, socket: String?) {
        let lower = cmd.lowercased()

        var socketPath: String? = nil
        if let sockRange = cmd.range(of: "(/tmp/[^\\s\"]+\\.sock)", options: .regularExpression) {
            socketPath = String(cmd[sockRange])
        }

        if lower.contains("chrome-devtools-mcp") {
            return ("Chrome DevTools MCP", .systemProcess, socketPath)
        } else if lower.contains("codex-app-tools") || lower.contains("mcp_servers.codex_app") {
            return ("Codex App Tools MCP", .codex, socketPath)
        } else if lower.contains("sqlite") {
            return ("SQLite MCP Server", .claudeCode, socketPath)
        } else if lower.contains("filesystem") {
            return ("Filesystem MCP Server", .claudeCode, socketPath)
        } else if lower.contains("github") {
            return ("GitHub MCP Server", .claudeCode, socketPath)
        } else if lower.contains("brave-search") {
            return ("Brave Search MCP", .claudeCode, socketPath)
        } else if lower.contains("postgres") {
            return ("PostgreSQL MCP Server", .claudeCode, socketPath)
        }

        // Fallback name extraction from command
        let words = cmd.split(separator: " ")
        for word in words {
            let w = String(word)
            // Skip json chunks and flags
            if w.contains("{") || w.contains("}") || w.contains("\"") || w.contains(":") || w.contains("=") {
                continue
            }
            if w.lowercased().contains("mcp") {
                let cleaned = URL(fileURLWithPath: w).lastPathComponent
                if !cleaned.isEmpty && cleaned.count < 30 {
                    return (cleaned, .systemProcess, socketPath)
                }
            }
        }

        let first = words.first.map(String.init) ?? "daemon"
        let binaryName = URL(fileURLWithPath: first).lastPathComponent
        return ("MCP Process (\(binaryName))", .systemProcess, socketPath)
    }

    private static func defaultToolsForKnownServer(name: String) -> [String] {
        let n = name.lowercased()
        if n.contains("chrome-devtools") || (n.contains("chrome") && n.contains("devtools")) {
            return ["navigate_page", "read_page_dom", "capture_screenshot", "evaluate_js", "inspect_network", "list_pages"]
        } else if n.contains("sqlite") {
            return ["read_query", "write_query", "list_tables", "describe_table"]
        } else if n.contains("filesystem") {
            return ["read_file", "write_file", "list_directory", "directory_tree"]
        } else if n.contains("github") {
            return ["get_issue", "create_issue", "list_pull_requests", "get_file_contents"]
        }
        return []
    }

    // MARK: - Config File Discovery

    static func scanConfigFiles() -> [MCPServerItem] {
        var items: [MCPServerItem] = []

        // 1. Scan Claude Code ~/.claude.json
        let claudeJsonURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        if let data = try? Data(contentsOf: claudeJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Global mcpServers
            if let globalMcp = json["mcpServers"] as? [String: [String: Any]] {
                for (name, cfg) in globalMcp {
                    let cmd = cfg["command"] as? String ?? ""
                    let args = cfg["args"] as? [String] ?? []
                    items.append(
                        MCPServerItem(
                            id: "cfg-claude-\(name)",
                            name: name,
                            status: .configured,
                            source: .claudeCode,
                            command: cmd,
                            args: args,
                            toolsExposed: defaultToolsForKnownServer(name: name)
                        )
                    )
                }
            }

            // Project-level mcpServers
            if let projects = json["projects"] as? [String: [String: Any]] {
                for (path, proj) in projects {
                    if let pMcp = proj["mcpServers"] as? [String: [String: Any]] {
                        let projName = URL(fileURLWithPath: path).lastPathComponent
                        for (name, cfg) in pMcp {
                            let cmd = cfg["command"] as? String ?? ""
                            let args = cfg["args"] as? [String] ?? []
                            items.append(
                                MCPServerItem(
                                    id: "cfg-proj-\(path)-\(name)",
                                    name: "\(name) (\(projName))",
                                    status: .configured,
                                    source: .projectWorkspace,
                                    command: cmd,
                                    args: args,
                                    toolsExposed: defaultToolsForKnownServer(name: name)
                                )
                            )
                        }
                    }
                }
            }
        }

        // 2. Scan Claude Desktop claude_desktop_config.json
        let desktopConfigURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        if let data = try? Data(contentsOf: desktopConfigURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desktopMcp = json["mcpServers"] as? [String: [String: Any]] {
            for (name, cfg) in desktopMcp {
                let cmd = cfg["command"] as? String ?? ""
                let args = cfg["args"] as? [String] ?? []
                items.append(
                    MCPServerItem(
                        id: "cfg-desktop-\(name)",
                        name: name,
                        status: .configured,
                        source: .claudeDesktop,
                        command: cmd,
                        args: args,
                        toolsExposed: defaultToolsForKnownServer(name: name)
                    )
                )
            }
        }

        return items
    }
}
