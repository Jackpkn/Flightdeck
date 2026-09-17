import Testing
import Foundation
@testable import Flightdeck

@Suite("MCP Ping Probe Tests")
struct MCPPingProbeTests {

    @Test("Running process PID liveness returns instant success with low latency")
    func livePidProbe() {
        let currentPid = ProcessInfo.processInfo.processIdentifier

        let server = MCPServerItem(
            id: "pid-\(currentPid)-test",
            name: "Current Test Runner",
            status: .running,
            source: .systemProcess,
            pid: currentPid,
            command: ""
        )

        let result = MCPPingProbe.probe(server: server, timeoutSeconds: 1.0)
        #expect(result.isHealthy == true)
        #expect(result.serverName == "Current Test Runner")
        #expect(result.protocolVersion?.contains("2024-11-05") == true)
        #expect(result.latencyMs >= 0.0)
        #expect(result.errorDescription == nil)
    }

    @Test("Non-existent PID returns failure diagnostic")
    func deadPidProbe() {
        // PID 999999 is almost certainly non-existent
        let deadPid: pid_t = 999999

        let server = MCPServerItem(
            id: "pid-\(deadPid)-dead",
            name: "Dead Server",
            status: .running,
            source: .systemProcess,
            pid: deadPid,
            command: ""
        )

        let result = MCPPingProbe.probe(server: server, timeoutSeconds: 1.0)
        #expect(result.isHealthy == false)
        #expect(result.serverName == "Dead Server")
        #expect(result.errorDescription?.contains("not responding") == true)
    }

    @Test("Non-executable command reports spawn failure")
    func nonExecutableCommand() {
        let server = MCPServerItem(
            id: "cfg-missing-bin",
            name: "Missing Tool MCP",
            status: .configured,
            source: .claudeCode,
            command: "/nonexistent/path/to/mcp-server-fake-bin",
            args: []
        )

        let result = MCPPingProbe.probe(server: server, timeoutSeconds: 1.0)
        #expect(result.isHealthy == false)
        #expect(result.errorDescription?.contains("Failed to spawn") == true)
    }

    @Test("Empty command reports missing configuration error")
    func emptyCommand() {
        let server = MCPServerItem(
            id: "cfg-empty",
            name: "Empty Config",
            status: .configured,
            source: .claudeCode,
            command: "",
            args: []
        )

        let result = MCPPingProbe.probe(server: server, timeoutSeconds: 1.0)
        #expect(result.isHealthy == false)
        #expect(result.errorDescription == "No executable command configured")
    }

    @Test("Stdio echo test responds and benchmarks latency")
    func stdioEchoHandshake() {
        // Run /bin/cat which echoes back stdin input immediately
        let server = MCPServerItem(
            id: "cfg-cat-echo",
            name: "Echo Test MCP",
            status: .configured,
            source: .claudeCode,
            command: "/bin/cat",
            args: []
        )

        let result = MCPPingProbe.probe(server: server, timeoutSeconds: 2.0)
        #expect(result.isHealthy == true)
        #expect(result.serverName == "Echo Test MCP")
        #expect(result.latencyMs > 0.0)
    }
}
