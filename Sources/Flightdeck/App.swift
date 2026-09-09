import SwiftUI

@main
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

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("Flightdeck") {
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
                .frame(minWidth: 1180, minHeight: 780)
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
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 820)

        // Lets the app keep tracking with the dashboard window closed — which
        // is what makes the persisted history continuous instead of only
        // covering the times someone had a big window open.
        MenuBarExtra {
            MenuBarPanel(store: store, watcher: activityWatcher, monitor: processMonitor)
                .preferredColorScheme(.dark)
        } label: {
            // Icon-only on purpose: a wide label gets pushed behind the notch
            // on a busy menu bar and then simply never shows up.
            Image(systemName: "speedometer")
        }
        .menuBarExtraStyle(.window)
    }
}
