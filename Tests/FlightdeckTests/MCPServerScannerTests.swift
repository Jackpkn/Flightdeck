import Testing
import Foundation
@testable import Flightdeck

@Suite("MCPServerScannerTests")
struct MCPServerScannerTests {

    @Test("Parses Darwin ps output for active Chrome DevTools MCP server")
    func parseChromeDevToolsPS() {
        let samplePS = """
          PID  %CPU    RSS      ELAPSED COMMAND
        23689   0.1  84210     02:45:12 node /usr/local/bin/chrome-devtools-mcp --port 9222
        50834   1.5 142850     05:12:00 python3 -m mcp_servers.codex_app --socket /tmp/codex-browser-use/codex.sock
        10101   0.0  12000     00:10:00 /usr/sbin/syslogd
        """

        let servers = MCPServerScanner.parsePSOutput(samplePS)

        #expect(servers.count == 2)

        guard let chrome = servers.first(where: { $0.pid == 23689 }) else {
            Issue.record("Expected Chrome DevTools MCP server with PID 23689")
            return
        }
        #expect(chrome.name == "Chrome DevTools MCP")
        #expect(chrome.status == .running)
        #expect(chrome.isRunning == true)
        #expect(chrome.cpuPercent == 0.1)
        #expect(chrome.memoryBytes == Int64(84210 * 1024))
        #expect(chrome.toolsExposed.contains("capture_screenshot"))
        #expect(chrome.toolsExposed.contains("navigate_page"))

        guard let codex = servers.first(where: { $0.pid == 50834 }) else {
            Issue.record("Expected Codex App Tools MCP server with PID 50834")
            return
        }
        #expect(codex.name == "Codex App Tools MCP")
        #expect(codex.source == .codex)
        #expect(codex.socketOrPipePath == "/tmp/codex-browser-use/codex.sock")
        #expect(codex.toolsExposed.contains("create_thread"))
        #expect(codex.toolsExposed.contains("send_message_to_thread"))
    }

    @Test("Ignores non-MCP processes and ps/grep self-references")
    func ignoreIrrelevantProcesses() {
        let samplePS = """
          PID  %CPU    RSS      ELAPSED COMMAND
        12345   0.0   5000     00:00:01 grep mcp
        12346   0.0   4000     00:00:01 /bin/ps -axo pid,%cpu,rss,etime,command
        12347   5.0 500000     01:00:00 /Applications/Safari.app/Contents/MacOS/Safari
        """

        let servers = MCPServerScanner.parsePSOutput(samplePS)
        #expect(servers.isEmpty)
    }

    @Test("Server status model and isRunning helper behave consistently")
    func mcpStatusModel() {
        let running = MCPServerItem(
            id: "test-running",
            name: "Test Runner",
            status: .running,
            source: .claudeCode,
            pid: 4242,
            toolsExposed: ["tool_a", "tool_b"]
        )
        #expect(running.isRunning == true)

        let stopped = MCPServerItem(
            id: "test-stopped",
            name: "Test Stopped",
            status: .stopped,
            source: .claudeCode,
            pid: nil
        )
        #expect(stopped.isRunning == false)

        let configured = MCPServerItem(
            id: "test-configured",
            name: "Test Configured",
            status: .configured,
            source: .claudeDesktop,
            pid: nil
        )
        #expect(configured.isRunning == false)
    }

    @Test("Extracts known tools for filesystem and SQLite MCP servers")
    func toolExtractionForKnownServers() {
        let samplePS = """
          PID  %CPU    RSS      ELAPSED COMMAND
        33001   0.2  45000     00:30:10 node /path/to/mcp-server-filesystem /Users/test/workspace
        33002   0.3  62000     00:45:00 python -m mcp_server_sqlite --db /path/to/data.db
        """

        let servers = MCPServerScanner.parsePSOutput(samplePS)
        #expect(servers.count == 2)

        let fs = servers.first(where: { $0.pid == 33001 })
        #expect(fs != nil)
        #expect(fs?.name == "Filesystem MCP Server")
        #expect(fs?.toolsExposed.contains("read_file") == true)
        #expect(fs?.toolsExposed.contains("list_directory") == true)

        let sqlite = servers.first(where: { $0.pid == 33002 })
        #expect(sqlite != nil)
        #expect(sqlite?.name == "SQLite MCP Server")
        #expect(sqlite?.toolsExposed.contains("read_query") == true)
        #expect(sqlite?.toolsExposed.contains("describe_table") == true)
    }
}
