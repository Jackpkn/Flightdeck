import Foundation

/// Result of testing a Model Context Protocol (MCP) server's health, protocol handshake, and latency.
struct MCPPingResult: Sendable, Identifiable {
    var id: String { serverName }
    let serverName: String
    let source: String
    let isHealthy: Bool
    let latencyMs: Double
    let protocolVersion: String?
    let serverTitle: String?
    let serverVersion: String?
    let errorDescription: String?

    init(
        serverName: String,
        source: String = "MCP",
        isHealthy: Bool,
        latencyMs: Double,
        protocolVersion: String? = nil,
        serverTitle: String? = nil,
        serverVersion: String? = nil,
        errorDescription: String? = nil
    ) {
        self.serverName = serverName
        self.source = source
        self.isHealthy = isHealthy
        self.latencyMs = latencyMs
        self.protocolVersion = protocolVersion
        self.serverTitle = serverTitle
        self.serverVersion = serverVersion
        self.errorDescription = errorDescription
    }
}

/// Diagnostic health probe and latency benchmark engine for Model Context Protocol (MCP) servers.
enum MCPPingProbe {

    /// Pings an individual MCP server item by either sending a JSON-RPC 2.0 initialize request or probing process liveness.
    static func probe(server: MCPServerItem, timeoutSeconds: Double = 3.0) -> MCPPingResult {
        // 1. If it is already a running process, probe OS process liveness and kernel task status
        if let pid = server.pid {
            let start = Date()
            let alive = kill(pid, 0) == 0
            let elapsedMs = max(0.1, Date().timeIntervalSince(start) * 1000.0)
            if alive {
                return MCPPingResult(
                    serverName: server.name,
                    source: server.source.rawValue,
                    isHealthy: true,
                    latencyMs: elapsedMs,
                    protocolVersion: "2024-11-05 (live daemon)",
                    serverTitle: server.name,
                    serverVersion: "active daemon (PID \(pid))",
                    errorDescription: nil
                )
            } else {
                return MCPPingResult(
                    serverName: server.name,
                    source: server.source.rawValue,
                    isHealthy: false,
                    latencyMs: elapsedMs,
                    errorDescription: "Daemon PID \(pid) is not responding or terminated"
                )
            }
        }

        // 2. Configured stdio server: test spawn & handshake
        guard !server.command.isEmpty else {
            return MCPPingResult(
                serverName: server.name,
                source: server.source.rawValue,
                isHealthy: false,
                latencyMs: 0,
                errorDescription: "No executable command configured"
            )
        }

        var execCommand = server.command
        var execArgs = server.args

        // If command has arguments in a single string, separate them
        if execArgs.isEmpty && execCommand.contains(" ") {
            let parts = execCommand.split(separator: " ").map(String.init)
            if let first = parts.first {
                execCommand = first
                execArgs = Array(parts.dropFirst())
            }
        }

        return probeStdio(
            serverName: server.name,
            source: server.source.rawValue,
            command: execCommand,
            args: execArgs,
            timeoutSeconds: timeoutSeconds
        )
    }

    /// Spawns a stdio MCP process, sends standard JSON-RPC 2.0 initialize request, and benchmarks response latency.
    static func probeStdio(
        serverName: String,
        source: String = "MCP",
        command: String,
        args: [String],
        timeoutSeconds: Double = 3.0
    ) -> MCPPingResult {
        let process = Process()

        // Resolve executable command path
        let resolvedCommand = resolveExecutable(command)
        process.executableURL = URL(fileURLWithPath: resolvedCommand)
        process.arguments = args

        // Inherit user environment so node/python/uv/npx are found on PATH
        var env = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = env["PATH"] {
            env["PATH"] = "\(existing):\(defaultPath)"
        } else {
            env["PATH"] = defaultPath
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()

        do {
            try process.run()
        } catch {
            return MCPPingResult(
                serverName: serverName,
                source: source,
                isHealthy: false,
                latencyMs: 0,
                errorDescription: "Failed to spawn command '\(command)': \(error.localizedDescription)"
            )
        }

        // Send standard MCP initialize request
        let rpcRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"Flightdeck","version":"0.2.0"}}}\n
        """

        guard let requestData = rpcRequest.data(using: .utf8) else {
            process.terminate()
            return MCPPingResult(serverName: serverName, source: source, isHealthy: false, latencyMs: 0, errorDescription: "UTF-8 encoding error")
        }

        stdinPipe.fileHandleForWriting.write(requestData)

        // Asynchronously read response with timeout
        var responseData = Data()
        let readQueue = DispatchQueue(label: "flightdeck.mcp.ping")
        let group = DispatchGroup()
        group.enter()

        let stdoutHandle = stdoutPipe.fileHandleForReading

        readQueue.async {
            // Read until newline or EOF
            while process.isRunning || stdoutHandle.availableData.count > 0 {
                let chunk = stdoutHandle.availableData
                if chunk.isEmpty {
                    break
                }
                responseData.append(chunk)
                if responseData.contains(0x0A) { // Newline delimiter
                    break
                }
            }
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeoutSeconds)
        let elapsedMs = Date().timeIntervalSince(startTime) * 1000.0

        // Clean up spawned process
        if process.isRunning {
            process.terminate()
            // Grace period before force kill
            usleep(100_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        if waitResult == .timedOut {
            return MCPPingResult(
                serverName: serverName,
                source: source,
                isHealthy: false,
                latencyMs: elapsedMs,
                errorDescription: "Timed out waiting for MCP handshake after \(String(format: "%.1f", timeoutSeconds))s"
            )
        }

        guard !responseData.isEmpty else {
            // Check stderr for error hints
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = errStr.isEmpty ? "Server closed stdout without responding to initialize" : errStr
            return MCPPingResult(
                serverName: serverName,
                source: source,
                isHealthy: false,
                latencyMs: elapsedMs,
                errorDescription: reason
            )
        }

        // Parse JSON-RPC response
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if let result = json["result"] as? [String: Any] {
                let proto = result["protocolVersion"] as? String ?? "2024-11-05"
                let serverInfo = result["serverInfo"] as? [String: Any]
                let title = serverInfo?["name"] as? String ?? serverName
                let ver = serverInfo?["version"] as? String ?? "unknown"

                return MCPPingResult(
                    serverName: serverName,
                    source: source,
                    isHealthy: true,
                    latencyMs: elapsedMs,
                    protocolVersion: proto,
                    serverTitle: title,
                    serverVersion: ver,
                    errorDescription: nil
                )
            } else if let error = json["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown MCP error"
                return MCPPingResult(
                    serverName: serverName,
                    source: source,
                    isHealthy: false,
                    latencyMs: elapsedMs,
                    errorDescription: "JSON-RPC error: \(msg)"
                )
            }
        }

        // Fallback: Check if response has non-empty text
        if let rawText = String(data: responseData, encoding: .utf8), !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MCPPingResult(
                serverName: serverName,
                source: source,
                isHealthy: true,
                latencyMs: elapsedMs,
                protocolVersion: "custom/stdio",
                serverTitle: serverName,
                serverVersion: "live",
                errorDescription: nil
            )
        }

        return MCPPingResult(
            serverName: serverName,
            source: source,
            isHealthy: false,
            latencyMs: elapsedMs,
            errorDescription: "Malformed JSON-RPC response from server"
        )
    }

    /// Resolves executable path using common macOS developer paths.
    private static func resolveExecutable(_ command: String) -> String {
        if command.hasPrefix("/") || command.hasPrefix("./") {
            return command
        }

        let candidates = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback to /usr/bin/env to resolve dynamically
        return "/usr/bin/env"
    }
}
