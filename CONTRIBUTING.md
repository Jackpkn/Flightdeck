# Contributing to Flightdeck

Thank you for your interest in contributing to Flightdeck! ⚡️

Flightdeck is an open-source macOS developer cockpit and activity monitor built purely in **Swift** and **SwiftUI**, integrating directly with Darwin POSIX and Mach kernel APIs.

---

## 🧭 Guiding Principles

When developing features or fixing bugs in Flightdeck, adhere to these core principles:

1. **Zero Mock Data**: Every metric, waveform, and process table row must originate from real Darwin kernel telemetry (`HOST_CPU_LOAD_INFO`, `HOST_VM_INFO64`, `getifaddrs`, `lsof`, `proc_listpids`). Never introduce simulated numbers in production code.
2. **Honest Attribution**: When metrics cannot be measured with 100% precision (e.g., spend predating a checkpoint, missing model pricing), explicitly label them with boundaries (`≤`, `≥`, or `unattributed`) rather than guessing.
3. **Engine Unity**: The headless CLI (`CLI.swift`) and graphical cockpit (`FlightdeckApp.swift`) must share the exact same underlying native engines (`PortScanner`, `DevCleaner`, `ZombieDetector`, `MCPServerScanner`, etc.). Do not duplicate POSIX logic between CLI and GUI.
4. **Non-Negotiable PID Safety**: Never terminate system critical processes (PID 0 kernel, PID 1 launchd, or Flightdeck itself). Destructive commands must have safeguards, confirmation prompts, or explicit `--force`/`--kill` flags.
5. **Privacy by Default**: Flightdeck never uploads telemetry to the cloud. All SQLite data, transcripts, and telemetry remain strictly on the local machine.

---

## 🛠️ Prerequisites & Local Setup

### System Requirements
* **Operating System**: macOS Sonoma (14.0) or macOS Sequoia (15.0+)
* **Toolchain**: Xcode 15.4+ or Xcode 16+ with **Swift 5.10+ / Swift 6**
* **Command Line Tools**: Installed via `xcode-select --install`

### Getting the Code

```bash
git clone git@github.com:Jackpkn/Flightdeck.git
cd Flightdeck
```

### Running Tests

Flightdeck includes an extensive automated test suite covering all kernel samplers, port scanners, and SQLite storage engines:

```bash
# Run all 267+ unit tests:
swift test

# Run a specific test suite:
swift test --filter PortScannerTests
swift test --filter DevCleanerTests
swift test --filter ZombieDetectorTests
swift test --filter CLITests
```

### Running the Headless CLI

You can run any CLI subcommand directly without building the full `.app` bundle:

```bash
swift run Flightdeck vitals
swift run Flightdeck ports --dev-only
swift run Flightdeck clean --dry-run
swift run Flightdeck zombies
swift run Flightdeck mcp --json
```

### Running the Graphical Cockpit

Because SwiftUI keyboard shortcuts and menu items require an assembled macOS application bundle:

```bash
./scripts/run-app.sh
```

This compiles the binary and packages it into a temporary `.app` bundle before launching.

---

## 📁 Repository Structure

```text
Flightdeck/
├── Sources/Flightdeck/
│   ├── CLI.swift                 # Subcommand router, table formatting & JSON serialization
│   ├── PortScanner.swift         # Darwin network socket enumeration & PID unbind
│   ├── DevCleaner.swift          # Xcode, SPM, NPM, CocoaPods, Gradle cache scanner
│   ├── ZombieDetector.swift      # Runaway developer orphan detector (ppid == 1 && NODEV)
│   ├── MCPServerScanner.swift    # Model Context Protocol runtime & config discovery
│   ├── AppUninstaller.swift      # Deep application uninstaller & leftover scanner
│   ├── SystemTelemetry.swift     # Mach kernel host_statistics & BSD network sampler
│   ├── HardwareVitals.swift      # Real-time hardware telemetry aggregator
│   ├── ProcessMonitor.swift      # Process table sampler & dual-layer PID termination
│   ├── ActivityWatcher.swift     # Foreground app switch & idle tracker
│   ├── ActivityDatabase.swift    # GRDB SQLite persistence for activity logs & sessions
│   ├── ClaudeSessionWatcher.swift# Claude Code transcript & JSON event monitor
│   ├── SessionInsights.swift     # Waste reporting, churn hotspots & plan limits
│   ├── GitOutcomeProbe.swift     # Git outcome & code survival measurement
│   ├── FileGuard.swift           # SIP isolation & permission safety checks
│   ├── Theme.swift               # Void black & Cyberpunk neon design tokens
│   └── Views/                    # SwiftUI HUD panels, waveforms & interactive cockpits
├── Tests/FlightdeckTests/        # Unit & integration test suites
├── packaging/flightdeck.rb       # Official Homebrew formula
├── scripts/                      # Build, packaging & notarization scripts
└── site/                         # Next.js marketing portal & interactive simulator
```

---

## 🧩 Adding a New Feature

Follow this standard pattern when contributing a new capability:

### 1. Implement Native Engine Logic
Create or extend an engine in `Sources/Flightdeck/`:
* Implement clean static or synchronous methods for CLI access (e.g. `PortScanner.killPort(_:)`).
* Implement `@Observable` reactive classes for SwiftUI bindings when needed.
* Use native macOS Darwin C APIs (`proc_listpids`, `host_statistics`, `lsof`, `FileManager`).

### 2. Expose in CLI Router
Update `Sources/Flightdeck/CLI.swift`:
* Add the subcommand to `CLI.run(arguments:)`.
* Support human-readable terminal table output by default.
* Support structured JSON output when `--json` is supplied.
* Update `handleHelp()` with documentation and usage examples.

### 3. Add Unit Tests
Add test cases in `Tests/FlightdeckTests/`:
* Use Swift Testing (`@Suite`, `@Test`) or XCTest.
* Ensure tests do not mutate the developer's real machine files. Use temporary directories (`FileManager.default.temporaryDirectory`).
* Verify that all existing tests pass: `swift test`.

---

## 🚀 Creating Pull Requests

1. **Create a Feature Branch**:
   ```bash
   git checkout -b feat/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

2. **Commit Conventions**:
   Follow [Conventional Commits](https://www.conventionalcommits.org/):
   * `feat(ports): add IPv6 socket discovery`
   * `fix(cleaner): handle missing DerivedData gracefully`
   * `docs(readme): document new CLI flags`
   * `test(zombies): add test for NODEV matching`

3. **Verify Locally Before Pushing**:
   ```bash
   swift test
   ```

4. **Submit Pull Request**:
   * Open your PR against the `main` branch.
   * Provide a clear description of the change, why it's needed, and how it was tested.
   * Ensure GitHub Actions CI passes (Swift Native Tests & Next.js Website Build).

---

## 📜 Code of Conduct & Licensing

Flightdeck is licensed under the [MIT License](LICENSE). By contributing, you agree that your contributions will be licensed under the same terms. Be respectful, constructive, and collaborative in all discussions and issue threads.
