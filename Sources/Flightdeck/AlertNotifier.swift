import Foundation
import Observation
import UserNotifications

/// Delivers alerts as macOS notifications, and keeps them for in-app display.
///
/// The decision of *what* is worth saying lives in `AlertEngine`, which is a pure
/// value type. This owns only the plumbing: authorisation, delivery, and the poll
/// that feeds the engine.
@Observable
@MainActor
final class AlertNotifier {
    /// Most recent alerts, newest first, for the in-app bell.
    private(set) var recent: [Alert] = []
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// User-facing switch. Off by default is wrong — the whole point is catching a
    /// limit before it bites — but it must be switchable, and the choice must stick.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { requestAuthorizationIfNeeded() }
        }
    }

    private static let enabledKey = "flightdeck.notifications_enabled"
    private static let recentLimit = 20

    private var engine = AlertEngine()
    private var timer: Timer?
    private let interval: TimeInterval

    /// Notifications are only useful if they arrive while the condition holds, and
    /// the evaluation is pure in-memory work, so 30s is cheap and timely enough.
    init(interval: TimeInterval = 30) {
        self.interval = interval
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
    }

    func start(store: DashboardStore, usage: ClaudeUsageMonitor, budget: BudgetManager = .shared) {
        refreshAuthorization()
        if isEnabled { requestAuthorizationIfNeeded() }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluate(store: store, usage: usage, budget: budget)
            }
        }
        evaluate(store: store, usage: usage, budget: budget)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate(store: DashboardStore, usage: ClaudeUsageMonitor, budget: BudgetManager) {
        let alerts = engine.evaluate(
            usage: usage.snapshot,
            sessions: store.activeSessions,
            todaySpend: store.todaySpend,
            dailyBudget: budget.dailyBudget
        )
        guard !alerts.isEmpty else { return }

        recent.insert(contentsOf: alerts, at: 0)
        if recent.count > Self.recentLimit {
            recent.removeLast(recent.count - Self.recentLimit)
        }
        guard isEnabled else { return }
        for alert in alerts { deliver(alert) }
    }

    // MARK: - Notification centre

    /// Nil when the process has no bundle identifier — an unbundled binary, where
    /// UNUserNotificationCenter is unavailable and touching it would trap.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func refreshAuthorization() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                self?.authorization = settings.authorizationStatus
            }
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard let center, authorization != .authorized else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthorization()
            }
        }
    }

    private func deliver(_ alert: Alert) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = alert.isCritical ? .defaultCritical : .default
        // Thread by condition so repeated alerts about one thing group together
        // rather than stacking up separately in Notification Centre.
        content.threadIdentifier = alert.dedupeKey

        center.add(UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        ))
    }
}
