<div align="center">

# ⚡️ FLIGHTDECK

**The Cyberpunk Activity Monitor & Developer Cockpit for macOS**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6%20%2F%205.10%2B-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Release](https://img.shields.io/badge/Release-v0.1.0-00f0ff?style=for-the-badge)](https://github.com/Jackpkn/Flightdeck/releases/tag/v0.1.0)
[![Tests](https://img.shields.io/badge/Tests-267%20Passing%20(40%20suites)-39ff88?style=for-the-badge)](Tests/)
[![License](https://img.shields.io/badge/License-MIT-00f0ff?style=for-the-badge)](LICENSE)

*Flightdeck is a hyper-dense, high-performance telemetry dashboard and developer cockpit built in Swift & SwiftUI with native Darwin Mach kernel, BSD C-level integrations, and a headless developer CLI.*

[**Website & Live Simulator**](https://flightdeck.netlify.app) &nbsp;&bull;&nbsp; [**Download DMG**](https://github.com/Jackpkn/Flightdeck/releases/tag/v0.1.0) &nbsp;&bull;&nbsp; [**Contributing Guide**](CONTRIBUTING.md)

</div>

---

## 🚀 Installation

### Option 1: Homebrew (Recommended & Zero Gatekeeper Friction)

macOS applies quarantine flags only to browser downloads. Homebrew fetches over `curl`, so an app installed via our tap launches immediately without Gatekeeper warnings:

```bash
brew tap Jackpkn/flightdeck
brew install flightdeck
```

To link Flightdeck into `/Applications` for Spotlight and Dock access:

```bash
ln -sfn "$(brew --prefix flightdeck)/Flightdeck.app" /Applications/Flightdeck.app
```

### Option 2: Standalone Universal DMG

Download the latest universal DMG (`arm64` + `x86_64`) from [GitHub Releases](https://github.com/Jackpkn/Flightdeck/releases/tag/v0.1.0):

1. Download **`Flightdeck-0.1.0.dmg`**
2. Drag `Flightdeck.app` to `/Applications`
3. Clear browser quarantine flag in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Flightdeck.app
   ```

### Option 3: Build from Source

```bash
git clone git@github.com:Jackpkn/Flightdeck.git
cd Flightdeck

# Run full test suite (267 tests)
swift test

# Build and launch GUI cockpit
./scripts/run-app.sh
```

---

## ⚡️ Developer CLI Power Suite

Flightdeck provides a headless CLI that interacts directly with Darwin POSIX and Mach kernel APIs without requiring the graphical application to be open.

```bash
# Run via Homebrew install:
flightdeck <command> [options]

# Or run directly via SwiftPM in repository:
swift run Flightdeck <command> [options]
```

| Command | Description | Useful Flags |
| :--- | :--- | :--- |
| `flightdeck vitals` / `top` | Live Mach kernel CPU, RAM (wired/active), disk I/O, and network throughput | `--json` |
| `flightdeck ports` | Fast Darwin TCP socket inspector with process names and PIDs | `--dev-only`, `--json` |
| `flightdeck kill-port <port>` | Cleanly unbind stuck port (`SIGTERM` &rarr; `SIGKILL`) with system PID protection | |
| `flightdeck clean` / `cruft` | Scan & reclaim gigabytes of disk space from Xcode, SwiftPM, NPM, CocoaPods, Gradle | `--dry-run`, `--force`, `--json` |
| `flightdeck zombies` | Detect runaway developer background processes (`ppid == 1 && NODEV`) | `--kill`, `--json` |
| `flightdeck kill-zombies` | Immediate batch-kill of orphaned developer processes to free RAM | |
| `flightdeck mcp` | Inspect running & configured Model Context Protocol (MCP) servers | `--json` |
| `flightdeck sessions` | List locally tracked Claude Code sessions, token count, and spend | `--json` |
| `flightdeck install-hooks` | Safely configure Claude Code statusline & event hooks in `~/.claude/settings.json` | `--dry-run` |

### CLI Examples

```bash
# Find stuck developer server ports:
flightdeck ports --dev-only

# Kill whichever runaway process is hogging port 3000:
flightdeck kill-port 3000

# Preview reclaimable Xcode and NPM cruft:
flightdeck clean --dry-run

# Free disk space immediately:
flightdeck clean --force

# Find and kill runaway orphan background processes:
flightdeck zombies --kill

# Query configured Model Context Protocol servers in JSON:
flightdeck mcp --json
```

---

## ✨ Graphical Cockpit Features

### 1. 🧠 Claude Code Cockpit — *was the spend worth it?*

Usage meters only tell you what you spent. Flightdeck reads the transcripts **and the local git repository on disk**, computing what your AI spend actually produced:

* **Code survival**: Measures how much code Claude wrote is still in `HEAD`, per session, using native `git diff` probes.
* **Cost per outcome**: Real cost per surviving file and per commit that touched the files a session generated.
* **Waste report**: Flags sessions that incurred cost without changing code, failing tool calls, context rebuild thrashing, and sessions nearing the context ceiling.
* **Churn hotspots**: Uncovers files repeatedly rewritten across multiple sessions &mdash; identifying where codebase documentation or `CLAUDE.md` rules are needed.
* **Plan limits**: Real five-hour and weekly rate-limit consumption with live countdown timers.
* **Session forensics**: Conversation turns, tool timelines, per-model token breakdown, and 1-click terminal session resume.

### 2. 🛰️ Kernel-Level Telemetry Waveforms

* **Mach `HOST_CPU_LOAD_INFO`**: Reads raw hardware CPU ticks across Performance & Efficiency cores.
* **Mach `HOST_VM_INFO64`**: Measures real physical active, wired, compressed, and installed memory.
* **BSD `getifaddrs`**: Live rx/tx network throughput across physical interfaces (`en0`, `en1`, WiFi).
* **IOKit Block Storage**: Live storage disk I/O throughput in real time.
* **Interactive Waveforms**: Filter between `[CPU]`, `[MEM]`, `[NET]`, and `[DISK]` with laser crosshair scanning.

### 3. 🎯 Process Control & Safe Kill

* **1-Click PID Termination**: Prominent `✕ KILL` triggers `NSRunningApplication.forceTerminate()` with an immediate POSIX `kill(pid, SIGKILL)` fallback.
* **Zero-Latency UI Reaction**: Terminated processes are removed instantly from the table.
* **Energy Impact Tracking**: Real-time energy drain metrics dynamically colored by CPU core usage.
* **System PID Protection**: Never allows accidental termination of PID 0 (kernel), PID 1 (launchd), or Flightdeck itself.

### 4. ⏱️ Focus Tracking & Distraction Radar

* **Zero-Permission App Switching**: Subscribes to `NSWorkspace.didActivateApplicationNotification` for real elapsed foreground durations.
* **Persistent SQLite Storage**: Segment histories persist across application restarts via an embedded GRDB SQLite database.
* **Active Idle Detection**: Automatically pauses tracking when stepping away for >120s using `CGEventSource`.
* **Live Focus Score**: Computes productivity ratios comparing developer toolchains against distractions.

### 5. 📁 Disk Intelligence & Deep App Uninstaller

* **Full Disk Access & SIP Guard**: Verifies System Integrity Protection and permissions before performing disk operations.
* **Developer Cruft Cleaner**: Identifies DerivedData, CocoaPods, SwiftPM, Gradle, and NPM caches.
* **Deep App Uninstaller**: Discovers orphaned leftovers in `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Preferences`, and `LaunchAgents`.
* **Downloads Intelligence**: Detects stale downloads (>30 days) and duplicate files with SHA-256 validation.

---

## 🛠️ Architecture

```text
Flightdeck/
├── Sources/Flightdeck/
│   ├── CLI.swift                 # Subcommand router, table formatters & JSON emitters
│   ├── PortScanner.swift         # Native Darwin TCP port scanner & POSIX socket kill
│   ├── DevCleaner.swift          # Developer cruft discovery (Xcode, SPM, NPM, Gradle, CocoaPods)
│   ├── ZombieDetector.swift      # Runaway orphan developer process scanner (ppid == 1 && NODEV)
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
├── Tests/FlightdeckTests/        # 267 automated tests across 40 test suites
├── packaging/flightdeck.rb       # Official Homebrew formula
├── scripts/                      # Build, release, packaging & run automation
└── site/                         # Next.js marketing portal & interactive simulator
```

---

## 🧪 Testing & CI

Flightdeck maintains 100% test coverage across all Darwin Mach kernel samplers, SQLite storage, port scanners, and developer tools:

```bash
# Run full test suite
swift test

# Run specific suite
swift test --filter PortScannerTests
swift test --filter DevCleanerTests
swift test --filter ZombieDetectorTests
swift test --filter CLITests
```

Automated GitHub Actions CI runs on both **macOS 15 (Sequoia)** and **Ubuntu** on every pull request and push to `main`.

---

## 🔒 Privacy & Permissions

* **Zero Cloud Telemetry**: Everything stays 100% on your local machine. No external servers, no tracking, and no gateway between you and Anthropic.
* **Non-Destructive by Default**: Claude Code transcript ingestion is read-only.
* **Transparent Hook Configuration**: The only file Flightdeck touches is `~/.claude/settings.json`, strictly upon explicit user request, always after generating a timestamped backup.
* **No Elevated Daemon Required**: Operates using public macOS system frameworks and POSIX kernel interfaces.

---

## 🤝 Contributing

We welcome contributions! Please review our [**Contributing Guide**](CONTRIBUTING.md) for details on our coding standards, local development workflow, and pull request process.

---

<div align="center">
  <sub>Built with 🖤 by Jackpkn. Licensed under the MIT License.</sub>
</div>
