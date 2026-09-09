<div align="center">

# ⚡️ FLIGHTDECK

**The Cyberpunk Activity Monitor & Developer Cockpit for macOS**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-00f0ff?style=for-the-badge)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-35%20Passing-39ff88?style=for-the-badge)](Tests/)

*Flightdeck is a hyper-dense, high-performance telemetry dashboard and file intelligence cockpit built purely in Swift & SwiftUI with native Mach kernel and BSD C-level integrations.*

</div>

---

## ✨ Features

### 1. 🛰️ Kernel-Level Telemetry Waveforms
* **Mach `HOST_CPU_LOAD_INFO`**: Reads raw hardware CPU ticks across Performance & Efficiency cores.
* **Mach `HOST_VM_INFO64`**: Measures real physical active, wired, compressed, and total installed memory.
* **BSD `getifaddrs`**: Live rx/tx network throughput across physical interfaces (`en0`, `en1`, WiFi).
* **IOKit Block Storage**: Live storage disk I/O throughput in real time.
* **Interactive Waveforms**: Filter between `[CPU]`, `[MEM]`, `[NET]`, and `[DISK]`, with laser crosshair scanning and HUD hover tooltips.

### 2. 🎯 Process Control & Dual-Layer Kill
* **1-Click PID Termination**: Prominent `✕ KILL` triggers `NSRunningApplication.forceTerminate()` with an immediate POSIX `kill(pid, SIGKILL)` fallback for unbundled CLI tools.
* **Zero-Latency UI Reaction**: Killed processes are instantly removed from the UI state.
* **Energy Drain Detection**: Real-time energy impact leaves (`🍃`) dynamically colored by CPU load.
* **Dynamic Ring Gauges**: Adaptive 3-stage load gauges (Cyan `<30%` → Purple `30–70%` → Neon Red `>70% HIGH LOAD`).

### 3. ⏱️ Focus Tracking & Distraction Radar
* **Zero-Permission App Switching**: Subscribes to `NSWorkspace.didActivateApplicationNotification` for real elapsed foreground durations.
* **Persistent SQLite Storage**: Closed segments are saved to local SQLite so usage totals survive application restarts.
* **Active Idle Detection**: Automatically pauses tracking if the user steps away from keyboard for >120s using `CGEventSource`.
* **Live Focus Score**: Real-time productivity scoring comparing developer environments (`Xcode`, `Cursor`, `Terminal`, `VS Code`) against distractions.

### 4. 📁 Files & Downloads Intelligence
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
└── Tests/FlightdeckTests/        # 35 automated tests across 7 test suites
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

---

## 🔒 Privacy & Permissions
* **Zero Cloud Telemetry**: Everything stays 100% on your local machine.
* **No Elevated Privileges**: Uses standard public macOS APIs (`NSWorkspace`, `getifaddrs`, Mach `host_statistics`, `ps`).

---

<div align="center">
  <sub>Built with 🖤 by Jackpkn.</sub>
</div>
