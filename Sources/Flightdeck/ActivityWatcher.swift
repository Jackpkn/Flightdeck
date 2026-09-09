import AppKit
import ApplicationServices
import CoreGraphics

/// One stretch of time spent in one app — closed off (`endedAt` set) the moment
/// the user switches away, so duration is always real elapsed time, not a guess.
struct AppActivityEntry: Identifiable {
    let id = UUID()
    let appName: String
    let bundleId: String
    var windowTitle: String?
    let startedAt: Date
    var endedAt: Date?

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

/// App-switch tracking needs no permission at all — NSWorkspace notifications
/// are plain public API. Window *titles* specifically require Accessibility,
/// which is why that half is gated behind an explicit grant.
///
/// Closed segments are written to SQLite, so today's totals survive a restart
/// and keep accumulating. Idle stretches are deliberately excluded: leaving the
/// machine with an app focused would otherwise record hours of fake usage into
/// a database we now keep forever.
@Observable
final class ActivityWatcher {
    private(set) var accessibilityGranted = false
    private(set) var isIdle = false
    /// Bumped by the tick timer so the live segment's elapsed time re-renders.
    private(set) var lastTick = Date()

    /// Persisted per-app totals for today, refreshed when a segment closes.
    private var persistedToday: [(name: String, seconds: TimeInterval, bundleId: String)] = []
    /// Only the segment currently in flight; finished ones live in the database.
    private var openEntry: AppActivityEntry?

    private var observerToken: NSObjectProtocol?
    private var tickTimer: Timer?
    private let idleThreshold: TimeInterval = 120

    func start() {
        accessibilityGranted = AXIsProcessTrusted()
        reloadPersistedTotals()

        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleActivation(note)
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            openSegment(for: app)
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // Without this the segment in flight at quit time is simply lost.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeOpenSegment()
        }
    }

    func stop() {
        closeOpenSegment()
        tickTimer?.invalidate()
        tickTimer = nil
        if let observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(observerToken)
        }
        observerToken = nil
    }

    /// Shows the real system permission dialog — same category as any app
    /// asking for Accessibility access, no special vendor status involved.
    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    var totalTimeToday: TimeInterval {
        timeByApp.reduce(0) { $0 + $1.seconds }
    }

    /// The in-flight segment, so the timeline can draw the block you're inside
    /// right now — it isn't in the database yet by design.
    var liveSegment: AppSegment? {
        guard let openEntry, !isIdle else { return nil }
        return AppSegment(
            id: "live",
            appName: openEntry.appName,
            bundleId: openEntry.bundleId,
            startedAt: openEntry.startedAt,
            endedAt: Date()
        )
    }

    /// Database totals for today merged with the in-flight segment, so the
    /// number climbs live without querying SQLite on every redraw.
    var timeByApp: [(name: String, seconds: TimeInterval, bundleId: String)] {
        var totals: [String: (seconds: TimeInterval, bundleId: String)] = [:]
        for row in persistedToday {
            totals[row.name] = (row.seconds, row.bundleId)
        }
        if let openEntry, !isIdle {
            var current = totals[openEntry.appName] ?? (0, openEntry.bundleId)
            current.seconds += openEntry.duration
            totals[openEntry.appName] = current
        }
        return totals
            .sorted { $0.value.seconds > $1.value.seconds }
            .map { ($0.key, $0.value.seconds, $0.value.bundleId) }
    }

    /// A graceful quit — the same request the Dock sends, not a force-kill.
    /// Only reaches apps you're already running; nothing system-level.
    func quit(bundleId: String) {
        guard bundleId != Bundle.main.bundleIdentifier,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId })
        else { return }
        app.terminate()
    }

    /// The hard kill, deliberately behind an ⌥-click so it can't be hit by
    /// accident — same gesture macOS itself uses to reveal Force Quit.
    func forceQuit(bundleId: String) {
        guard bundleId != Bundle.main.bundleIdentifier,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId })
        else { return }
        app.forceTerminate()
    }

    // MARK: - Segment lifecycle

    private func handleActivation(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        closeOpenSegment()
        openSegment(for: app)
    }

    private func openSegment(for app: NSRunningApplication) {
        let title = accessibilityGranted ? Self.focusedWindowTitle(pid: app.processIdentifier) : nil
        openEntry = AppActivityEntry(
            appName: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? "",
            windowTitle: title,
            startedAt: Date()
        )
    }

    /// Writes the in-flight segment to disk. `endedAt` can be pulled back to
    /// when input actually stopped, so an idle stretch isn't billed as usage.
    private func closeOpenSegment(endingAt: Date = Date()) {
        guard let entry = openEntry else { return }
        openEntry = nil
        guard endingAt > entry.startedAt else { return }
        ActivityDatabase.shared?.save(
            appName: entry.appName,
            bundleId: entry.bundleId,
            windowTitle: entry.windowTitle,
            startedAt: entry.startedAt,
            endedAt: endingAt
        )
        reloadPersistedTotals()
    }

    private func tick() {
        let idleSeconds = Self.systemIdleSeconds()

        if idleSeconds >= idleThreshold {
            if !isIdle {
                // Stop the clock at the moment input stopped, not now.
                closeOpenSegment(endingAt: Date().addingTimeInterval(-idleSeconds))
                isIdle = true
            }
        } else if isIdle {
            isIdle = false
            if let app = NSWorkspace.shared.frontmostApplication {
                openSegment(for: app)
            }
        }

        lastTick = Date()
    }

    private func reloadPersistedTotals() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        persistedToday = ActivityDatabase.shared?.totals(since: startOfDay) ?? []
    }

    // MARK: - System queries

    /// Seconds since the last human input of any kind. Free, no permission.
    private static func systemIdleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }

        var titleRef: AnyObject?
        let axWindow = window as! AXUIElement
        guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }
}
