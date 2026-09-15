"use client";

import React from "react";
import { GitBranch, DollarSign, Flame, ShieldAlert, CheckCircle } from "lucide-react";
import GlowBorderCard from "./GlowBorderCard";
import OutcomePipelineAnimation from "./OutcomePipelineAnimation";

export default function OutcomeDeepDive() {
  return (
    <section className="max-w-[1200px] mx-auto px-4 sm:px-6 py-16 md:py-24 border-t border-[#363739]/40">
      {/* Section Header */}
      <div className="mb-10">
        <p className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-2">
          Deck 02 &middot; Claude Code Forensics &rarr; Outcome Engine
        </p>
        <h2 className="text-[32px] sm:text-[40px] font-normal text-[#ffffff] tracking-tight">
          Cost Per Outcome, Measured Against Your Actual Repository.
        </h2>
        <p className="text-[16px] text-[#9c9c9d] max-w-[680px] mt-2 leading-relaxed">
          Flightdeck matches every file a session touched against <code className="text-white font-mono text-[13px] px-1.5 py-0.5 rounded bg-[#111214] border border-white/5">git</code>: still in <code className="text-white font-mono text-[13px] px-1.5 py-0.5 rounded bg-[#111214] border border-white/5">HEAD</code>, written but reverted, or gone. Then it divides the session's real spend by what actually survived.
        </p>
      </div>

      {/* Animated 3-Stage Pipeline Diagram */}
      <OutcomePipelineAnimation />

      {/* Interactive Cursor Spotlight Glow Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Card 1: Ground Truth vs Cloud Invoices */}
        <GlowBorderCard glowColor="green">
          <div>
            <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#e6e6e6] mb-4">
              <GitBranch className="w-5 h-5 text-[#59d499]" />
            </div>
            <h3 className="text-[18px] font-medium text-white mb-2">
              Git HEAD Correlation
            </h3>
            <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
              Cloud usage meters only see prompt tokens in transit. Flightdeck cross-references session transcripts with your working tree commits to prove whether Claude's code made it to production or died in a rebase.
            </p>
          </div>
          <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#59d499] flex items-center gap-1.5">
            <CheckCircle className="w-3.5 h-3.5" />
            <span>Exact commit SHA linkage</span>
          </div>
        </GlowBorderCard>

        {/* Card 2: Cumulative Ledger Decoding */}
        <GlowBorderCard glowColor="coral">
          <div>
            <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#e6e6e6] mb-4">
              <DollarSign className="w-5 h-5 text-[#ff6363]" />
            </div>
            <h3 className="text-[18px] font-medium text-white mb-2">
              The 200% Billing Trap
            </h3>
            <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
              Claude Code records <em>cumulative</em> turn cost snapshots, not deltas. Third-party extensions that sum these turn figures double your real invoice ($145.93 vs true $72.96). Flightdeck's parser mathematically dedupes snapshot intervals.
            </p>
          </div>
          <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#ff6363] flex items-center gap-1.5">
            <ShieldAlert className="w-3.5 h-3.5" />
            <span>Corrected against Anthropic billing</span>
          </div>
        </GlowBorderCard>

        {/* Card 3: Churn & Documentation Diagnostics */}
        <GlowBorderCard glowColor="blue">
          <div>
            <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#e6e6e6] mb-4">
              <Flame className="w-5 h-5 text-[#63a1ff]" />
            </div>
            <h3 className="text-[18px] font-medium text-white mb-2">
              CLAUDE.md Churn Signals
            </h3>
            <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
              When an agent repeatedly rewrites the same Swift or TypeScript file across sessions, it isn't making progress — it lacks context. Flightdeck pinpoints these churn hotspots so you can add high-leverage architectural rules.
            </p>
          </div>
          <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#63a1ff] flex items-center gap-1.5">
            <CheckCircle className="w-3.5 h-3.5" />
            <span>Eliminate loop cycles</span>
          </div>
        </GlowBorderCard>
      </div>
    </section>
  );
}
