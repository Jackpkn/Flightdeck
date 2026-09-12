"use client";

import React, { useState } from "react";
import { ShieldCheck, AlertOctagon, CheckCircle2, ChevronRight, Terminal, RefreshCw, Cpu, Database, GitCommit } from "lucide-react";

interface Scenario {
  id: string;
  name: string;
  category: string;
  naiveBehavior: {
    badge: string;
    result: string;
    explanation: string;
    calculation: string;
  };
  truthBehavior: {
    badge: string;
    result: string;
    explanation: string;
    calculation: string;
  };
}

const SCENARIOS: Scenario[] = [
  {
    id: "parallel_sessions",
    name: "Parallel Claude Sessions (Split Subagent)",
    category: "Cost & Token Forensics",
    naiveBehavior: {
      badge: "NAIVE TOOL ESTIMATION",
      result: "$145.92 Double Billed",
      explanation: "Polls cloud usage API without local session correlation. Multi-terminal subagents are counted twice due to overlapping timestamp windows.",
      calculation: "Session A ($72.96) + Session B ($72.96) = $145.92 (100% phantom overcount)",
    },
    truthBehavior: {
      badge: "FLIGHTDECK GROUND TRUTH",
      result: "$72.96 Exact Ledger",
      explanation: "Reads local transcript JSONL monotonically into SQLite with session UUID primary keys. Subagent forks are linked without duplicate billing.",
      calculation: "Monotonic SQLite hash: Session A parent (UUID: 4f8a) deduplicated with subagent child.",
    },
  },
  {
    id: "git_churn",
    name: "Code Survival vs Overwritten Turns",
    category: "Outcome Integrity",
    naiveBehavior: {
      badge: "NAIVE TOOL ESTIMATION",
      result: "+1,420 Lines Added (Reported)",
      explanation: "Sums every diff generated in turns 1 through 16. Assumes every written token represents permanent engineering value delivered.",
      calculation: "Turn 2 (+340) + Turn 5 (+480) + Turn 9 (+600) = 1,420 lines 'created'",
    },
    truthBehavior: {
      badge: "FLIGHTDECK GROUND TRUTH",
      result: "182 Lines in HEAD (12.8% Survival)",
      explanation: "Executes real git blob verification against current working tree. 1,238 lines were rewritten or discarded in later turns.",
      calculation: "Surviving: 182 lines ($9.34). Churned/Discarded: 1,238 lines ($63.62 wasted spend).",
    },
  },
  {
    id: "cpu_measurement",
    name: "M-Series P-Core vs E-Core Load",
    category: "Darwin Kernel Vitals",
    naiveBehavior: {
      badge: "NAIVE TOOL ESTIMATION",
      result: "42% CPU (Flat Average)",
      explanation: "Executes standard POSIX ps or top. Divides total tick count across all cores without distinguishing cluster affinity.",
      calculation: "Average ticks / 16 cores = 42% (Hides thermal throttling on Performance cores)",
    },
    truthBehavior: {
      badge: "FLIGHTDECK GROUND TRUTH",
      result: "98% P-Cores / 4% E-Cores (Spike Alert)",
      explanation: "Direct mach_host_processor_info kernel sysctl. Reveals your Vite compiler pinning all 8 Performance cores while Efficiency cores idle.",
      calculation: "Cluster 0 (P-Cores): 98.4% load (3.8 GHz). Cluster 1 (E-Cores): 4.1% load (idle).",
    },
  },
  {
    id: "disk_cruft",
    name: "Build Cache Purge Safety",
    category: "Storage Radar",
    naiveBehavior: {
      badge: "NAIVE TOOL ESTIMATION",
      result: "Blind 'Clean All' (High Risk)",
      explanation: "Executes recursive rm -rf on ~/.cache without verifying whether lockfiles, active daemons, or unpushed artifacts depend on them.",
      calculation: "Deletes active bundler cache -> Causes 20-minute rebuilds and broken CocoaPods.",
    },
    truthBehavior: {
      badge: "FLIGHTDECK GROUND TRUTH",
      result: "Safe Purge with Re-gen Confidence",
      explanation: "Categorizes caches with rebuild confidence tags. Preserves git indexes, only cleans ephemeral DerivedData, brew cache, and Xcode logs.",
      calculation: "Target: DerivedData (42.1 GB, 100% safe). Preserved: local git blobstores and credentials.",
    },
  },
];

export default function TruthEngineDiff() {
  const [activeScenario, setActiveScenario] = useState<Scenario>(SCENARIOS[0]);

  return (
    <div className="my-16 rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_16px_50px_rgba(0,0,0,0.8)] overflow-hidden">
      {/* Top Header */}
      <div className="px-6 py-4 border-b border-[#363739]/60 flex flex-wrap items-center justify-between gap-4 bg-[#0a0b0d]">
        <div className="flex items-center gap-3">
          <ShieldCheck className="w-4 h-4 text-[#59d499]" />
          <span className="text-[13px] font-mono font-medium text-white tracking-wide">
            TRUTH_ENGINE // NAIVE TOOLS VS FLIGHTDECK DETERMINISM
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className="inline-block w-2 h-2 rounded-full bg-[#59d499] animate-pulse" />
          <span className="text-[11px] font-mono text-[#59d499]">
            ZERO INVENTIONS PROTOCOL
          </span>
        </div>
      </div>

      <div className="p-6 sm:p-8">
        {/* Scenario Switcher Tabs */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mb-8">
          {SCENARIOS.map((scenario) => {
            const isSelected = activeScenario.id === scenario.id;
            return (
              <button
                key={scenario.id}
                onClick={() => setActiveScenario(scenario)}
                className={`p-3.5 rounded-[10px] text-left transition-all border text-[12px] font-mono ${
                  isSelected
                    ? "bg-[#16171a] border-[#59d499] text-white shadow-[0_0_15px_rgba(89,212,153,0.15)]"
                    : "bg-[#0d0e11] border-[#363739]/60 text-[#9c9c9d] hover:border-[#6a6b6c] hover:text-white"
                }`}
              >
                <div className="text-[10px] uppercase text-[#6a6b6c] mb-1">
                  {scenario.category}
                </div>
                <div className="font-medium truncate">{scenario.name}</div>
              </button>
            );
          })}
        </div>

        {/* Live Comparison Split Deck */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Naive Side */}
          <div className="rounded-[12px] bg-[#0c0505]/70 border border-[#ff6363]/30 p-6 flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between gap-2 pb-4 mb-4 border-b border-[#ff6363]/20">
                <div className="flex items-center gap-2 text-[#ff6363] text-[12px] font-mono">
                  <AlertOctagon className="w-4 h-4" />
                  <span>{activeScenario.naiveBehavior.badge}</span>
                </div>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-[#ff6363]/10 text-[#ff6363] border border-[#ff6363]/30">
                  EXTRAPOLATION
                </span>
              </div>

              <div className="text-[24px] font-mono font-medium text-[#ff8080] mb-3">
                {activeScenario.naiveBehavior.result}
              </div>

              <p className="text-[13px] text-[#b3a4a4] leading-relaxed mb-6">
                {activeScenario.naiveBehavior.explanation}
              </p>
            </div>

            <div className="p-3.5 rounded-[8px] bg-[#1a0c0c] border border-[#ff6363]/20 font-mono text-[11px] text-[#ff9e9e]">
              <div className="text-[9px] uppercase tracking-wider text-[#995c5c] mb-1">
                Flawed Computation:
              </div>
              <div className="break-all">{activeScenario.naiveBehavior.calculation}</div>
            </div>
          </div>

          {/* Flightdeck Truth Side */}
          <div className="rounded-[12px] bg-[#050c08]/70 border border-[#59d499]/30 p-6 flex flex-col justify-between shadow-[0_0_30px_rgba(89,212,153,0.06)]">
            <div>
              <div className="flex items-center justify-between gap-2 pb-4 mb-4 border-b border-[#59d499]/20">
                <div className="flex items-center gap-2 text-[#59d499] text-[12px] font-mono">
                  <CheckCircle2 className="w-4 h-4" />
                  <span>{activeScenario.truthBehavior.badge}</span>
                </div>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-[#59d499]/10 text-[#59d499] border border-[#59d499]/30">
                  KERNEL &amp; GIT AUDITED
                </span>
              </div>

              <div className="text-[24px] font-mono font-medium text-[#59d499] mb-3">
                {activeScenario.truthBehavior.result}
              </div>

              <p className="text-[13px] text-[#9db8a8] leading-relaxed mb-6">
                {activeScenario.truthBehavior.explanation}
              </p>
            </div>

            <div className="p-3.5 rounded-[8px] bg-[#091710] border border-[#59d499]/20 font-mono text-[11px] text-[#59d499]">
              <div className="text-[9px] uppercase tracking-wider text-[#3d805f] mb-1">
                Deterministic Audit:
              </div>
              <div className="break-all">{activeScenario.truthBehavior.calculation}</div>
            </div>
          </div>
        </div>

        {/* Footer Note */}
        <div className="mt-8 pt-6 border-t border-[#363739]/60 flex flex-col sm:flex-row items-center justify-between gap-4 text-[12px] text-[#6a6b6c]">
          <div className="flex items-center gap-2">
            <Database className="w-3.5 h-3.5 text-[#59d499]" />
            <span>Telemetry stored locally in <code className="text-white font-mono">~/.flightdeck/flightdeck.db</code> &middot; No cloud syncing</span>
          </div>
          <div className="font-mono text-[#59d499] text-[11px]">
            ZERO TELEMETRY PHONE-HOME
          </div>
        </div>
      </div>
    </div>
  );
}
