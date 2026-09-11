<div align="center">

# ⚡️ FLIGHTDECK

**The Cyberpunk Activity Monitor & Developer Cockpit for macOS**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-00f0ff?style=for-the-badge)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-239%20Passing-39ff88?style=for-the-badge)](Tests/)

*Flightdeck is a hyper-dense, high-performance telemetry dashboard and file intelligence cockpit built purely in Swift & SwiftUI with native Mach kernel and BSD C-level integrations.*

</div>

---

## ✨ Features

### 1. 🧠 Claude Code Cockpit — *was the spend worth it?*

Usage meters tell you what you spent. Flightdeck reads the transcripts **and the
repository on disk**, so it can tell you what the spend produced — something no
cloud dashboard can compute.

* **Code survival**: how much of what Claude wrote is still in `HEAD`, per session,
  measured with `git` against your real repo.
* **Cost per outcome**: cost per surviving file and per commit that actually touched
  the files a session wrote — not every commit that happened to land in the window.
* **Waste report**: sessions that cost money and changed no code, tool calls that
  failed and got billed, contexts that kept rebuilding their cache, work done against
  the context ceiling.
* **Churn hotspots**: files Claude keeps having to rewrite across sessions — usually
  where the codebase needs better docs or a `CLAUDE.md` rule.
* **Plan limits**: real five-hour and weekly rate-limit consumption with reset
  countdowns, read from Claude Code's own cached figures.
* **Session forensics**: full conversation turns, tool timeline, per-model token and
  cost breakdown, and one-click resume of any session in your terminal.

Every number is measured or clearly labelled. Where a figure cannot be attributed
honestly — a windowed spend that predates a checkpoint, a cost including a model with
no known price — it is marked (`≤`, `≥`) rather than presented as exact.

### 2. 🛰️ Kernel-Level Telemetry Waveforms
* **Mach `HOST_CPU_LOAD_INFO`**: Reads raw hardware CPU ticks across Performance & Efficiency cores.
* **Mach `HOST_VM_INFO64`**: Measures real physical active, wired, compressed, and total installed memory.
* **BSD `getifaddrs`**: Live rx/tx network throughput across physical interfaces (`en0`, `en1`, WiFi).
* **IOKit Block Storage**: Live storage disk I/O throughput in real time.
* **Interactive Waveforms**: Filter between `[CPU]`, `[MEM]`, `[NET]`, and `[DISK]`, with laser crosshair scanning and HUD hover tooltips.

### 3. 🎯 Process Control & Dual-Layer Kill
* **1-Click PID Termination**: Prominent `✕ KILL` triggers `NSRunningApplication.forceTerminate()` with an immediate POSIX `kill(pid, SIGKILL)` fallback for unbundled CLI tools.
* **Zero-Latency UI Reaction**: Killed processes are instantly removed from the UI state.
* **Energy Drain Detection**: Real-time energy impact leaves (`🍃`) dynamically colored by CPU load.
* **Dynamic Ring Gauges**: Adaptive 3-stage load gauges (Cyan `<30%` → Purple `30–70%` → Neon Red `>70% HIGH LOAD`).

### 4. ⏱️ Focus Tracking & Distraction Radar
* **Zero-Permission App Switching**: Subscribes to `NSWorkspace.didActivateApplicationNotification` for real elapsed foreground durations.
* **Persistent SQLite Storage**: Closed segments are saved to local SQLite so usage totals survive application restarts.
* **Active Idle Detection**: Automatically pauses tracking if the user steps away from keyboard for >120s using `CGEventSource`.
* **Live Focus Score**: Real-time productivity scoring comparing developer environments (`Xcode`, `Cursor`, `Terminal`, `VS Code`) against distractions.

### 5. 📁 Files & Downloads Intelligence
* **Full Disk Access & SIP Guard**: Verifies System Integrity Protection and file permissions before any disk mutations.
* **Instant Syntax Preview**: Fast native code previews with syntax highlighting for JSON, Swift, Python, YAML, and Markdown.
* **Downloads Intelligence**: Categorizes downloads, detects duplicate and stale files (>30 days), and provides bulk-action deletion bars.
* **Disk Radar**: Scans subtrees to uncover largest files and reclaimable developer caches.

---

## 🛠️ Architecture

```text
Flightdeck/
├── Sources/Flightdeck/
│   ├── SystemTelemetry.swift     # Native Mach & BSD C-level hardware sampler
│   ├── ProcessMonitor.swift      # Real process table sampler & PID termination
│   ├── ActivityWatcher.swift     # Foreground app switch & idle tracker
│   ├── ActivityDatabase.swift    # SQLite persistence for activity logs
│   ├── FileGuard.swift           # SIP isolation & permission safety checks
│   ├── FileBrowser.swift         # Fast directory scanning & file operations
│   ├── CockpitAudio.swift        # Sound design & macOS audio triggers
│   ├── Theme.swift               # Void black & Cyberpunk neon design tokens
│   └── Views/                    # SwiftUI HUD panels & interactive charts
└── Tests/FlightdeckTests/        # 213 automated tests across 36 test suites
```

---

## 🚀 Quick Start

### Requirements
* macOS Sonoma (14.0) or later
* Xcode 15+ / Swift 5.10+

### Build & Run
```bash
# Clone the repository
git clone git@github.com:Jackpkn/Flightdeck.git
cd Flightdeck

# Run automated tests
swift test

# Build and launch the desktop app
./scripts/run-app.sh
```

### Connect live Claude Code telemetry (optional)

Flightdeck reads your session transcripts with no setup at all. Installing the
statusline and hooks adds what transcripts don't record — live context-window size,
running cost, and tool events as they happen:

```bash
./scripts/install-claude-hooks.sh
```

Or do it from the app: **Sessions → Set up**, which shows exactly what is wired up,
backs up your `~/.claude/settings.json` before touching it, never replaces a
statusline you configured yourself, and can remove everything again.

### Build a release

```bash
./scripts/release.sh              # universal (arm64 + x86_64) .app and .dmg in dist/

# Signed and notarised, so it opens cleanly on other Macs:
./scripts/setup-notarization.sh   # one-time instructions
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="flightdeck" ./scripts/release.sh
```

---

## 🔒 Privacy & Permissions
* **Zero Cloud Telemetry**: Everything stays 100% on your local machine. No account,
  no upload, no gateway sitting between you and Anthropic.
* **Read-only by default**: Claude Code data is read from `~/.claude/projects/` and
  `~/.claude.json`. The only file Flightdeck ever writes is
  `~/.claude/settings.json`, and only when you install the integration — always after
  taking a timestamped backup.
* **No Elevated Privileges**: Uses standard public macOS APIs (`NSWorkspace`, `getifaddrs`, Mach `host_statistics`, `ps`).

---

<div align="center">
  <sub>Built with 🖤 by Jackpkn.</sub>
</div>
