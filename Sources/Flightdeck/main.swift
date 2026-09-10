import Foundation

/// Entry point: dispatches between headless CLI mode (statusline/hook/install-hooks)
/// and the normal SwiftUI GUI. Claude Code invokes the CLI subcommands; the user
/// launches the GUI by double-clicking the app or running `./scripts/run-app.sh`.
let args = CommandLine.arguments

if args.count >= 2 {
    let subcommand = args[1].lowercased()
    if ["statusline", "hook", "install-hooks"].contains(subcommand) {
        CLI.run(subcommand: subcommand)
        // CLI.run calls exit() — never reaches here
    }
}

// No CLI subcommand → launch the SwiftUI macOS app
FlightdeckApp.main()
