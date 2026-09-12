"use client";

import React from "react";
import { Lock, Cpu, Database, EyeOff, Terminal, Sparkles } from "lucide-react";

export default function ArchitectureSection() {
  const specs = [
    {
      icon: EyeOff,
      title: "Zero Cloud & Zero Analytics",
      description:
        "Every byte of telemetry, token calculation, and session history stays strictly on your local NVMe storage. No network calls, no tracking pings, no accounts.",
    },
    {
      icon: Cpu,
      title: "Native Mach & BSD C Engine",
      description:
        "Direct hardware interrogation using POSIX C APIs. It accesses real CPU tick registers rather than invoking slow shell sub-processes like top or ps.",
    },
    {
      icon: Database,
      title: "Local SQLite Ledger",
      description:
        "Sessions, churn metrics, and historical hardware telemetry are written to an ultra-fast local SQLite database that never touches any remote servers.",
    },
    {
      icon: Lock,
      title: "Zero-Permission Focus Tracking",
      description:
        "Uses native NSWorkspace app activation notifications and CGEventSource idle detection — no screen recording or accessibility permissions required.",
    },
  ];

  return (
    <section className="max-w-[1200px] mx-auto px-4 sm:px-6 py-16 md:py-24 border-t border-[#363739]/40">
      <div className="text-center mb-14">
        <p className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-2">
          Engineered for Power Users
        </p>
        <h2 className="text-[32px] sm:text-[40px] font-normal text-[#ffffff] tracking-tight">
          Built purely in Swift &amp; C. Nothing Leaves Your Mac.
        </h2>
        <p className="text-[16px] text-[#9c9c9d] max-w-[580px] mx-auto mt-2">
          Flightdeck is an uncompromising desktop application designed to run silently in the background with near-zero resource consumption.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {specs.map((item, idx) => {
          const Icon = item.icon;
          return (
            <div
              key={idx}
              className="p-6 rounded-[16px] bg-[#07080a] border border-[#363739]/80 key-shadow flex flex-col justify-between"
            >
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#e6e6e6] mb-4">
                  <Icon className="w-5 h-5 text-[#ff6363]" />
                </div>
                <h3 className="text-[16px] font-medium text-white mb-2">
                  {item.title}
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed">
                  {item.description}
                </p>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
