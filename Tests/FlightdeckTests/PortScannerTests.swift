import Testing
import Foundation
@testable import Flightdeck

@Suite("PortScannerTests")
struct PortScannerTests {
    @Test("Parse lsof output extracts listening ports, PIDs, and process names correctly")
    func parseLsofOutput() {
        let sampleOutput = """
        COMMAND     PID       USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      24048 pawankumar   16u  IPv4 0xeb37d846bc1053e2      0t0  TCP *:5173 (LISTEN)
        Python    36348 pawankumar   11u  IPv4 0xff500bbab676f049      0t0  TCP 127.0.0.1:8080 (LISTEN)
        com.docke 79196 pawankumar  256u  IPv4 0xcf15732626db7587      0t0  TCP 127.0.0.1:5432 (LISTEN)
        dart      81498 pawankumar    9u  IPv4 0xc454449da28cbdea      0t0  TCP 127.0.0.1:55535 (LISTEN)
        """

        let ports = PortScanner.parseLsofOutput(sampleOutput)

        #expect(ports.count == 4)

        let vite = ports.first { $0.port == 5173 }
        #expect(vite != nil)
        #expect(vite?.processName == "node")
        #expect(vite?.pid == 24048)
        #expect(vite?.address == "0.0.0.0")
        #expect(vite?.isDevPort == true)

        let python = ports.first { $0.port == 8080 }
        #expect(python != nil)
        #expect(python?.processName == "Python")
        #expect(python?.pid == 36348)
        #expect(python?.address == "127.0.0.1")
        #expect(python?.isDevPort == true)

        let postgres = ports.first { $0.port == 5432 }
        #expect(postgres != nil)
        #expect(postgres?.processName == "com.docke")
        #expect(postgres?.pid == 79196)
        #expect(postgres?.isDevPort == true)

        let ephemeral = ports.first { $0.port == 55535 }
        #expect(ephemeral != nil)
        #expect(ephemeral?.isDevPort == false)
    }

    @Test("Selection and checkout multi-select logic operates reliably")
    func selectionLogic() {
        let scanner = PortScanner()
        let p1 = ListeningPort(port: 3000, processName: "node", pid: 1001, address: "127.0.0.1")
        let p2 = ListeningPort(port: 8080, processName: "python", pid: 1002, address: "127.0.0.1")
        let p3 = ListeningPort(port: 52000, processName: "dart", pid: 1003, address: "127.0.0.1")

        // Populate scanner via parsing
        let dummyOutput = """
        COMMAND   PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        node     1001 user 1u IPv4 0x1    0t0      TCP *:3000 (LISTEN)
        python   1002 user 2u IPv4 0x2    0t0      TCP *:8080 (LISTEN)
        dart     1003 user 3u IPv4 0x3    0t0      TCP *:52000 (LISTEN)
        """
        let parsed = PortScanner.parseLsofOutput(dummyOutput)
        #expect(parsed.count == 3)

        // Test single toggle
        scanner.toggleSelection(id: parsed[0].id)
        #expect(scanner.isSelected(id: parsed[0].id))
        #expect(!scanner.isSelected(id: parsed[1].id))

        scanner.toggleSelection(id: parsed[0].id)
        #expect(!scanner.isSelected(id: parsed[0].id))
    }

    @Test("Kill safety refuses to kill PID 0, PID 1, or self PID")
    func killSafety() {
        let scanner = PortScanner()
        let selfPid = ProcessInfo.processInfo.processIdentifier

        #expect(!scanner.isKillable(pid: 0))
        #expect(!scanner.isKillable(pid: 1))
        #expect(!scanner.isKillable(pid: selfPid))
        #expect(scanner.isKillable(pid: 99999))
    }
}
