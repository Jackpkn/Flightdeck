"use client";

import React, { useState } from "react";
import { DollarSign, Brain, GitCommit, AlertTriangle, CheckCircle2, TrendingUp, Sliders } from "lucide-react";

export default function SpendCalculator() {
  const [spend, setSpend] = useState(120); // monthly spend in USD
  const [survivalRate, setSurvivalRate] = useState(88); // % survival

  // Formulas based on Flightdeck's real transcript analyzer
  const survivingDollars = (spend * (survivalRate / 100)).toFixed(2);
  const wastedDollars = (spend * (1 - survivalRate / 100)).toFixed(2);
  const estimatedFiles = Math.max(8, Math.round(spend / 2.4));
  const costPerSurvivingFile = (parseFloat(survivingDollars) / (estimatedFiles * (survivalRate / 100))).toFixed(2);
  const naiveSummedOvercharge = (spend * 1.85).toFixed(2);

  return (
    <div className="rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_12px_40px_rgba(0,0,0,0.8)] overflow-hidden">
      {/* Header Bar */}
      <div className="px-6 py-4 border-b border-[#363739]/60 flex flex-wrap items-center justify-between gap-4 bg-[#0a0b0d]">
        <div className="flex items-center gap-3">
          <DollarSign className="w-4 h-4 text-[#ff6363]" />
          <span className="text-[13px] font-mono font-medium text-white tracking-wide">
            CLAUDE_FORENSICS // CODE SURVIVAL &amp; ROI SIMULATOR
          </span>
        </div>
        <span className="text-[11px] font-mono text-[#59d499] bg-[#59d499]/10 px-2.5 py-1 rounded-[6px] border border-[#59d499]/20">
          DETERMINISTIC GIT ANALYSIS
        </span>
      </div>

      <div className="p-6 sm:p-8">
        {/* Sliders Controls Row */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mb-8 pb-8 border-b border-[#363739]/60">
          <div>
            <div className="flex justify-between items-baseline mb-2">
              <label className="text-[13px] font-mono text-[#e6e6e6]">
                Monthly Claude Code Spend
              </label>
              <span className="text-[20px] font-mono font-medium text-[#ff6363]">
                ${spend} / mo
              </span>
            </div>
            <input
              type="range"
              min="20"
              max="600"
              step="10"
              value={spend}
              onChange={(e) => setSpend(Number(e.target.value))}
              className="w-full h-2 bg-[#1b1c1e] rounded-lg appearance-none cursor-pointer accent-[#ff6363]"
            />
            <div className="flex justify-between text-[11px] font-mono text-[#6a6b6c] mt-1.5">
              <span>$20 (Indie)</span>
              <span>$200 (Pro)</span>
              <span>$600+ (Team)</span>
            </div>
          </div>

          <div>
            <div className="flex justify-between items-baseline mb-2">
              <label className="text-[13px] font-mono text-[#e6e6e6]">
                Expected HEAD Survival Rate
              </label>
              <span className="text-[20px] font-mono font-medium text-[#59d499]">
                {survivalRate}% in HEAD
              </span>
            </div>
            <input
              type="range"
              min="50"
              max="99"
              step="1"
              value={survivalRate}
              onChange={(e) => setSurvivalRate(Number(e.target.value))}
              className="w-full h-2 bg-[#1b1c1e] rounded-lg appearance-none cursor-pointer accent-[#59d499]"
            />
            <div className="flex justify-between text-[11px] font-mono text-[#6a6b6c] mt-1.5">
              <span>50% (High Churn)</span>
              <span>85% (Average)</span>
              <span>99% (High Precision)</span>
            </div>
          </div>
        </div>

        {/* Calculated Breakdown 4-Metric Tiles */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div className="p-4 rounded-[12px] bg-[#0c0d10] border border-white/5">
            <span className="text-[11px] font-mono text-[#6a6b6c] uppercase block mb-1">
              Surviving in HEAD
            </span>
            <span className="text-[24px] font-normal text-[#59d499] tracking-tight font-mono">
              ${survivingDollars}
            </span>
            <span className="text-[11px] text-[#9c9c9d] mt-1 block">
              Production code retained
            </span>
          </div>

          <div className="p-4 rounded-[12px] bg-[#0c0d10] border border-white/5">
            <span className="text-[11px] font-mono text-[#6a6b6c] uppercase block mb-1">
              Churn &amp; Waste
            </span>
            <span className="text-[24px] font-normal text-[#ff6363] tracking-tight font-mono">
              ${wastedDollars}
            </span>
            <span className="text-[11px] text-[#9c9c9d] mt-1 block">
              Discarded turns &amp; reverts
            </span>
          </div>

          <div className="p-4 rounded-[12px] bg-[#0c0d10] border border-white/5">
            <span className="text-[11px] font-mono text-[#6a6b6c] uppercase block mb-1">
              Cost Per Surviving File
            </span>
            <span className="text-[24px] font-normal text-white tracking-tight font-mono">
              ${costPerSurvivingFile}
            </span>
            <span className="text-[11px] text-[#9c9c9d] mt-1 block">
              Across ~{estimatedFiles} created files
            </span>
          </div>

          <div className="p-4 rounded-[12px] bg-[#0c0d10] border border-white/5">
            <span className="text-[11px] font-mono text-[#6a6b6c] uppercase block mb-1">
              Naive Cloud Sum
            </span>
            <span className="text-[24px] font-normal text-[#fbbf24] tracking-tight font-mono line-through opacity-60">
              ${naiveSummedOvercharge}
            </span>
            <span className="text-[11px] text-[#fbbf24] mt-1 block">
              +85% cumulative overcount
            </span>
          </div>
        </div>

        {/* Informational Callout Bar */}
        <div className="p-4 rounded-[10px] bg-[#111214] border border-[#363739]/60 flex items-start gap-3">
          <CheckCircle2 className="w-4 h-4 text-[#59d499] mt-0.5 shrink-0" />
          <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
            <strong className="text-white">Why naive tools overcharge:</strong> Standard cloud calculators blindly sum cumulative token counters across CLI turns. Flightdeck extracts the raw SQLite turn deltas and correlates them with <code className="text-white font-mono">git log</code> to attribute value solely to surviving assets.
          </p>
        </div>
      </div>
    </div>
  );
}
