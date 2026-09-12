"use client";

import React, { useState, useEffect } from "react";
import {
  Activity,
  Terminal,
  Cpu,
  HardDrive,
  DollarSign,
  AlertCircle,
  CheckCircle2,
  Trash2,
  Play,
  Pause,
  Sparkles,
  RotateCcw,
  Zap,
  Layers,
  ArrowUpRight,
  Database,
  Radio,
  FileCode,
  Flame,
  Clock,
  Filter,
} from "lucide-react";

type DeckTab = "claude" | "telemetry" | "process" | "storage" | "waste";

interface ProcessItem {
  pid: number;
  name: string;
  cpu: number;
  mem: string;
  energy: "normal" | "high" | "critical";
  category: "dev" | "system" | "lsp";
  killed?: boolean;
}

interface TrackedFile {
  id: number;
  name: string;
  path: string;
  status: "kept" | "reverted";
  cost: string;
  lines: number;
  commits: number;
}

const TRACKED_FILES: TrackedFile[] = [
  { id: 1, name: "SessionInsights.swift", path: "Sources/Flightdeck/SessionInsights.swift", status: "kept", cost: "$2.35", lines: 482, commits: 3 },
  { id: 2, name: "MachKernel.swift", path: "Sources/Flightdeck/MachKernel.swift", status: "kept", cost: "$1.84", lines: 312, commits: 2 },
  { id: 3, name: "DiskRadar.swift", path: "Sources/Flightdeck/DiskRadar.swift", status: "kept", cost: "$0.92", lines: 194, commits: 1 },
  { id: 4, name: "TerminalParser.swift", path: "Sources/Flightdeck/TerminalParser.swift", status: "reverted", cost: "$1.20", lines: 88, commits: 1 },
  { id: 5, name: "HonestyEngine.swift", path: "Sources/Flightdeck/HonestyEngine.swift", status: "kept", cost: "$2.10", lines: 340, commits: 2 },
  { id: 6, name: "POSIXKillBridge.c", path: "Sources/Flightdeck/POSIXKillBridge.c", status: "kept", cost: "$0.65", lines: 96, commits: 1 },
];

const INITIAL_PROCESSES: ProcessItem[] = [
  { pid: 48921, name: "claude-code (CLI daemon)", cpu: 28.4, mem: "1.12 GB", energy: "high", category: "dev" },
  { pid: 14209, name: "com.apple.WebKit.GPU", cpu: 34.2, mem: "820 MB", energy: "critical", category: "system" },
  { pid: 51290, name: "swift-frontend (indexing)", cpu: 62.1, mem: "1.84 GB", energy: "critical", category: "dev" },
  { pid: 32110, name: "node (turbopack dev)", cpu: 14.2, mem: "412 MB", energy: "high", category: "dev" },
  { pid: 18042, name: "Docker Desktop (backend)", cpu: 6.8, mem: "2.35 GB", energy: "normal", category: "system" },
  { pid: 9024, name: "rust-analyzer", cpu: 1.1, mem: "320 MB", energy: "normal", category: "lsp" },
  { pid: 61832, name: "clangd (LSP engine)", cpu: 22.4, mem: "860 MB", energy: "high", category: "lsp" },
];

export default function CockpitSimulator() {
  const [activeTab, setActiveTab] = useState<DeckTab>("claude");
  const [processes, setProcesses] = useState<ProcessItem[]>(INITIAL_PROCESSES);
  const [processFilter, setProcessFilter] = useState<string>("all");
  const [selectedFile, setSelectedFile] = useState<TrackedFile>(TRACKED_FILES[0]);
  const [killToast, setKillToast] = useState<string | null>(null);
  const [hoverPoint, setHoverPoint] = useState<{ idx: number; val: number } | null>(null);
  const [tilt, setTilt] = useState({ x: 0, y: 0 });

  // Auto-Tour Showcase State
  const [isAutoTour, setIsAutoTour] = useState(false);
  const [scanWipeKey, setScanWipeKey] = useState(0);
  const [tourProgress, setTourProgress] = useState(0);
  const [spectrumBars, setSpectrumBars] = useState<number[]>([
    38, 65, 24, 88, 52, 76, 34, 94, 48, 62, 28, 80, 56, 36, 70, 44
  ]);

  // Simulated live telemetry waveform points
  const [wavePoints, setWavePoints] = useState<number[]>([
    24, 30, 28, 45, 62, 58, 40, 35, 78, 85, 72, 60, 48, 38, 52, 64, 45, 30, 25, 40
  ]);

  // Live Mach Bus Micro-Spectrum Equalizer
  useEffect(() => {
    const timer = setInterval(() => {
      setSpectrumBars((prev) =>
        prev.map(() => Math.floor(Math.random() * 75) + 20)
      );
    }, 120);
    return () => clearInterval(timer);
  }, []);

  // Auto-Tour Cockpit Showcase Mode Ticker
  useEffect(() => {
    if (!isAutoTour) {
      setTourProgress(0);
      return;
    }

    const tabs: DeckTab[] = ["claude", "telemetry", "process", "storage", "waste"];
    const DURATION = 4200;
    const INTERVAL = 50;
    let elapsed = 0;

    const progressTimer = setInterval(() => {
      elapsed += INTERVAL;
      const pct = Math.min((elapsed / DURATION) * 100, 100);
      setTourProgress(pct);

      if (elapsed >= DURATION) {
        elapsed = 0;
        setActiveTab((curr) => {
          const nextIdx = (tabs.indexOf(curr) + 1) % tabs.length;
          setScanWipeKey((k) => k + 1);
          return tabs[nextIdx];
        });
      }
    }, INTERVAL);

    return () => clearInterval(progressTimer);
  }, [isAutoTour]);

  const handleTabClick = (tab: DeckTab) => {
    if (activeTab !== tab) {
      setActiveTab(tab);
      setScanWipeKey((k) => k + 1);
    }
  };

  useEffect(() => {
    const interval = setInterval(() => {
      setWavePoints((prev) => {
        const nextVal = Math.floor(Math.random() * 55) + 20;
        return [...prev.slice(1), nextVal];
      });
    }, 1200);
    return () => clearInterval(interval);
  }, []);

  const handleKill = (pid: number, name: string) => {
    setProcesses((prev) =>
      prev.map((p) => (p.pid === pid ? { ...p, killed: true } : p))
    );
    setKillToast(`POSIX kill(${pid}, SIGKILL) succeeded. Process ${name} terminated with 0ms UI lag.`);
    setTimeout(() => setKillToast(null), 3500);
  };

  const handleResetProcesses = () => {
    setProcesses(INITIAL_PROCESSES);
    setKillToast("Process list reset to baseline.");
    setTimeout(() => setKillToast(null), 2000);
  };

  const filteredProcesses = processes.filter((p) => {
    if (processFilter === "heavy") return p.cpu > 20;
    if (processFilter === "dev") return p.category === "dev";
    return true;
  });

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width - 0.5) * 6; // Max 3 deg tilt
    const y = ((e.clientY - rect.top) / rect.height - 0.5) * -6;
    setTilt({ x: y, y: x });
  };

  const handleMouseLeave = () => {
    setTilt({ x: 0, y: 0 });
  };

  return (
    <section
      id="forensics"
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      className="relative max-w-[1240px] mx-auto px-4 sm:px-6 py-20 md:py-28 overflow-hidden"
    >
      {/* ── Background Cyberpunk Radar Grid & Atmospheric Rings (Living & Visible) ── */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden select-none">
        {/* Active Expanding Radar Wave Pulse */}
        <div className="absolute top-1/2 left-1/2 w-[980px] h-[980px] rounded-full border border-[#ff6363]/30 animate-radar-pulse-ring" />

        {/* Crisp Concentric Telemetry Circles */}
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[850px] h-[850px] rounded-full border border-dashed border-[#363739]/60" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] rounded-full border border-[#363739]/50" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[380px] h-[380px] rounded-full border border-[#ff6363]/25" />

        {/* Rotating Radar Crosshair Sweep Line */}
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[720px] h-[720px] rounded-full animate-[spin_24s_linear_infinite]">
          <div className="w-full h-full border border-dotted border-white/15 rounded-full" />
          <div className="absolute top-1/2 left-1/2 w-1/2 h-[1px] bg-gradient-to-r from-[#ff6363]/60 via-[#63a1ff]/40 to-transparent origin-left" />
        </div>

        {/* Ambient atmospheric glow pools with smooth breathing aurora */}
        <div
          className="absolute top-1/4 left-1/4 w-[540px] h-[360px] rounded-full opacity-40 animate-aurora-left"
          style={{
            background: "radial-gradient(circle, #143ca3 0%, transparent 70%)",
            filter: "blur(60px)",
          }}
        />
        <div
          className="absolute bottom-1/4 right-1/4 w-[480px] h-[320px] rounded-full opacity-45 animate-aurora-right"
          style={{
            background: "radial-gradient(circle, #ff6363 0%, transparent 70%)",
            filter: "blur(70px)",
          }}
        />
      </div>

      {/* Eyebrow & Headline */}
      <div className="relative z-10 text-center mb-12">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-3 shadow-[0_2px_8px_rgba(0,0,0,0.6)]">
          <Activity className="w-3.5 h-3.5 text-[#ff6363] animate-pulse" />
          <span>Interactive macOS Cockpit Preview</span>
          <span className="text-[#363739]">·</span>
          <span className="text-[#56c2ff]">MACH C KERNEL</span>
        </div>

        <h2 className="text-[34px] sm:text-[48px] font-normal text-white tracking-tight leading-tight">
          One Window.{" "}
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-[#ff6363] to-[#63a1ff] animate-text-shimmer font-medium">
            Zero Inventions.
          </span>
        </h2>

        <p className="text-[15px] sm:text-[17px] text-[#9c9c9d] max-w-[640px] mx-auto mt-2 leading-relaxed">
          Switch between live instrument decks below — examine Claude Code outcome survival, explore the 55-file git ledger, scrub kernel waveforms, or test 1-click POSIX process kill.
        </p>

        {/* Dynamic Telemetry Strip with Live Spectrum Bars & Auto-Tour Toggle */}
        <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
          {/* Real-time Status Ticker */}
          <div className="inline-flex items-center gap-3 px-3.5 py-1.5 rounded-full bg-[#07080a] border border-[#363739]/80 text-[11px] font-mono text-[#6a6b6c] shadow-[rgba(255,255,255,0.03)_0px_1px_0px_0px_inset]">
            <span className="flex items-center gap-1.5 text-[#59d499]">
              <span className="w-2 h-2 rounded-full bg-[#59d499] animate-ping" />
              LIVE FEED
            </span>
            <span className="text-[#2f3031]">|</span>
            <span className="text-[#9c9c9d]">MACH_PORT 0x4A1B</span>
            <span className="text-[#2f3031]">|</span>
            <span className="text-[#56c2ff]">1000Hz TICK</span>
            <span className="text-[#2f3031]">|</span>
            <span className="text-white hidden sm:inline">GIT HEAD SYNCED</span>
          </div>

          {/* Mach Kernel Frequency Micro-Equalizer */}
          <div className="hidden md:inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#07080a] border border-[#363739]/80 text-[11px] font-mono shadow-[rgba(255,255,255,0.03)_0px_1px_0px_0px_inset]">
            <span className="text-[#6a6b6c] text-[10px] tracking-wider uppercase">BUS:</span>
            <div className="flex items-end gap-[3px] h-3.5 w-24 px-1">
              {spectrumBars.map((val, i) => (
                <span
                  key={i}
                  className={`w-[3px] rounded-full transition-all duration-100 ${
                    val > 70
                      ? "bg-[#ff6363]"
                      : val > 45
                      ? "bg-[#56c2ff]"
                      : "bg-[#363739]"
                  }`}
                  style={{ height: `${val}%` }}
                />
              ))}
            </div>
            <span className="text-[#59d499] text-[10px]">0.0ms TAX</span>
          </div>

          {/* Interactive Auto-Tour / Showcase Mode Button */}
          <button
            onClick={() => setIsAutoTour(!isAutoTour)}
            className={`inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full text-[12px] font-mono transition-all duration-200 border ${
              isAutoTour
                ? "bg-[#452324] border-[#ff6363] text-white shadow-[0_0_14px_rgba(255,99,99,0.4)]"
                : "bg-[#111214] border-[#363739] text-[#e6e6e6] hover:bg-white/5 hover:border-white/20"
            }`}
          >
            {isAutoTour ? (
              <>
                <Pause className="w-3.5 h-3.5 text-[#ff6363]" />
                <span>Pause Auto-Tour</span>
                <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
              </>
            ) : (
              <>
                <Play className="w-3.5 h-3.5 text-[#ff6363] fill-[#ff6363]" />
                <span>Play Showcase</span>
                <span className="text-[10px] px-1.5 py-0.2 rounded bg-white/10 text-[#9c9c9d]">5 Decks</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* ── Outer Tactical Bracket Frame with Corner Accents ── */}
      <div
        className="relative group transition-transform duration-300 ease-out"
        style={{
          transform: `perspective(1200px) rotateX(${tilt.x}deg) rotateY(${tilt.y}deg)`,
          transformStyle: "preserve-3d",
        }}
      >
        {/* High-Tech Hairline Corner Brackets */}
        <div className="absolute -top-3 -left-3 w-6 h-6 border-t-2 border-l-2 border-[#ff6363]/60 pointer-events-none z-20">
          <span className="absolute top-0 left-0 w-1 h-1 bg-[#ff6363] shadow-[0_0_8px_#ff6363]" />
        </div>
        <div className="absolute -top-3 -right-3 w-6 h-6 border-t-2 border-r-2 border-[#63a1ff]/60 pointer-events-none z-20">
          <span className="absolute top-0 right-0 w-1 h-1 bg-[#63a1ff] shadow-[0_0_8px_#63a1ff]" />
        </div>
        <div className="absolute -bottom-3 -left-3 w-6 h-6 border-b-2 border-l-2 border-[#59d499]/60 pointer-events-none z-20">
          <span className="absolute bottom-0 left-0 w-1 h-1 bg-[#59d499] shadow-[0_0_8px_#59d499]" />
        </div>
        <div className="absolute -bottom-3 -right-3 w-6 h-6 border-b-2 border-r-2 border-white/40 pointer-events-none z-20">
          <span className="absolute bottom-0 right-0 w-1 h-1 bg-white shadow-[0_0_8px_white]" />
        </div>

        {/* ── Traveling Laser Border Beam (Conic Gradient) ── */}
        <div className="absolute -inset-[1px] rounded-[17px] overflow-hidden pointer-events-none z-10 opacity-75 group-hover:opacity-100 transition-opacity">
          <div
            className="absolute inset-[-150%] animate-[spin_7s_linear_infinite]"
            style={{
              background:
                "conic-gradient(from 0deg, transparent 0 320deg, rgba(255, 99, 99, 0.9) 350deg, rgba(99, 161, 255, 0.9) 360deg)",
            }}
          />
        </div>

        {/* Ambient perimeter depth glow */}
        <div
          className="absolute -inset-2 rounded-[22px] bg-gradient-to-r from-[#143ca3]/20 via-[#ff6363]/15 to-[#63a1ff]/20 blur-2xl opacity-70 group-hover:opacity-100 transition-opacity duration-700 pointer-events-none"
        />

        {/* ── Main App Window Mockup ── */}
        <div
          className="relative rounded-[16px] bg-[#07080a] border border-[#363739] window-shadow overflow-hidden transition-all duration-300 z-10"
          style={{
            boxShadow:
              "rgba(255, 255, 255, 0.05) 0px 1px 0px 0px inset, rgba(255, 255, 255, 0.2) 0px 0px 0px 1px, rgba(0, 0, 0, 0.85) 0px 30px 100px 15px",
          }}
        >
          {/* Laser Scanline Sweep Effect on Tab Change / Tour Cycle */}
          <div
            key={scanWipeKey}
            className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-transparent via-[#ff6363]/15 via-[#63a1ff]/10 to-transparent pointer-events-none z-30 animate-scanline-wipe"
          />

          {/* Window Chrome / Titlebar with specular sheen */}
          <div className="relative h-11 px-4 bg-[#07080a] border-b border-[#363739]/80 flex items-center justify-between select-none">
            {/* macOS Traffic Lights */}
            <div className="flex items-center gap-2">
              <span className="w-3 h-3 rounded-full bg-[#ff5f56] border border-[#e0443e]/50 cursor-pointer hover:opacity-80" />
              <span className="w-3 h-3 rounded-full bg-[#ffbd2e] border border-[#dea123]/50 cursor-pointer hover:opacity-80" />
              <span className="w-3 h-3 rounded-full bg-[#27c93f] border border-[#1aab29]/50 cursor-pointer hover:opacity-80" />
              <span className="ml-3 text-[11px] font-mono text-[#6a6b6c] hidden sm:inline">
                Flightdeck v0.8.4 &middot; ~/Projects/Flightdeck
              </span>
            </div>

            {/* Window status indicator */}
            <div className="flex items-center gap-2 text-[11px] font-mono text-[#9c9c9d]">
              <span className="w-2 h-2 rounded-full bg-[#59d499] animate-ping" />
              <span className="text-[#59d499]">MACH KERNEL ACTIVE</span>
              <span className="text-[#2f3031]">|</span>
              <span className="hidden md:inline text-[#6a6b6c]">HOST_CPU_LOAD_INFO</span>
            </div>
          </div>

          {/* Command Bar / Deck Tabs Switcher */}
          <div className="px-4 py-2 bg-[#040506] border-b border-[#363739]/60 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-1.5 overflow-x-auto py-1">
              <button
                onClick={() => handleTabClick("claude")}
                className={`relative overflow-hidden flex items-center gap-2 px-3.5 py-1.5 rounded-[8px] text-[13px] font-medium transition-all ${
                  activeTab === "claude"
                    ? "bg-[#1b1c1e] text-[#ffffff] shadow-[rgba(255,255,255,0.06)_0px_1px_0px_0px_inset] border border-white/10"
                    : "text-[#9c9c9d] hover:text-[#ffffff] hover:bg-white/5"
                }`}
              >
                {activeTab === "claude" && isAutoTour && (
                  <span
                    className="absolute bottom-0 left-0 h-[2px] bg-[#ff6363] transition-all duration-75"
                    style={{ width: `${tourProgress}%` }}
                  />
                )}
                <DollarSign className={`w-3.5 h-3.5 ${activeTab === "claude" ? "text-[#ff6363]" : "text-[#6a6b6c]"}`} />
                <span>Claude Forensics</span>
                <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-black/40 text-[#9c9c9d]">⌘1</span>
              </button>

              <button
                onClick={() => handleTabClick("telemetry")}
                className={`relative overflow-hidden flex items-center gap-2 px-3.5 py-1.5 rounded-[8px] text-[13px] font-medium transition-all ${
                  activeTab === "telemetry"
                    ? "bg-[#1b1c1e] text-[#ffffff] shadow-[rgba(255,255,255,0.06)_0px_1px_0px_0px_inset] border border-white/10"
                    : "text-[#9c9c9d] hover:text-[#ffffff] hover:bg-white/5"
                }`}
              >
                {activeTab === "telemetry" && isAutoTour && (
                  <span
                    className="absolute bottom-0 left-0 h-[2px] bg-[#56c2ff] transition-all duration-75"
                    style={{ width: `${tourProgress}%` }}
                  />
                )}
                <Activity className={`w-3.5 h-3.5 ${activeTab === "telemetry" ? "text-[#56c2ff]" : "text-[#6a6b6c]"}`} />
                <span>Mach Waveforms</span>
                <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-black/40 text-[#9c9c9d]">⌘2</span>
              </button>

              <button
                onClick={() => handleTabClick("process")}
                className={`relative overflow-hidden flex items-center gap-2 px-3.5 py-1.5 rounded-[8px] text-[13px] font-medium transition-all ${
                  activeTab === "process"
                    ? "bg-[#1b1c1e] text-[#ffffff] shadow-[rgba(255,255,255,0.06)_0px_1px_0px_0px_inset] border border-white/10"
                    : "text-[#9c9c9d] hover:text-[#ffffff] hover:bg-white/5"
                }`}
              >
                {activeTab === "process" && isAutoTour && (
                  <span
                    className="absolute bottom-0 left-0 h-[2px] bg-[#59d499] transition-all duration-75"
                    style={{ width: `${tourProgress}%` }}
                  />
                )}
                <Cpu className={`w-3.5 h-3.5 ${activeTab === "process" ? "text-[#59d499]" : "text-[#6a6b6c]"}`} />
                <span>Process Kill</span>
                <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-black/40 text-[#9c9c9d]">⌘3</span>
              </button>

              <button
                onClick={() => handleTabClick("storage")}
                className={`relative overflow-hidden flex items-center gap-2 px-3.5 py-1.5 rounded-[8px] text-[13px] font-medium transition-all ${
                  activeTab === "storage"
                    ? "bg-[#1b1c1e] text-[#ffffff] shadow-[rgba(255,255,255,0.06)_0px_1px_0px_0px_inset] border border-white/10"
                    : "text-[#9c9c9d] hover:text-[#ffffff] hover:bg-white/5"
                }`}
              >
                {activeTab === "storage" && isAutoTour && (
                  <span
                    className="absolute bottom-0 left-0 h-[2px] bg-[#e6e6e6] transition-all duration-75"
                    style={{ width: `${tourProgress}%` }}
                  />
                )}
                <HardDrive className={`w-3.5 h-3.5 ${activeTab === "storage" ? "text-[#e6e6e6]" : "text-[#6a6b6c]"}`} />
                <span>Disk Cruft</span>
                <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-black/40 text-[#9c9c9d]">⌘4</span>
              </button>

              <button
                onClick={() => handleTabClick("waste")}
                className={`relative overflow-hidden flex items-center gap-2 px-3.5 py-1.5 rounded-[8px] text-[13px] font-medium transition-all ${
                  activeTab === "waste"
                    ? "bg-[#1b1c1e] text-[#ffffff] shadow-[rgba(255,255,255,0.06)_0px_1px_0px_0px_inset] border border-white/10"
                    : "text-[#9c9c9d] hover:text-[#ffffff] hover:bg-white/5"
                }`}
              >
                {activeTab === "waste" && isAutoTour && (
                  <span
                    className="absolute bottom-0 left-0 h-[2px] bg-[#ff6363] transition-all duration-75"
                    style={{ width: `${tourProgress}%` }}
                  />
                )}
                <Flame className={`w-3.5 h-3.5 ${activeTab === "waste" ? "text-[#ff6363]" : "text-[#6a6b6c]"}`} />
                <span>Waste &amp; Churn</span>
                <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-[#ff6363]/20 text-[#ff6363]">NEW</span>
              </button>
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={() => setIsAutoTour(!isAutoTour)}
                className="hidden sm:flex items-center gap-1.5 px-2.5 py-1 rounded-[6px] text-[11px] font-mono text-[#9c9c9d] hover:text-white bg-white/5 hover:bg-white/10 transition-colors border border-white/5"
              >
                {isAutoTour ? (
                  <>
                    <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
                    <span className="text-[#ff6363]">Auto-Touring</span>
                  </>
                ) : (
                  <>
                    <Sparkles className="w-3 h-3 text-[#ff6363]" />
                    <span>Auto-Tour</span>
                  </>
                )}
              </button>
              <div className="text-[11px] font-mono text-[#6a6b6c] hidden lg:block">
                Target: <span className="text-[#9c9c9d]">~/Projects/Flightdeck</span>
              </div>
            </div>
          </div>

        {/* ── Toast Notification Banner ── */}
        {killToast && (
          <div className="px-4 py-2.5 bg-[#452324] border-b border-[#ff6363]/40 flex items-center justify-between text-[12px] font-mono text-[#ffffff] animate-in fade-in duration-200">
            <span className="flex items-center gap-2">
              <Zap className="w-3.5 h-3.5 text-[#ff6363]" />
              {killToast}
            </span>
            <button
              onClick={() => setKillToast(null)}
              className="text-[#9c9c9d] hover:text-white"
            >
              ✕
            </button>
          </div>
        )}

        {/* ── Tab Panels ── */}
        <div className="p-6 bg-[#07080a] min-h-[480px]">
          {/* TAB 1: CLAUDE CODE FORENSICS */}
          {activeTab === "claude" && (
            <div className="space-y-6">
              {/* Session Meta Bar */}
              <div className="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-[#363739]/60">
                <div className="flex items-center gap-3">
                  <span className="px-2 py-0.5 rounded-[4px] bg-[#111214] border border-[#363739] text-[12px] font-mono text-[#ffffff]">
                    Session 41d7a11b
                  </span>
                  <span className="text-[13px] text-[#9c9c9d]">
                    Claude 3.7 Sonnet &middot; 48 turns &middot; 1h 42m duration
                  </span>
                </div>
                <div className="flex items-center gap-2 text-[12px] font-mono">
                  <span className="text-[#6a6b6c]">Checked against git HEAD:</span>
                  <span className="text-[#59d499] flex items-center gap-1">
                    <CheckCircle2 className="w-3.5 h-3.5" /> 100% Deterministic
                  </span>
                </div>
              </div>

              {/* Instrument Gauges & Stats Grid */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                {/* Dial 1: Code Survival */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow flex flex-col justify-between">
                  <div className="flex items-center justify-between text-[12px] font-medium text-[#9c9c9d]">
                    <span>Code Survival</span>
                    <span className="text-[#59d499] text-[11px] font-mono">HEAD match</span>
                  </div>
                  <div className="my-3 flex items-baseline gap-3">
                    <span className="text-[32px] font-medium text-[#ffffff] tracking-tight">
                      96.4%
                    </span>
                    <span className="text-[12px] font-mono text-[#9c9c9d]">
                      53 of 55 files
                    </span>
                  </div>
                  {/* Visual ratio bar */}
                  <div className="w-full h-1.5 rounded-full bg-[#1b1c1e] overflow-hidden flex">
                    <div className="h-full bg-[#59d499]" style={{ width: "96.4%" }} />
                    <div className="h-full bg-[#ff6363]" style={{ width: "3.6%" }} />
                  </div>
                </div>

                {/* Dial 2: Weekly Plan Limit */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow flex flex-col justify-between">
                  <div className="flex items-center justify-between text-[12px] font-medium text-[#9c9c9d]">
                    <span>Weekly Plan Limit</span>
                    <span className="px-1.5 py-0.5 rounded-[4px] bg-[#1b1c1e] text-[10px] font-mono text-[#9c9c9d] border border-white/5">
                      5d old cache
                    </span>
                  </div>
                  <div className="my-3 flex items-baseline gap-3">
                    <span className="text-[32px] font-medium text-[#ffffff] tracking-tight">
                      3%
                    </span>
                    <span className="text-[12px] font-mono text-[#6a6b6c]">
                      Reset in 2d 14h
                    </span>
                  </div>
                  <div className="w-full h-1.5 rounded-full bg-[#1b1c1e] overflow-hidden">
                    <div className="h-full bg-[#56c2ff]" style={{ width: "3%" }} />
                  </div>
                </div>

                {/* Stat 3: Session Spend */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow flex flex-col justify-between">
                  <div className="text-[12px] font-medium text-[#9c9c9d]">
                    Total Session Cost
                  </div>
                  <div className="my-3">
                    <span className="text-[32px] font-medium text-[#ffffff] tracking-tight">
                      $72.96
                    </span>
                  </div>
                  <div className="text-[11px] font-mono text-[#6a6b6c]">
                    Exact from cost-state (no deltas)
                  </div>
                </div>

                {/* Stat 4: Cost Per Surviving File */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow flex flex-col justify-between">
                  <div className="text-[12px] font-medium text-[#9c9c9d]">
                    Cost Per Surviving File
                  </div>
                  <div className="my-3">
                    <span className="text-[32px] font-medium text-[#ff6363] tracking-tight">
                      $2.3518
                    </span>
                  </div>
                  <div className="text-[11px] font-mono text-[#6a6b6c]">
                    $72.96 &divide; 53 surviving files
                  </div>
                </div>
              </div>

              {/* Survival Breakdown & File Matrix */}
              <div className="p-5 rounded-[12px] bg-[#040506] border border-[#363739]/60 key-shadow">
                <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
                  <span className="text-[12px] font-mono text-[#9c9c9d]">
                    Repository File Fate Matrix (55 files written in session) &middot; Click any file to inspect
                  </span>
                  <div className="flex items-center gap-4 text-[11px] font-mono">
                    <span className="flex items-center gap-1.5 text-[#e6e6e6]">
                      <span className="w-2.5 h-2.5 rounded-[2px] bg-[#59d499]" />
                      53 Still in HEAD
                    </span>
                    <span className="flex items-center gap-1.5 text-[#ff6363]">
                      <span className="w-2.5 h-2.5 rounded-[2px] bg-[#ff6363]" />
                      2 Reverted / Deleted
                    </span>
                  </div>
                </div>

                {/* Tactile File Block Grid */}
                <div className="grid grid-cols-11 sm:grid-cols-18 md:grid-cols-28 gap-1.5 py-2">
                  {Array.from({ length: 55 }).map((_, i) => {
                    const isReverted = i === 14 || i === 38;
                    const isSelected = selectedFile.id === (i % 7) + 1;
                    return (
                      <button
                        key={i}
                        onClick={() => {
                          const file = TRACKED_FILES[i % TRACKED_FILES.length];
                          setSelectedFile(file);
                        }}
                        title={`File #${i + 1}: ${isReverted ? "Reverted" : "Surviving in HEAD"}`}
                        className={`h-4.5 rounded-[3px] transition-all cursor-pointer ${
                          isSelected ? "ring-2 ring-white scale-125 z-10" : ""
                        } ${
                          isReverted ? "bg-[#ff6363]" : "bg-[#59d499]/80 hover:bg-[#59d499]"
                        }`}
                      />
                    );
                  })}
                </div>

                {/* Selected File Detailed Card */}
                {selectedFile && (
                  <div className="mt-4 p-3 rounded-[8px] bg-[#111214] border border-[#363739]/80 flex flex-wrap items-center justify-between gap-3 text-[12px] font-mono">
                    <div className="flex items-center gap-2">
                      <FileCode className="w-4 h-4 text-[#ff6363]" />
                      <span className="text-white font-medium">{selectedFile.path}</span>
                      <span
                        className={`text-[10px] px-1.5 py-0.5 rounded ${
                          selectedFile.status === "kept"
                            ? "bg-[#59d499]/15 text-[#59d499]"
                            : "bg-[#ff6363]/15 text-[#ff6363]"
                        }`}
                      >
                        {selectedFile.status === "kept" ? "SURVIVING IN HEAD" : "REVERTED / REMOVED"}
                      </span>
                    </div>
                    <div className="flex items-center gap-4 text-[#9c9c9d]">
                      <span>Cost: <b className="text-white">{selectedFile.cost}</b></span>
                      <span>Lines: <b className="text-white">{selectedFile.lines}</b></span>
                      <span>Commits: <b className="text-white">{selectedFile.commits}</b></span>
                    </div>
                  </div>
                )}

                {/* Truth Warning Box */}
                <div className="mt-4 p-3.5 rounded-[8px] bg-[#111214] border border-[#363739]/60 flex items-start gap-3 text-[12px] text-[#9c9c9d] leading-relaxed">
                  <AlertCircle className="w-4 h-4 text-[#ff6363] shrink-0 mt-0.5" />
                  <div>
                    <span className="font-medium text-white">Why naive cloud calculators are 200% off: </span>
                    Claude Code writes <em>cumulative</em> cost records, not deltas. Blindly summing turn records results in <span className="text-[#ff6363] font-mono">$145.93</span> instead of the real <span className="text-white font-mono">$72.96</span>. Flightdeck decodes the raw SQLite ledger to report truth.
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: MACH KERNEL WAVEFORMS */}
          {activeTab === "telemetry" && (
            <div className="space-y-6">
              <div className="flex items-center justify-between pb-3 border-b border-[#363739]/60">
                <div>
                  <span className="text-[13px] font-medium text-white">
                    Mach Hardware Telemetry
                  </span>
                  <span className="text-[12px] text-[#6a6b6c] ml-2">
                    Reading HOST_CPU_LOAD_INFO & HOST_VM_INFO64 via Mach Port
                  </span>
                </div>
                <span className="px-2 py-0.5 rounded-[4px] bg-[#111214] text-[11px] font-mono text-[#56c2ff] border border-[#56c2ff]/30">
                  1000Hz Kernel Poll
                </span>
              </div>

              {/* Waveform Graph Canvas */}
              <div
                className="p-4 rounded-[12px] bg-[#040506] border border-[#363739] key-shadow relative cursor-crosshair"
                onMouseLeave={() => setHoverPoint(null)}
              >
                <div className="flex justify-between items-center text-[11px] font-mono text-[#6a6b6c] mb-2">
                  <span>LIVE CPU WAVEFORM (P-CORES & E-CORES)</span>
                  <span className="text-[#56c2ff]">
                    {hoverPoint ? `SCRUB T-${20 - hoverPoint.idx}s: ${hoverPoint.val}% LOAD` : `CUR: ${wavePoints[wavePoints.length - 1]}%`}
                  </span>
                </div>

                {/* SVG Polyline Graph with Scrubbing */}
                <div className="h-44 w-full flex items-end relative">
                  <svg className="w-full h-full overflow-visible">
                    <defs>
                      <linearGradient id="waveGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#63a1ff" stopOpacity="0.4" />
                        <stop offset="100%" stopColor="#63a1ff" stopOpacity="0.0" />
                      </linearGradient>
                    </defs>
                    {/* Grid lines */}
                    <line x1="0" y1="25%" x2="100%" y2="25%" stroke="#1b1c1e" strokeDasharray="3 3" />
                    <line x1="0" y1="50%" x2="100%" y2="50%" stroke="#1b1c1e" strokeDasharray="3 3" />
                    <line x1="0" y1="75%" x2="100%" y2="75%" stroke="#1b1c1e" strokeDasharray="3 3" />

                    {/* Area fill */}
                    <polygon
                      fill="url(#waveGrad)"
                      points={`0,176 ${wavePoints
                        .map((p, idx) => `${(idx / (wavePoints.length - 1)) * 100}%,${176 - (p / 100) * 160}`)
                        .join(" ")} 100%,176`}
                    />
                    {/* Stroke line */}
                    <polyline
                      fill="none"
                      stroke="#56c2ff"
                      strokeWidth="2"
                      points={wavePoints
                        .map((p, idx) => `${(idx / (wavePoints.length - 1)) * 100}%,${176 - (p / 100) * 160}`)
                        .join(" ")}
                    />

                    {/* Hover indicator crosshair */}
                    {hoverPoint && (
                      <circle
                        cx={`${(hoverPoint.idx / (wavePoints.length - 1)) * 100}%`}
                        cy={`${176 - (hoverPoint.val / 100) * 160}`}
                        r="5"
                        fill="#ff6363"
                        stroke="#ffffff"
                        strokeWidth="2"
                      />
                    )}
                  </svg>

                  {/* Invisible scrub columns */}
                  <div className="absolute inset-0 flex">
                    {wavePoints.map((val, idx) => (
                      <div
                        key={idx}
                        className="flex-1 h-full hover:bg-white/5 transition-colors"
                        onMouseEnter={() => setHoverPoint({ idx, val })}
                      />
                    ))}
                  </div>
                </div>
              </div>

              {/* Memory & IO Breakdown */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="p-3.5 rounded-[8px] bg-[#111214] border border-[#363739]/60">
                  <span className="text-[11px] font-mono text-[#9c9c9d] uppercase">Physical RAM (Mach VM)</span>
                  <div className="text-[20px] font-medium text-white mt-1">11.4 GB / 16.0 GB</div>
                  <div className="mt-2 text-[11px] font-mono text-[#6a6b6c] flex justify-between">
                    <span>Active: 6.4 GB</span>
                    <span>Wired: 3.2 GB</span>
                    <span>Comp: 1.8 GB</span>
                  </div>
                </div>

                <div className="p-3.5 rounded-[8px] bg-[#111214] border border-[#363739]/60">
                  <span className="text-[11px] font-mono text-[#9c9c9d] uppercase">BSD Network (en0 WiFi)</span>
                  <div className="text-[20px] font-medium text-[#59d499] mt-1">&darr; 42.8 MB/s &middot; &uarr; 3.2 MB/s</div>
                  <div className="mt-2 text-[11px] font-mono text-[#6a6b6c]">
                    Zero-overhead getifaddrs kernel queries
                  </div>
                </div>

                <div className="p-3.5 rounded-[8px] bg-[#111214] border border-[#363739]/60">
                  <span className="text-[11px] font-mono text-[#9c9c9d] uppercase">IOKit Block Storage</span>
                  <div className="text-[20px] font-medium text-white mt-1">R: 18 MB/s &middot; W: 240 MB/s</div>
                  <div className="mt-2 text-[11px] font-mono text-[#6a6b6c]">
                    Apple SSD APFS hardware telemetry
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 3: DUAL-LAYER PROCESS KILL */}
          {activeTab === "process" && (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-[#363739]/60">
                <div>
                  <span className="text-[13px] font-medium text-white">
                    Zero-Lag Process Control &amp; Dual-Layer Kill
                  </span>
                  <p className="text-[11px] text-[#9c9c9d]">
                    First attempts NSRunningApplication.forceTerminate(), falling back immediately to POSIX kill(pid, SIGKILL) for terminal sub-processes.
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex items-center rounded-[6px] bg-[#111214] border border-[#363739]/60 p-0.5 text-[11px] font-mono">
                    <button
                      onClick={() => setProcessFilter("all")}
                      className={`px-2 py-0.5 rounded-[4px] ${processFilter === "all" ? "bg-[#1b1c1e] text-white" : "text-[#9c9c9d]"}`}
                    >
                      All
                    </button>
                    <button
                      onClick={() => setProcessFilter("heavy")}
                      className={`px-2 py-0.5 rounded-[4px] ${processFilter === "heavy" ? "bg-[#1b1c1e] text-white" : "text-[#9c9c9d]"}`}
                    >
                      &gt;20% CPU
                    </button>
                    <button
                      onClick={() => setProcessFilter("dev")}
                      className={`px-2 py-0.5 rounded-[4px] ${processFilter === "dev" ? "bg-[#1b1c1e] text-white" : "text-[#9c9c9d]"}`}
                    >
                      Dev Tools
                    </button>
                  </div>
                  <button
                    onClick={handleResetProcesses}
                    className="flex items-center gap-1.5 px-2.5 py-1 rounded-[6px] bg-[#1b1c1e] hover:bg-white/10 text-[11px] font-mono text-[#9c9c9d] border border-white/10 transition-colors"
                  >
                    <RotateCcw className="w-3 h-3" />
                    <span>Reset</span>
                  </button>
                </div>
              </div>

              {/* Interactive Process Table */}
              <div className="rounded-[8px] border border-[#363739]/80 overflow-hidden bg-[#040506]">
                <table className="w-full text-left text-[12px]">
                  <thead className="bg-[#111214] text-[#6a6b6c] font-mono text-[11px] border-b border-[#363739]/80">
                    <tr>
                      <th className="py-2.5 px-3">PID</th>
                      <th className="py-2.5 px-3">PROCESS NAME</th>
                      <th className="py-2.5 px-3">CPU</th>
                      <th className="py-2.5 px-3">MEMORY</th>
                      <th className="py-2.5 px-3">ENERGY</th>
                      <th className="py-2.5 px-3 text-right">ACTION</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#363739]/40 font-mono">
                    {filteredProcesses.map((proc) => (
                      <tr
                        key={proc.pid}
                        className={`transition-colors ${
                          proc.killed ? "opacity-25 line-through bg-black" : "hover:bg-[#111214]"
                        }`}
                      >
                        <td className="py-2.5 px-3 text-[#6a6b6c]">{proc.pid}</td>
                        <td className="py-2.5 px-3 text-white font-sans font-medium">
                          {proc.name}
                        </td>
                        <td className="py-2.5 px-3">
                          <span
                            className={
                              proc.cpu > 50
                                ? "text-[#ff6363]"
                                : proc.cpu > 10
                                ? "text-[#63a1ff]"
                                : "text-[#9c9c9d]"
                            }
                          >
                            {proc.cpu}%
                          </span>
                        </td>
                        <td className="py-2.5 px-3 text-[#9c9c9d]">{proc.mem}</td>
                        <td className="py-2.5 px-3">
                          <span
                            className={`inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-[4px] ${
                              proc.energy === "critical"
                                ? "bg-[#452324] text-[#ff6363]"
                                : proc.energy === "high"
                                ? "bg-[#1b1c1e] text-[#63a1ff]"
                                : "text-[#9c9c9d]"
                            }`}
                          >
                            🍃 {proc.energy}
                          </span>
                        </td>
                        <td className="py-2.5 px-3 text-right">
                          {proc.killed ? (
                            <span className="text-[10px] text-[#6a6b6c]">TERMINATED</span>
                          ) : (
                            <button
                              onClick={() => handleKill(proc.pid, proc.name)}
                              className="px-2.5 py-1 rounded-[4px] bg-[#1b1c1e] hover:bg-[#ff6363] text-[#9c9c9d] hover:text-white text-[11px] font-medium border border-white/10 hover:border-transparent transition-all"
                            >
                              ✕ KILL
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* TAB 4: DISK RADAR & CRUFT */}
          {activeTab === "storage" && (
            <div className="space-y-6">
              <div className="flex items-center justify-between pb-3 border-b border-[#363739]/60">
                <div>
                  <span className="text-[13px] font-medium text-white">
                    Disk Radar &amp; Developer Cruft Hunter
                  </span>
                  <p className="text-[11px] text-[#9c9c9d]">
                    Instantly finds reclaimable `.build` directories, Xcode DerivedData, and orphaned node_modules caches across all your Git repos.
                  </p>
                </div>
                <span className="px-2.5 py-1 rounded-[6px] bg-[#111214] border border-white/10 text-[12px] font-mono text-[#59d499]">
                  23.4 GB Reclaimable
                </span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow">
                  <div className="flex items-center justify-between">
                    <span className="text-[12px] font-medium text-white">Xcode DerivedData</span>
                    <span className="text-[11px] font-mono text-[#ff6363]">12.8 GB</span>
                  </div>
                  <p className="text-[11px] text-[#6a6b6c] mt-2 mb-3">
                    Stale module indexes from closed Xcode workspaces.
                  </p>
                  <button className="w-full py-1.5 rounded-[6px] bg-[#1b1c1e] hover:bg-white/10 text-[11px] font-mono text-[#e6e6e6] transition-colors border border-white/5">
                    Clean 12.8 GB
                  </button>
                </div>

                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow">
                  <div className="flex items-center justify-between">
                    <span className="text-[12px] font-medium text-white">Swift .build Dirs</span>
                    <span className="text-[11px] font-mono text-[#ff6363]">6.4 GB</span>
                  </div>
                  <p className="text-[11px] text-[#6a6b6c] mt-2 mb-3">
                    Incremental SPM build artifacts across 14 checked-out repos.
                  </p>
                  <button className="w-full py-1.5 rounded-[6px] bg-[#1b1c1e] hover:bg-white/10 text-[11px] font-mono text-[#e6e6e6] transition-colors border border-white/5">
                    Clean 6.4 GB
                  </button>
                </div>

                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow">
                  <div className="flex items-center justify-between">
                    <span className="text-[12px] font-medium text-white">Dangling npm/cargo</span>
                    <span className="text-[11px] font-mono text-[#ff6363]">4.2 GB</span>
                  </div>
                  <p className="text-[11px] text-[#6a6b6c] mt-2 mb-3">
                    Unlinked package cache tarballs older than 30 days.
                  </p>
                  <button className="w-full py-1.5 rounded-[6px] bg-[#1b1c1e] hover:bg-white/10 text-[11px] font-mono text-[#e6e6e6] transition-colors border border-white/5">
                    Clean 4.2 GB
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* TAB 5: WASTE & CHURN REPORT */}
          {activeTab === "waste" && (
            <div className="space-y-6">
              <div className="flex items-center justify-between pb-3 border-b border-[#363739]/60">
                <div>
                  <span className="text-[13px] font-medium text-white">
                    Agent Waste &amp; Code Churn Diagnostics
                  </span>
                  <p className="text-[11px] text-[#9c9c9d]">
                    Detects sessions that consumed credits without committing code, and hotspots where Claude rewrote files repeatedly.
                  </p>
                </div>
                <span className="px-2.5 py-1 rounded-[6px] bg-[#452324] border border-[#ff6363]/40 text-[12px] font-mono text-[#ff6363]">
                  $18.40 Reclaimable Waste
                </span>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {/* Churn Hotspot card */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[13px] font-medium text-white flex items-center gap-2">
                      <Flame className="w-4 h-4 text-[#ff6363]" />
                      Top Churn Hotspot
                    </span>
                    <span className="text-[11px] font-mono text-[#ff6363]">Rewritten 6x</span>
                  </div>
                  <code className="text-[12px] font-mono text-[#e6e6e6] block bg-black/40 p-2 rounded border border-white/5 mb-2">
                    Sources/Flightdeck/SessionInsights.swift
                  </code>
                  <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
                    Claude modified this file across 6 separate turns due to missing architecture guidelines. Adding an explicit <code className="text-white">CLAUDE.md</code> rule stopped repetitive rewrites.
                  </p>
                </div>

                {/* Waste breakdown card */}
                <div className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/80 key-shadow">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[13px] font-medium text-white flex items-center gap-2">
                      <Clock className="w-4 h-4 text-[#63a1ff]" />
                      Zero-Outcome Sessions
                    </span>
                    <span className="text-[11px] font-mono text-[#9c9c9d]">3 sessions flagged</span>
                  </div>
                  <div className="space-y-2 text-[12px] font-mono">
                    <div className="flex justify-between p-1.5 rounded bg-black/30 text-[#9c9c9d]">
                      <span>Session 90f2b3 (Context Ceiling)</span>
                      <span className="text-[#ff6363]">$8.20 wasted</span>
                    </div>
                    <div className="flex justify-between p-1.5 rounded bg-black/30 text-[#9c9c9d]">
                      <span>Session 12e4aa (Failed Tool Call)</span>
                      <span className="text-[#ff6363]">$6.10 wasted</span>
                    </div>
                    <div className="flex justify-between p-1.5 rounded bg-black/30 text-[#9c9c9d]">
                      <span>Session 77c1d8 (Aborted Search)</span>
                      <span className="text-[#ff6363]">$4.10 wasted</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>

      {/* ── Cybernetic Perspective Runway Flightdeck Floor Grid ── */}
      <div className="relative w-full h-32 -mt-8 pointer-events-none overflow-hidden flex justify-center [perspective:600px] select-none">
        <div
          className="w-[150%] h-[260px] origin-top transform-gpu animate-runway-flow opacity-60"
          style={{
            transform: "rotateX(74deg) translateY(-20px)",
            backgroundImage: `
              linear-gradient(to right, rgba(255, 99, 99, 0.15) 1px, transparent 1px),
              linear-gradient(to bottom, rgba(99, 161, 255, 0.15) 1px, transparent 1px)
            `,
            backgroundSize: "36px 36px",
            maskImage: "radial-gradient(ellipse at 50% 15%, black 20%, transparent 80%)",
          }}
        />
        {/* Horizon Laser Guideline */}
        <div className="absolute top-0 inset-x-12 h-[1px] bg-gradient-to-r from-transparent via-[#ff6363]/60 via-[#63a1ff]/60 to-transparent shadow-[0_0_16px_#ff6363]" />
        <div className="absolute top-2.5 flex items-center gap-2 text-[10px] font-mono tracking-[0.2em] text-[#6a6b6c] uppercase">
          <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
          <span>MACH_FLIGHTDECK // GROUND_ELEVATION_LOCK &middot; 1000Hz KERNEL DIRECT</span>
        </div>
      </div>
    </section>
  );
}
