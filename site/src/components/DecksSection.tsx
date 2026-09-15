"use client";

import React, { useState } from "react";
import {
  LayoutDashboard,
  Brain,
  Activity,
  HardDrive,
  Coins,
  Check,
  ChevronRight,
} from "lucide-react";

interface Deck {
  key: string;
  name: string;
  badge: string;
  icon: React.ElementType;
  headline: string;
  description: string;
  features: { title: string; detail: string }[];
}

const DECKS: Deck[] = [
  {
    key: "1",
    name: "Deck 01 · Cockpit",
    badge: "⌘1",
    icon: LayoutDashboard,
    headline: "Everything at a single glance.",
    description:
      "All your vital telemetry and today's AI spend in one ultra-responsive desktop HUD. Instant keyboard navigation with ⌘K command palette.",
    features: [
      {
        title: "Live Machine Vitals",
        detail: "Real-time P/E core CPU ticks, memory pressure, and BSD socket throughput.",
      },
      {
        title: "Early Warning Radar",
        detail: "Proactive alert triggers before plan limits, rate caps, or context ceilings bite.",
      },
      {
        title: "Global ⌘K Command Palette",
        detail: "Zero-latency fuzzy search across active sessions, open ports, and system processes.",
      },
    ],
  },
  {
    key: "2",
    name: "Deck 02 · Claude Code",
    badge: "⌘2",
    icon: Brain,
    headline: "Was the Claude Code spend worth it?",
    description:
      "Unlike cloud billing portals that stop at the invoice, Flightdeck correlates token usage with your working tree to measure real delivered value.",
    features: [
      {
        title: "Code Survival in HEAD",
        detail: "Calculates what percentage of code Claude wrote actually survived in your git repo.",
      },
      {
        title: "Cost Per Outcome",
        detail: "True amortized cost per surviving file and per landed commit.",
      },
      {
        title: "Waste & Churn Hotspots",
        detail: "Flags sessions with zero retained code and files rewritten repeatedly across turns.",
      },
      {
        title: "Live Rate Limit Countdowns",
        detail: "Real 5-hour and 7-day rate consumption read directly from Claude Code's local cache.",
      },
    ],
  },
  {
    key: "3",
    name: "Deck 03 · System",
    badge: "⌘3",
    icon: Activity,
    headline: "Kernel-level telemetry, never estimated.",
    description:
      "Direct Mach C-level integration. No estimation algorithms, no polling lag, and zero battery tax.",
    features: [
      {
        title: "Mach HOST_CPU_LOAD_INFO",
        detail: "Reads hardware CPU ticks across Performance & Efficiency clusters independently.",
      },
      {
        title: "Real Mach VM Physical Memory",
        detail: "Measures actual active, wired, compressed, and anonymous page allocations.",
      },
      {
        title: "Dual-Layer POSIX Kill",
        detail: "Graceful termination with instant POSIX SIGKILL fallback for unbundled CLI daemons.",
      },
      {
        title: "Listening Ports Audit",
        detail: "Full table of all bound localhost sockets and their associated PIDs.",
      },
    ],
  },
  {
    key: "4",
    name: "Deck 04 · Storage",
    badge: "⌘4",
    icon: HardDrive,
    headline: "Where your SSD went.",
    description:
      "Deep developer storage analyzer designed specifically for modern dev environments and bloated tooling.",
    features: [
      {
        title: "Dev Cruft Hunter",
        detail: "Scans and reclaims hidden DerivedData, .build, .turbo, and orphaned node_modules.",
      },
      {
        title: "Duplicate File Finder",
        detail: "Rapid Blake3 & SHA-256 content hashing to identify duplicate build artifacts.",
      },
      {
        title: "Deep App Uninstaller",
        detail: "Traces ~/Library Application Support, Caches, and Saved State leftovers.",
      },
    ],
  },
  {
    key: "5",
    name: "Deck 05 · Spend",
    badge: "⌘5",
    icon: Coins,
    headline: "Mathematical spend guardrails.",
    description:
      "Stay in full control of your LLM budget with exact arithmetic and transparent attribution.",
    features: [
      {
        title: "Daily & Weekly Budgets",
        detail: "Visual progress meters that warn you when an automated agent session is runaway.",
      },
      {
        title: "Per-Project & Per-Model",
        detail: "Full attribution splitting Opus, Sonnet, and Haiku calls by repository.",
      },
      {
        title: "Exact Fractional Accounting",
        detail: "Zero rounding errors — calculations preserve micro-cent precision.",
      },
    ],
  },
];

export default function DecksSection() {
  const [selectedDeck, setSelectedDeck] = useState<string>("2");

  const current = DECKS.find((d) => d.key === selectedDeck) || DECKS[1];
  const IconComponent = current.icon;

  return (
    <section id="decks" className="max-w-[1200px] mx-auto px-4 sm:px-6 py-16 md:py-24">
      {/* Section Header */}
      <div className="mb-12">
        <p className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-2">
          Five Specialized Decks · ⌘1 – ⌘5
        </p>
        <h2 className="text-[32px] sm:text-[40px] font-normal text-[#ffffff] tracking-tight">
          The Machine and the Bill, in One Window.
        </h2>
        <p className="text-[16px] text-[#9c9c9d] max-w-[620px] mt-2">
          Switch between five dedicated instruments designed with tactile key-shadow depth and keyboard-first shortcuts.
        </p>
      </div>

      {/* 5-Deck Selector Tabs */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-2.5 mb-8">
        {DECKS.map((deck) => {
          const isSelected = deck.key === selectedDeck;
          const ItemIcon = deck.icon;
          return (
            <button
              key={deck.key}
              onClick={() => setSelectedDeck(deck.key)}
              className={`p-3.5 rounded-[12px] border text-left transition-all ${
                isSelected
                  ? "bg-[#07080a] border-[#ff6363]/60 key-shadow-highlight"
                  : "bg-[#07080a]/50 border-[#363739]/60 hover:border-[#363739] hover:bg-[#07080a]"
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <span
                  className={`w-7 h-7 rounded-full flex items-center justify-center ${
                    isSelected ? "bg-[#ff6363]/10 text-[#ff6363]" : "bg-[#111214] text-[#9c9c9d]"
                  }`}
                >
                  <ItemIcon className="w-3.5 h-3.5" />
                </span>
                <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-[#111214] text-[#6a6b6c] border border-white/5">
                  {deck.badge}
                </span>
              </div>
              <div className={`text-[13px] font-medium truncate ${isSelected ? "text-white" : "text-[#9c9c9d]"}`}>
                {deck.name.replace(/.*·\s*/, "")}
              </div>
            </button>
          );
        })}
      </div>

      {/* Selected Deck Showcase Card with Key Shadow */}
      <div
        className="rounded-[16px] bg-[#07080a] border border-[#363739] p-6 sm:p-8 key-shadow relative overflow-hidden"
      >
        <div className="flex flex-col lg:flex-row lg:items-start justify-between gap-8">
          {/* Left info */}
          <div className="max-w-[500px]">
            <div className="flex items-center gap-3 mb-4">
              {/* Circular Icon Container (99999px radius, dark surface) */}
              <div className="w-12 h-12 rounded-[99999px] bg-[#111214] border border-white/10 flex items-center justify-center text-[#e6e6e6]">
                <IconComponent className="w-6 h-6 text-[#ff6363]" />
              </div>
              <div>
                <span className="text-[11px] font-mono tracking-wider text-[#ff6363] uppercase">
                  {current.name}
                </span>
                <h3 className="text-[22px] font-medium text-white tracking-tight">
                  {current.headline}
                </h3>
              </div>
            </div>

            <p className="text-[15px] text-[#9c9c9d] leading-relaxed mb-6">
              {current.description}
            </p>

            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-[6px] bg-[#111214] border border-white/5 text-[12px] font-mono text-[#6a6b6c]">
              <span>Trigger in app:</span>
              <kbd className="px-1.5 py-0.5 rounded bg-[#1b1c1e] text-white font-mono text-[11px]">
                {current.badge}
              </kbd>
            </div>
          </div>

          {/* Right feature list */}
          <div className="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-4">
            {current.features.map((feat, idx) => (
              <div
                key={idx}
                className="p-4 rounded-[12px] bg-[#111214] border border-[#363739]/60 key-shadow-subtle"
              >
                <div className="flex items-start gap-2.5">
                  <div className="w-4 h-4 rounded-full bg-[#1b1c1e] flex items-center justify-center mt-0.5 shrink-0 text-[#59d499]">
                    <Check className="w-3 h-3" />
                  </div>
                  <div>
                    <h4 className="text-[13px] font-medium text-white mb-1">
                      {feat.title}
                    </h4>
                    <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
                      {feat.detail}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
