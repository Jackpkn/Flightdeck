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
}
