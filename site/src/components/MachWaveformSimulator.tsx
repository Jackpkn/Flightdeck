"use client";

import React, { useState, useEffect, useRef } from "react";
import {
  Activity,
  Cpu,
  Zap,
  Terminal,
  Trash2,
  RotateCcw,
  CheckCircle2,
  AlertCircle,
  Play,
  Pause,
} from "lucide-react";

interface SimulatedProcess {
  pid: number;
  name: string;
  pCoreUsage: number;
  eCoreUsage: number;
  memMB: number;
  state: "running" | "killed";
  category: "lsp" | "compiler" | "daemon";
}

const INITIAL_PROCESSES: SimulatedProcess[] = [
  { pid: 98124, name: "swift-frontend (indexing)", pCoreUsage: 88.4, eCoreUsage: 12.1, memMB: 2840, state: "running", category: "compiler" },
  { pid: 98402, name: "node (tsserver orphaned)", pCoreUsage: 94.2, eCoreUsage: 4.8, memMB: 1980, state: "running", category: "lsp" },
  { pid: 97890, name: "clangd (heavy AST scan)", pCoreUsage: 64.0, eCoreUsage: 22.4, memMB: 1420, state: "running", category: "lsp" },
  { pid: 96541, name: "rust-analyzer (proc-macro)", pCoreUsage: 52.8, eCoreUsage: 18.0, memMB: 1150, state: "running", category: "lsp" },
  { pid: 95400, name: "backupd-helper (APFS snapshot)", pCoreUsage: 4.2, eCoreUsage: 78.4, memMB: 480, state: "running", category: "daemon" },
];

export default function MachWaveformSimulator() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const [processes, setProcesses] = useState<SimulatedProcess[]>(INITIAL_PROCESSES);
  const [reclaimedMem, setReclaimedMem] = useState(0);
  const [ticksCount, setTicksCount] = useState(482109);
  const [activeTab, setActiveTab] = useState<"pcore" | "ecore" | "dual">("dual");

  // Real-time Waveform Canvas Loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animId: number;
    let t = 0;

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.scale(dpr, dpr);
    };

    resize();
    window.addEventListener("resize", resize);

    const historyP: number[] = new Array(180).fill(45);
    const historyE: number[] = new Array(180).fill(25);

    const render = () => {
      if (!canvas) return;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      ctx.clearRect(0, 0, w, h);

      if (isPlaying) {
        t += 0.04;
        setTicksCount((prev) => prev + 12);

        // Compute aggregate load from live processes
        const activeProcs = processes.filter((p) => p.state === "running");
        const baseP = activeProcs.reduce((acc, p) => acc + p.pCoreUsage, 0) / (activeProcs.length || 1);
        const baseE = activeProcs.reduce((acc, p) => acc + p.eCoreUsage, 0) / (activeProcs.length || 1);

        const newP = Math.min(98, Math.max(8, baseP + Math.sin(t * 3.5) * 14 + Math.cos(t * 7.1) * 8 + (Math.random() - 0.5) * 6));
        const newE = Math.min(92, Math.max(5, baseE + Math.cos(t * 2.2) * 12 + Math.sin(t * 4.8) * 5 + (Math.random() - 0.5) * 4));

        historyP.push(newP);
        historyP.shift();

        historyE.push(newE);
        historyE.shift();
      }

      // ── Grid & Reticle Lines ──
      ctx.strokeStyle = "rgba(255, 255, 255, 0.04)";
      ctx.lineWidth = 1;
      const gridYCount = 4;
      for (let i = 1; i < gridYCount; i++) {
        const y = (h / gridYCount) * i;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
      }

      for (let x = 0; x < w; x += 60) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
        ctx.stroke();
      }

      // ── Waveform Helper ──
      const drawLine = (data: number[], color: string, glowColor: string, fillGrad: CanvasGradient) => {
        ctx.save();
        ctx.beginPath();
        const step = w / (data.length - 1);

        ctx.moveTo(0, h - (data[0] / 100) * (h - 20) - 10);
        for (let i = 1; i < data.length; i++) {
          const x = i * step;
          const y = h - (data[i] / 100) * (h - 20) - 10;
          ctx.lineTo(x, y);
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.shadowColor = glowColor;
        ctx.shadowBlur = 10;
        ctx.stroke();

        // Fill area under line
        ctx.lineTo(w, h);
        ctx.lineTo(0, h);
        ctx.closePath();
        ctx.fillStyle = fillGrad;
        ctx.fill();
        ctx.restore();
      };

      // ── Draw E-Core Waveform (Cyan) ──
      if (activeTab === "ecore" || activeTab === "dual") {
        const gradE = ctx.createLinearGradient(0, 0, 0, h);
        gradE.addColorStop(0, "rgba(56, 189, 248, 0.18)");
        gradE.addColorStop(1, "rgba(56, 189, 248, 0.0)");
        drawLine(historyE, "#38bdf8", "rgba(56, 189, 248, 0.6)", gradE);
      }

      // ── Draw P-Core Waveform (Coral) ──
      if (activeTab === "pcore" || activeTab === "dual") {
        const gradP = ctx.createLinearGradient(0, 0, 0, h);
        gradP.addColorStop(0, "rgba(255, 99, 99, 0.22)");
        gradP.addColorStop(1, "rgba(255, 99, 99, 0.0)");
        drawLine(historyP, "#ff6363", "rgba(255, 99, 99, 0.7)", gradP);
      }

      // ── Live Leading Laser Needle ──
      ctx.strokeStyle = "rgba(255, 255, 255, 0.35)";
      ctx.setLineDash([2, 4]);
      ctx.beginPath();
      ctx.moveTo(w - 1, 0);
      ctx.lineTo(w - 1, h);
      ctx.stroke();
      ctx.setLineDash([]);

      animId = requestAnimationFrame(render);
    };

    animId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("resize", resize);
    };
  }, [isPlaying, processes, activeTab]);

  const killProcess = (pid: number) => {
    setProcesses((prev) =>
      prev.map((proc) => {
        if (proc.pid === pid) {
          setReclaimedMem((m) => m + proc.memMB);
          return { ...proc, state: "killed", pCoreUsage: 0, eCoreUsage: 0 };
        }
        return proc;
      })
    );
  };

  const resetProcesses = () => {
    setProcesses(INITIAL_PROCESSES);
    setReclaimedMem(0);
  };

  return (
    <div className="rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_12px_40px_rgba(0,0,0,0.8)] overflow-hidden">
      {/* Waveform Header Bar */}
      <div className="px-6 py-4 border-b border-[#363739]/60 flex flex-wrap items-center justify-between gap-4 bg-[#0a0b0d]">
        <div className="flex items-center gap-3">
          <div className="w-2.5 h-2.5 rounded-full bg-[#59d499] animate-pulse" />
          <span className="text-[13px] font-mono font-medium text-white tracking-wide">
            MACH_HOST_CPU_LOAD_INFO // 1000Hz KERNEL DIRECT
          </span>
          <span className="text-[#363739]">|</span>
          <span className="text-[11px] font-mono text-[#6a6b6c]">
            TICKS: {ticksCount.toLocaleString()}
          </span>
        </div>

        <div className="flex items-center gap-3">
          {/* Core Channel Selector */}
          <div className="flex items-center p-0.5 rounded-[6px] bg-[#111214] border border-[#363739]/80 text-[11px] font-mono">
            <button
              onClick={() => setActiveTab("dual")}
              className={`px-2.5 py-1 rounded-[4px] transition-colors ${
                activeTab === "dual" ? "bg-[#1b1c1e] text-white font-medium" : "text-[#6a6b6c] hover:text-white"
              }`}
            >
              Dual Channels
            </button>
            <button
              onClick={() => setActiveTab("pcore")}
              className={`px-2.5 py-1 rounded-[4px] transition-colors ${
                activeTab === "pcore" ? "bg-[#1b1c1e] text-[#ff6363] font-medium" : "text-[#6a6b6c] hover:text-white"
              }`}
            >
              P-Cores (Coral)
            </button>
            <button
              onClick={() => setActiveTab("ecore")}
              className={`px-2.5 py-1 rounded-[4px] transition-colors ${
                activeTab === "ecore" ? "bg-[#1b1c1e] text-[#38bdf8] font-medium" : "text-[#6a6b6c] hover:text-white"
              }`}
            >
              E-Cores (Cyan)
            </button>
          </div>

          <button
            onClick={() => setIsPlaying(!isPlaying)}
            className="p-1.5 rounded-[6px] bg-[#111214] hover:bg-[#1b1c1e] border border-[#363739]/60 text-[#9c9c9d] hover:text-white transition-colors"
            title={isPlaying ? "Pause Stream" : "Resume Stream"}
          >
            {isPlaying ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5 text-[#59d499]" />}
          </button>
        </div>
      </div>

      {/* Real-time Oscilloscope Canvas View */}
      <div className="relative h-[240px] w-full bg-[#050608] overflow-hidden">
        <canvas ref={canvasRef} className="w-full h-full" />

        {/* Legend Overlay */}
        <div className="absolute top-3 left-4 flex items-center gap-4 text-[11px] font-mono pointer-events-none">
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-[#ff6363] shadow-[0_0_8px_#ff6363]" />
            <span className="text-[#e6e6e6]">Performance Ticks (P-Cores)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-[#38bdf8] shadow-[0_0_8px_#38bdf8]" />
            <span className="text-[#9c9c9d]">Efficiency Ticks (E-Cores)</span>
          </div>
        </div>

        <div className="absolute bottom-3 right-4 text-[10px] font-mono text-[#454647] pointer-events-none">
          0ms IPC Overhead · Direct Kernel Wire
        </div>
      </div>

      {/* Interactive Process Sandbox Sub-section */}
      <div className="p-6 border-t border-[#363739]/60 bg-[#07080a]">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
          <div>
            <h4 className="text-[14px] font-medium text-white flex items-center gap-2">
              <span>Interactive POSIX Process Control Sandbox</span>
              <span className="text-[11px] font-mono text-[#59d499] px-2 py-0.5 rounded bg-[#59d499]/10 border border-[#59d499]/20">
                0ms UI LAG
              </span>
            </h4>
            <p className="text-[12px] text-[#6a6b6c] mt-0.5">
              Simulate terminating runaway memory hogs. Watch the waveform drop and physical memory restore instantly.
            </p>
          </div>

          <div className="flex items-center gap-3">
            {reclaimedMem > 0 && (
              <span className="text-[12px] font-mono text-[#59d499] flex items-center gap-1 bg-[#59d499]/10 px-2.5 py-1 rounded-[6px] border border-[#59d499]/20">
                <CheckCircle2 className="w-3.5 h-3.5" />
                {(reclaimedMem / 1024).toFixed(2)} GB Reclaimed
              </span>
            )}
            <button
              onClick={resetProcesses}
              className="inline-flex items-center gap-1.5 text-[11px] font-mono text-[#9c9c9d] hover:text-white px-2.5 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 hover:border-[#363739] transition-colors"
            >
              <RotateCcw className="w-3 h-3" />
              <span>Reset Processes</span>
            </button>
          </div>
        </div>

        {/* Process Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-[12px] font-mono">
            <thead>
              <tr className="text-[#6a6b6c] border-b border-[#1b1c1e] text-[11px]">
                <th className="pb-2.5 font-normal">PID</th>
                <th className="pb-2.5 font-normal">PROCESS</th>
                <th className="pb-2.5 font-normal">P-CORE</th>
                <th className="pb-2.5 font-normal">E-CORE</th>
                <th className="pb-2.5 font-normal">MACH VM RESIDENT</th>
                <th className="pb-2.5 font-normal text-right">ACTION</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#161719]">
              {processes.map((proc) => {
                const isKilled = proc.state === "killed";
                return (
                  <tr key={proc.pid} className={`transition-opacity duration-200 ${isKilled ? "opacity-35" : ""}`}>
                    <td className="py-2.5 text-[#6a6b6c]">{proc.pid}</td>
                    <td className="py-2.5 font-medium text-white flex items-center gap-2">
                      <span>{proc.name}</span>
                      {proc.category === "compiler" && (
                        <span className="text-[10px] px-1.5 py-0.2 rounded bg-[#ff6363]/10 text-[#ff6363] border border-[#ff6363]/20">
                          COMPILER
                        </span>
                      )}
                    </td>
                    <td className="py-2.5 text-[#ff6363]">
                      {isKilled ? "0.0%" : `${proc.pCoreUsage.toFixed(1)}%`}
                    </td>
                    <td className="py-2.5 text-[#38bdf8]">
                      {isKilled ? "0.0%" : `${proc.eCoreUsage.toFixed(1)}%`}
                    </td>
                    <td className="py-2.5 text-[#e6e6e6]">
                      {isKilled ? "0 MB" : `${proc.memMB} MB`}
                    </td>
                    <td className="py-2.5 text-right">
                      {isKilled ? (
                        <span className="text-[11px] text-[#59d499] flex items-center justify-end gap-1">
                          <CheckCircle2 className="w-3 h-3" />
                          KILLED
                        </span>
                      ) : (
                        <button
                          onClick={() => killProcess(proc.pid)}
                          className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-[5px] bg-[#ff6363]/10 hover:bg-[#ff6363]/20 text-[#ff6363] border border-[#ff6363]/30 transition-colors text-[11px]"
                        >
                          <Trash2 className="w-3 h-3" />
                          <span>1-Click Kill</span>
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
