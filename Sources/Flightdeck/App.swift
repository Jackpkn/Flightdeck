import SwiftUI

@MainActor
struct FlightdeckApp: App {
    @State private var store = DashboardStore()
    @State private var activityWatcher = ActivityWatcher()
    @State private var downloadsWatcher = DownloadsWatcher()
    @State private var processMonitor = ProcessMonitor()
    @State private var fileBrowser = FileBrowser()
    @State private var diskScanner = DiskScanner()
    @State private var dayTimeline = DayTimeline()
    @State private var actions = ActionCenter()
    @State private var hardwareVitals = HardwareVitals()
    @State private var portScanner = PortScanner()
    @State private var zombieDetector = ZombieDetector()
    @State private var devCleaner = DevCleaner()
    @State private var appUninstaller = AppUninstaller.shared
    @State private var duplicateScanner = DuplicateScanner.shared
    @State private var mcpScanner = MCPServerScanner.shared
    @State private var usageMonitor = ClaudeUsageMonitor()
    @State private var outcomeStore = SessionOutcomeStore()
    @State private var alerts = AlertNotifier()

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("Flightdeck", id: "dashboard") {
            DashboardView()
                .environment(store)
                .environment(activityWatcher)
                .environment(downloadsWatcher)
                .environment(processMonitor)
                .environment(fileBrowser)
                .environment(diskScanner)
                .environment(dayTimeline)
                .environment(actions)
                .environment(hardwareVitals)
                .environment(portScanner)
                .environment(zombieDetector)
                .environment(devCleaner)
                .environment(appUninstaller)
                .environment(duplicateScanner)
                .environment(mcpScanner)
                .environment(usageMonitor)
                .environment(outcomeStore)
                .environment(alerts)
                .frame(minWidth: 1180, maxWidth: .infinity, minHeight: 780, maxHeight: .infinity)
                .background(Theme.page)
                .preferredColorScheme(.dark)
                .onAppear {
                    store.start()
                    activityWatcher.start()
                    downloadsWatcher.start()
                    processMonitor.start()
                    fileBrowser.start()
                    hardwareVitals.start()
                    portScanner.start()
                    zombieDetector.start()
                    devCleaner.start()
                    mcpScanner.start()
                    usageMonitor.start()
                    alerts.start(store: store, usage: usageMonitor)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 820)

        // Lets the app keep tracking with the dashboard window closed — which
        // is what makes the persisted history continuous instead of only
        // covering the times someone had a big window open.
        MenuBarExtra {
            MenuBarPanel(
                store: store,
                usage: usageMonitor,
                alerts: alerts,
                watcher: activityWatcher,
                monitor: processMonitor,
                portScanner: portScanner,
                zombieDetector: zombieDetector,
                devCleaner: devCleaner
            )
            .preferredColorScheme(.dark)
        } label: {
            // Icon-only on purpose: a wide label gets pushed behind the notch
            // on a busy menu bar and then simply never shows up.
            Image(systemName: "speedometer")
        }
        .menuBarExtraStyle(.window)
    }
}
