"use client";

import React, { useState } from "react";
import { Check, X, Shield, Zap, Sparkles, Cpu, HardDrive } from "lucide-react";
import { playClickSound } from "@/utils/audio";

interface ComparisonRow {
  feature: string;
  category: "ai" | "telemetry" | "system";
  flightdeck: string;
  flightdeckHighlight: boolean;
  activityMonitor: string;
  statsApp: string;
  cloudDashboards: string;
}

const COMPARISON_DATA: ComparisonRow[] = [
  {
    feature: "Claude Code Spend to Git Survival Correlation",
    category: "ai",
    flightdeck: "Monotonic SQLite correlation against git HEAD",
    flightdeckHighlight: true,
    activityMonitor: "None",
    statsApp: "None",
    cloudDashboards: "None (Raw invoices only)",
  },
  {
    feature: "Sampling Frequency & Timer Mechanism",
    category: "telemetry",
    flightdeck: "1,000 Hz microsecond Mach kernel C timer",
    flightdeckHighlight: true,
    activityMonitor: "1.0 - 5.0 Hz coarse polling",
    statsApp: "1.0 Hz polling",
    cloudDashboards: "Lagged batch queries (15-60 min delay)",
  },
  {
    feature: "Memory Footprint & Runtime Overhead",
    category: "system",
    flightdeck: "~18 MB native Swift 6 binary (< 0.2% CPU)",
    flightdeckHighlight: true,
    activityMonitor: "~65 MB Cocoa / WebKit helper",
    statsApp: "~85 MB menubar daemon",
    cloudDashboards: "150+ MB per active browser tab",
  },
  {
    feature: "Data Privacy & Network Policy",
    category: "system",
    flightdeck: "100% On-Device / 0 Outbound Network Requests",
    flightdeckHighlight: true,
    activityMonitor: "Local only",
    statsApp: "Local with opt-in update check",
    cloudDashboards: "Full session & transcript upload required",
  },
  {
    feature: "APFS Storage Fast-Clone Sector Awareness",
    category: "telemetry",
    flightdeck: "Real block-level disk radar with safety index",
    flightdeckHighlight: true,
    activityMonitor: "Basic volume summary",
    statsApp: "Basic disk percentage bar",
    cloudDashboards: "None",
  },
  {
    feature: "Dead Code Churn & Financial Waste Estimation",
    category: "ai",
    flightdeck: "Automatic diff attribution on every session close",
    flightdeckHighlight: true,
    activityMonitor: "None",
    statsApp: "None",
    cloudDashboards: "None",
  },
  {
    feature: "Kernel Subsystem Target",
    category: "system",
    flightdeck: "Mach VM, proc_pidinfo, sysctl hw.perflevel",
    flightdeckHighlight: true,
    activityMonitor: "Standard proc APIs",
    statsApp: "IOKit SMC sensors",
    cloudDashboards: "None (HTTP API)",
  },
];

export default function ComparisonMatrix() {
  const [filter, setFilter] = useState<"all" | "ai" | "telemetry" | "system">("all");

  const filteredRows = filter === "all" ? COMPARISON_DATA : COMPARISON_DATA.filter((r) => r.category === filter);

  return (
    <div className="w-full max-w-[1240px] mx-auto px-4 sm:px-6 py-16 sm:py-24">
      {/* Section Header */}
      <div className="text-center max-w-[800px] mx-auto mb-12">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#ff6363]/10 border border-[#ff6363]/30 text-[11px] font-mono text-[#ff6363] uppercase mb-4">
          <Zap className="w-3.5 h-3.5" />
          <span>ARCHITECTURAL BENCHMARK</span>
        </div>
        <h2 className="text-[32px] sm:text-[44px] font-normal text-white tracking-tight leading-[1.15] mb-4">
          Why Flightdeck replaces coarse monitors.
        </h2>
        <p className="text-[15px] sm:text-[17px] text-[#9c9c9d] leading-relaxed">
          Activity Monitor was built in 2001 for desktop multitasking. Cloud dashboards were built for billing teams. Flightdeck is built for engineers using agentic coding on Apple Silicon.
        </p>

        {/* Filter Pills */}
        <div className="flex items-center justify-center gap-2 mt-8">
          {[
            { id: "all", label: "All Benchmarks" },
            { id: "ai", label: "Claude Attribution" },
            { id: "telemetry", label: "Mach Precision" },
            { id: "system", label: "System Overhead" },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => {
                playClickSound();
                setFilter(tab.id as typeof filter);
              }}
              className={`px-3.5 py-1.5 rounded-[8px] text-[12px] font-mono transition-all duration-150 ${
                filter === tab.id
                  ? "bg-white text-black font-semibold shadow-[0_0_12px_rgba(255,255,255,0.2)]"
                  : "bg-[#111214] text-[#9c9c9d] hover:text-white border border-[#26272b]"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Responsive Comparison Table Container */}
      <div className="w-full overflow-x-auto rounded-[14px] border border-[#232428] bg-[#07080a] shadow-[0_12px_48px_rgba(0,0,0,0.8)]">
        <table className="w-full min-w-[760px] text-left border-collapse">
          <thead>
            <tr className="border-b border-[#232428] bg-[#0b0c0f]">
              <th className="py-4 px-5 text-[12px] font-mono text-[#6a6b6c] uppercase w-[30%]">CAPABILITY</th>
              <th className="py-4 px-5 text-[12px] font-mono text-[#ff6363] uppercase w-[28%] bg-[#ff6363]/5 border-x border-[#ff6363]/20">
                <div className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-[#ff6363] animate-pulse" />
                  <span>FLIGHTDECK (NATIVE)</span>
                </div>
              </th>
              <th className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d] uppercase w-[14%]">ACTIVITY MONITOR</th>
              <th className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d] uppercase w-[14%]">STATS / ISTAT</th>
              <th className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d] uppercase w-[14%]">CLOUD CONSOLES</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#18191d]">
            {filteredRows.map((row, idx) => (
              <tr key={idx} className="hover:bg-white/[0.02] transition-colors">
                {/* Feature Name */}
                <td className="py-4 px-5 text-[13px] font-medium text-white font-sans">
                  {row.feature}
                </td>

                {/* Flightdeck Column (Highlighted) */}
                <td className="py-4 px-5 text-[13px] font-mono text-[#ffffff] bg-[#ff6363]/5 border-x border-[#ff6363]/20 font-medium">
                  <div className="flex items-start gap-2">
                    <Check className="w-4 h-4 text-[#ff6363] shrink-0 mt-0.5" />
                    <span>{row.flightdeck}</span>
                  </div>
                </td>

                {/* Activity Monitor */}
                <td className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d]">
                  {row.activityMonitor === "None" ? (
                    <span className="text-[#454647] flex items-center gap-1">
                      <X className="w-3.5 h-3.5" /> None
                    </span>
                  ) : (
                    row.activityMonitor
                  )}
                </td>

                {/* Stats App */}
                <td className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d]">
                  {row.statsApp === "None" ? (
                    <span className="text-[#454647] flex items-center gap-1">
                      <X className="w-3.5 h-3.5" /> None
                    </span>
                  ) : (
                    row.statsApp
                  )}
                </td>

                {/* Cloud Dashboards */}
                <td className="py-4 px-5 text-[12px] font-mono text-[#9c9c9d]">
                  {row.cloudDashboards.startsWith("None") ? (
                    <span className="text-[#454647] flex items-center gap-1">
                      <X className="w-3.5 h-3.5" /> None
                    </span>
                  ) : (
                    row.cloudDashboards
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
