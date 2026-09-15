import Foundation

/// Entry point: dispatches between headless CLI mode and the normal SwiftUI GUI.
/// Running `flightdeck <subcommand>` in terminal runs headless CLI commands.
/// Running `flightdeck` with no arguments or double-clicking the app launches the GUI.
let args = CommandLine.arguments

if args.count >= 2 {
    let firstArg = args[1]
    // macOS LaunchServices passes -psn_... when launching via Finder/Dock
    if !firstArg.hasPrefix("-psn") {
        CLI.run(arguments: Array(args.dropFirst()))
        // CLI.run calls exit() — never reaches here
    }
}

// No CLI subcommand → launch the SwiftUI macOS app
FlightdeckApp.main()
