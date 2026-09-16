import Testing
import Foundation
import Darwin
@testable import Flightdeck

@Suite("CLITests")
struct CLITests {

    @Test("Darwin proc_listpids retrieves active system PIDs without error")
    func testProcListPids() {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        #expect(byteCount > 0)

        let numPids = Int(byteCount) / MemoryLayout<pid_t>.size
        #expect(numPids > 10)

        var pids = [pid_t](repeating: 0, count: numPids)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, byteCount)
        #expect(filled > 0)
    }

    @Test("proc_pidinfo reads current process memory task info")
    func testCurrentProcTaskInfo() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let res = proc_pidinfo(currentPid, PROC_PIDTASKINFO, 0, &info, size)
        #expect(res == size)
        #expect(info.pti_resident_size > 0)
    }

    @Test("proc_name retrieves valid process name for self")
    func testCurrentProcName() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let bytes = proc_name(currentPid, &nameBuffer, 1024)
        #expect(bytes > 0)
        let name = String(cString: nameBuffer)
        #expect(!name.isEmpty)
    }

    @Test("Formatters handles token counts and USD values cleanly")
    func testCLIFormatters() {
        #expect(Formatters.tokens(250_000) == "250,000")
        #expect(Formatters.tokens(0) == "0")
        #expect(Formatters.usd(0.0) == "$0.00")
        #expect(Formatters.usd(4.50) == "$4.50")
        #expect(Formatters.usd(124.99) == "$124.99")
    }

    @Test("ClaudeIntegrationInstaller recognizes CLI subcommands")
    func testInstallerSubcommands() {
        #expect(ClaudeIntegrationInstaller.isFlightdeckCommand("flightdeck statusline"))
        #expect(ClaudeIntegrationInstaller.isFlightdeckCommand("/usr/local/bin/flightdeck hook PostToolUse"))
        #expect(!ClaudeIntegrationInstaller.isFlightdeckCommand("echo flightdeck"))
        #expect(!ClaudeIntegrationInstaller.isFlightdeckCommand(nil))
    }

    @Test("PortScanner fetchListeningPorts returns valid TCP ports and classifies dev ports")
    func testPortScannerFetch() {
        let ports = PortScanner.fetchListeningPorts()
        // Ports should execute without crashing and have valid port bounds
        for p in ports {
            #expect(p.port > 0 && p.port <= 65535)
            #expect(!p.processName.isEmpty)
            #expect(p.isDevPort == (p.port < 49152))
        }
    }

    @Test("PortScanner isKillable guards protected system PIDs and self")
    func testPortScannerSafety() {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        #expect(!PortScanner.isKillable(pid: 0))
        #expect(!PortScanner.isKillable(pid: 1))
        #expect(!PortScanner.isKillable(pid: selfPid))
        #expect(PortScanner.isKillable(pid: 99999))
    }

    @Test("DevCleaner scanSynchronously discovers default developer cache targets")
    func testDevCleanerScan() {
        let targets = DevCleaner.scanSynchronously()
        #expect(!targets.isEmpty)
        #expect(targets.contains(where: { $0.id == "xcode_derived_data" }))
        #expect(targets.contains(where: { $0.id == "npm_cache" }))
        #expect(targets.contains(where: { $0.id == "spm_cache" }))

        // All non-RAM targets must have valid user-directory paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for target in targets where !target.isRAM {
            #expect(target.path.path.hasPrefix(home))
            #expect(target.sizeBytes >= 0)
        }
    }

    @Test("ZombieDetector discoverOrphans runs safely and adheres to safety guards")
    func testZombieDetector() {
        let orphans = ZombieDetector.discoverOrphans()
        let selfPid = ProcessInfo.processInfo.processIdentifier
        for orphan in orphans {
            #expect(orphan.pid > 1)
            #expect(orphan.pid != selfPid)
            #expect(!orphan.path.isEmpty)
            #expect(orphan.memoryBytes >= 0)
        }
        #expect(!ZombieDetector.isKillable(pid: 0))
        #expect(!ZombieDetector.isKillable(pid: 1))
        #expect(!ZombieDetector.isKillable(pid: selfPid))
        #expect(ZombieDetector.isKillable(pid: 88888))
    }

    @Test("MCPServerScanner scanAllSync retrieves running and configured MCP servers")
    func testMCPServerScannerSync() {
        let servers = MCPServerScanner.scanAllSync()
        for server in servers {
            #expect(!server.id.isEmpty)
            #expect(!server.name.isEmpty)
        }
    }
}
