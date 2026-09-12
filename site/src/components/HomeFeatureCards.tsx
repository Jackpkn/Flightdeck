"use client";

import React from "react";
import Link from "next/link";
import { Brain, Activity, HardDrive, ShieldCheck, ArrowRight } from "lucide-react";
import GlowBorderCard from "./GlowBorderCard";

export default function HomeFeatureCards() {
  const sections = [
    {
      href: "/forensics",
      badge: "Deck 02 · AI Forensics",
      title: "Claude Code Spend & Outcome",
      desc: "Correlates session transcripts with your working tree. Measures real code survival in HEAD and flags runaway churn hotspots.",
      icon: Brain,
      glow: "coral" as const,
      stat: "96.4% survival",
    },
    {
      href: "/system",
      badge: "Deck 03 · Hardware Vitals",
      title: "Mach Kernel Waveforms",
      desc: "Raw HOST_CPU_LOAD_INFO across P/E cores, Mach VM physical memory, and 1-click POSIX process termination with 0ms UI lag.",
      icon: Activity,
      glow: "blue" as const,
      stat: "1000Hz ticks",
    },
    {
      href: "/storage",
      badge: "Deck 04 · Storage Radar",
      title: "Developer Cruft Hunter",
      desc: "Instantly reclaims hidden Xcode DerivedData, SPM .build directories, and orphaned node_modules caches across all your repos.",
      icon: HardDrive,
      glow: "green" as const,
      stat: "23.4 GB reclaimable",
    },
    {
      href: "/manifesto",
      badge: "Architecture · Honesty",
      title: "Measurement Integrity",
      desc: "Eliminates plausible guesses. Marks baseline window approximations with ≤, unpriced models with ≥, and keeps all data on NVMe.",
      icon: ShieldCheck,
      glow: "coral" as const,
      stat: "100% on-device",
    },
  ];

  return (
    <section className="max-w-[1240px] mx-auto px-4 sm:px-6 py-16 md:py-24 border-t border-[#363739]/40">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-12">
        <div>
          <p className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-2">
            Cockpit Deep Dives &middot; 4 Dedicated Instruments
          </p>
          <h2 className="text-[32px] sm:text-[40px] font-normal text-white tracking-tight">
            Explore Each Instrument
          </h2>
        </div>
        <p className="text-[14px] text-[#9c9c9d] max-w-[440px]">
          Dedicated telemetry suites engineered for precision, zero fluff, and mathematical accountability.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {sections.map((item, idx) => {
          const Icon = item.icon;
          return (
            <Link key={idx} href={item.href} className="block h-full group">
              <GlowBorderCard glowColor={item.glow} className="h-full hover:border-[#363739]">
                <div>
                  <div className="flex items-center justify-between mb-4">
                    <div className="w-9 h-9 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#e6e6e6]">
                      <Icon className="w-4 h-4 text-[#ff6363]" />
                    </div>
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-[#111214] text-[#59d499] border border-white/5">
                      {item.stat}
                    </span>
                  </div>

                  <span className="text-[11px] font-mono tracking-wider text-[#6a6b6c] uppercase block mb-1">
                    {item.badge}
                  </span>
                  <h3 className="text-[16px] font-medium text-white mb-2 group-hover:text-[#ff6363] transition-colors flex items-center gap-1.5">
                    <span>{item.title}</span>
                    <ArrowRight className="w-3.5 h-3.5 opacity-0 group-hover:opacity-100 group-hover:translate-x-1 transition-all" />
                  </h3>
                  <p className="text-[13px] text-[#9c9c9d] leading-relaxed">
                    {item.desc}
                  </p>
                </div>

                <div className="pt-4 mt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#6a6b6c] group-hover:text-white transition-colors flex items-center justify-between">
                  <span>Open Deep Dive</span>
                  <span>&rarr;</span>
                </div>
              </GlowBorderCard>
            </Link>
          );
        })}
      </div>
    </section>
  );
}
