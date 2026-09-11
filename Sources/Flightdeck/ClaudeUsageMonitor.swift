import Foundation
import Observation

/// Watches Claude Code's cached rate-limit utilization in `~/.claude.json`.
///
/// This is the only local source for how much of the account's five-hour and weekly
/// budgets are gone. Claude Code refreshes it while a session runs, so the monitor
/// polls the file rather than deriving anything itself.
@Observable
final class ClaudeUsageMonitor {
    private(set) var snapshot: ClaudeUsageSnapshot?
    /// Bumped on every poll so views re-render countdowns without their own timer.
    private(set) var tick: Date = Date()

    private var timer: Timer?
    private let url: URL
    private let interval: TimeInterval
    /// `~/.claude.json` runs to hundreds of KB and grows with every project, so the
    /// read and parse stay off the main thread; only the result is published there.
    private let ioQueue = DispatchQueue(label: "com.flightdeck.usage-limits", qos: .utility)

    /// `interval` is a poll, not a countdown refresh — 20s keeps reset timers
    /// visibly moving without re-reading an 85KB JSON file more than necessary.
    init(url: URL = ClaudeUsageLimitsReader.defaultURL(), interval: TimeInterval = 20) {
        self.url = url
        self.interval = interval
    }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    func reload() {
        let url = self.url
        ioQueue.async { [weak self] in
            let loaded = ClaudeUsageLimitsReader.load(from: url)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Never blank out a good reading because one poll raced a partial write.
                if let loaded { self.snapshot = loaded }
                self.tick = Date()
            }
        }
    }

    /// True when the file exists but carries no usage block — an account or plan
    /// that does not report limits, which is different from "not loaded yet".
    var hasData: Bool { snapshot != nil }
}
