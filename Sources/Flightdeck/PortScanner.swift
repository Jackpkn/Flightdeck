import Foundation
import SwiftUI

/// A single active local listening TCP port and its bound process.
public struct ListeningPort: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let port: Int
    public let processName: String
    public let pid: Int32
    public let address: String
    public let isDevPort: Bool

    public init(
        id: UUID = UUID(),
        port: Int,
        processName: String,
        pid: Int32,
        address: String
    ) {
        self.id = id
        self.port = port
        self.processName = processName
        self.pid = pid
        self.address = address
        // Typical developer server ports are standard low/mid numbers (e.g. 3000, 5173, 8000, 8080, 5432, 6379),
        // whereas ephemeral system client ports are generally > 49152.
        self.isDevPort = port < 49152
    }
}

/// Discovers active listening TCP ports on macOS, provides individual and batch
/// "checkout-style" multi-select termination to quickly free blocked developer ports.
@Observable
public final class PortScanner {
    public static let shared = PortScanner()

    public private(set) var ports: [ListeningPort] = []
    public private(set) var isScanning = false
    public var selectedPortIds: Set<UUID> = []
    public var showDevOnly: Bool = true
    public var searchQuery: String = ""

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.flightdeck.portscanner", qos: .utility)

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Filtered Ports

    public var filteredPorts: [ListeningPort] {
        ports.filter { item in
            if showDevOnly && !item.isDevPort { return false }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
                let matchesPort = String(item.port).contains(q)
                let matchesName = item.processName.lowercased().contains(q)
                let matchesPID = String(item.pid).contains(q)
                return matchesPort || matchesName || matchesPID
            }
            return true
        }
    }

    // MARK: - Selection (Checkout Flow)

    public func toggleSelection(id: UUID) {
        if selectedPortIds.contains(id) {
            selectedPortIds.remove(id)
        } else {
            selectedPortIds.insert(id)
        }
    }

    public func isSelected(id: UUID) -> Bool {
        selectedPortIds.contains(id)
    }

    public func selectAllFiltered() {
        let visibleIds = filteredPorts.map(\.id)
        selectedPortIds.formUnion(visibleIds)
    }

    public func deselectAll() {
        selectedPortIds.removeAll()
    }

    public var areAllFilteredSelected: Bool {
        let visible = filteredPorts
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { selectedPortIds.contains($0.id) }
    }

    // MARK: - Scanning & Parsing

    public func refresh() {
        guard !isScanning else { return }
        isScanning = true

        queue.async { [weak self] in
            guard let self else { return }
            let scanned = Self.fetchListeningPorts()
            DispatchQueue.main.async {
                self.ports = scanned
                // Prune any selection IDs that no longer exist
                let existingIds = Set(scanned.map(\.id))
                self.selectedPortIds = self.selectedPortIds.intersection(existingIds)
                self.isScanning = false
            }
        }
    }

    public static func fetchListeningPorts() -> [ListeningPort] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // suppress error noise

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return parseLsofOutput(output)
        } catch {
            return []
        }
    }

    public static func parseLsofOutput(_ output: String) -> [ListeningPort] {
        var results: [ListeningPort] = []
        var seenPorts = Set<Int>()
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // Expect at least: COMMAND, PID, USER, FD, TYPE, DEVICE, SIZE/OFF, NODE, NAME (LISTEN)
            guard parts.count >= 9 else { continue }
            guard parts.last?.contains("LISTEN") == true else { continue }

            let rawProcessName = String(parts[0]).replacingOccurrences(of: "\\x20", with: " ")
            guard let pid = Int32(parts[1]) else { continue }

            // Protected system PIDs
            guard pid > 1 && pid != ProcessInfo.processInfo.processIdentifier else { continue }

            // Extract the network address and port from the second-to-last or last token before (LISTEN)
            // Format examples: "*:3000", "127.0.0.1:8080", "[::1]:5173"
            let targetToken = String(parts[parts.count - 2])
            guard let colonIndex = targetToken.lastIndex(of: ":") else { continue }

            let portString = targetToken[targetToken.index(after: colonIndex)...]
            guard let portNumber = Int(portString) else { continue }

            // Deduplicate same port instances (e.g. IPv4 + IPv6 dual-stack on same process)
            guard !seenPorts.contains(portNumber) else { continue }
            seenPorts.insert(portNumber)

            let addressString = String(targetToken[..<colonIndex])
            let cleanAddress = addressString == "*" ? "0.0.0.0" : addressString

            results.append(ListeningPort(
                port: portNumber,
                processName: rawProcessName,
                pid: pid,
                address: cleanAddress
            ))
        }

        // Sort ascending by port number, with dev ports prioritized
        return results.sorted { a, b in
            if a.isDevPort != b.isDevPort {
                return a.isDevPort && !b.isDevPort
            }
            return a.port < b.port
        }
    }

    // MARK: - Killing & Freeing Ports

    /// Free a single listening port by terminating its owning process.
    public func freePort(_ port: ListeningPort) {
        guard isKillable(pid: port.pid) else { return }
        CockpitAudio.playPing()
        terminateProcess(pid: port.pid)

        // Optimistically remove from local list
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            ports.removeAll { $0.id == port.id }
            selectedPortIds.remove(port.id)
        }

        // Re-scan after short delay to verify kernel release
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    /// Batch free all selected ports (Checkout Flow).
    public func freeSelected() {
        let targets = ports.filter { selectedPortIds.contains($0.id) }
        guard !targets.isEmpty else { return }

        CockpitAudio.playPing()
        for target in targets {
            if isKillable(pid: target.pid) {
                terminateProcess(pid: target.pid)
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            ports.removeAll { selectedPortIds.contains($0.id) }
            selectedPortIds.removeAll()
        }

        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    /// Batch free all active developer ports (< 49152).
    public func freeAllDevPorts() {
        let targets = ports.filter { $0.isDevPort }
        guard !targets.isEmpty else { return }

        CockpitAudio.playPing()
        for target in targets {
            if isKillable(pid: target.pid) {
                terminateProcess(pid: target.pid)
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            ports.removeAll { $0.isDevPort }
            selectedPortIds.removeAll()
        }

        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Process Safety

    public func isKillable(pid: Int32) -> Bool {
        Self.isKillable(pid: pid)
    }

    public static func isKillable(pid: Int32) -> Bool {
        // Must never kill Flightdeck itself or kernel/launchd
        guard pid > 1 else { return false }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        return true
    }

    private func terminateProcess(pid: Int32) {
        Self.terminateProcess(pid: pid)
    }

    public static func terminateProcess(pid: Int32) {
        // Graceful SIGTERM first
        kill(pid, SIGTERM)
        // Allow brief grace period, then verify
        usleep(250_000)
        if kill(pid, 0) == 0 { // process still alive
            kill(pid, SIGKILL)
        }
    }

    public static func killPort(_ portNumber: Int) -> (success: Bool, message: String, process: String?, pid: Int32?) {
        let ports = fetchListeningPorts()
        guard let target = ports.first(where: { $0.port == portNumber }) else {
            return (false, "No active listening process found on port \(portNumber)", nil, nil)
        }
        guard isKillable(pid: target.pid) else {
            return (false, "Refusing to terminate protected system PID \(target.pid) on port \(portNumber)", target.processName, target.pid)
        }
        terminateProcess(pid: target.pid)
        return (true, "Freed port \(portNumber) (terminated process '\(target.processName)', PID \(target.pid))", target.processName, target.pid)
    }
}
