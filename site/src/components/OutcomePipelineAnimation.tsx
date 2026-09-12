"use client";

import React, { useEffect, useState } from "react";
import { GitCommit, ArrowRight, ShieldCheck, Zap, Sparkles, CornerDownRight } from "lucide-react";

export default function OutcomePipelineAnimation() {
  const [activeStep, setActiveStep] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setActiveStep((prev) => (prev + 1) % 3);
    }, 2400);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="w-full rounded-[16px] bg-[#07080a] border border-[#363739]/80 p-6 md:p-8 key-shadow relative overflow-hidden mb-8">
      {/* Background ambient gradient glow */}
      <div
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[180px] rounded-full opacity-20 pointer-events-none"
        style={{
          background: "radial-gradient(circle, #ff6363 0%, #63a1ff 50%, transparent 80%)",
          filter: "blur(50px)",
        }}
      />

      <div className="relative z-10">
        <div className="flex flex-wrap items-center justify-between gap-2 mb-6">
          <span className="text-[11px] font-mono tracking-wider text-[#9c9c9d] uppercase flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-[#59d499] animate-pulse" />
            Deterministic Outcome Pipeline &middot; Live Flow
          </span>
          <span className="text-[11px] font-mono text-[#6a6b6c]">
            Git SHA: 41d7a11b &rarr; HEAD
          </span>
        </div>

        {/* 3-Stage Pipeline Diagram */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 relative">
          {/* Stage 1: Claude Code Output */}
          <div
            className={`p-4 rounded-[12px] border transition-all duration-300 ${
              activeStep === 0
                ? "bg-[#111214] border-[#ff6363]/80 shadow-[0_0_20px_rgba(255,99,99,0.15)]"
                : "bg-[#040506]/60 border-[#363739]/60"
            }`}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-[11px] font-mono text-[#ff6363] uppercase">Stage 01</span>
              <span className="w-2 h-2 rounded-full bg-[#ff6363]" />
            </div>
            <div className="text-[15px] font-medium text-white mb-1">
              Claude Session Spend
            </div>
            <div className="text-[20px] font-mono font-medium text-[#ffffff] mb-2">
              $72.96
            </div>
            <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
              48 conversation turns &middot; 55 files staged in buffer.
            </p>
          </div>

          {/* Stage 2: Git Working Tree */}
          <div
            className={`p-4 rounded-[12px] border transition-all duration-300 ${
              activeStep === 1
                ? "bg-[#111214] border-[#63a1ff]/80 shadow-[0_0_20px_rgba(99,161,255,0.15)]"
                : "bg-[#040506]/60 border-[#363739]/60"
            }`}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-[11px] font-mono text-[#63a1ff] uppercase">Stage 02</span>
              <span className="w-2 h-2 rounded-full bg-[#63a1ff]" />
            </div>
            <div className="text-[15px] font-medium text-white mb-1">
              Local NVMe Verification
            </div>
            <div className="text-[20px] font-mono font-medium text-[#63a1ff] mb-2">
              55 Files Tracked
            </div>
            <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
              Matched against local repository working tree on disk.
            </p>
          </div>

          {/* Stage 3: Survival in HEAD */}
          <div
            className={`p-4 rounded-[12px] border transition-all duration-300 ${
              activeStep === 2
                ? "bg-[#111214] border-[#59d499]/80 shadow-[0_0_20px_rgba(89,212,153,0.15)]"
                : "bg-[#040506]/60 border-[#363739]/60"
            }`}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-[11px] font-mono text-[#59d499] uppercase">Stage 03</span>
              <span className="w-2 h-2 rounded-full bg-[#59d499]" />
            </div>
            <div className="text-[15px] font-medium text-white mb-1">
              Survival in git HEAD
            </div>
            <div className="text-[20px] font-mono font-medium text-[#59d499] mb-2">
              96.4% Kept ($2.35/file)
            </div>
            <p className="text-[12px] text-[#9c9c9d] leading-relaxed">
              53 surviving files retained across subsequent commits.
            </p>
          </div>
        </div>

        {/* Dynamic Animated Laser Bar connecting stages */}
        <div className="mt-6 pt-4 border-t border-[#1b1c1e] flex flex-wrap items-center justify-between gap-3 text-[12px] font-mono text-[#6a6b6c]">
          <div className="flex items-center gap-2">
            <Zap className="w-3.5 h-3.5 text-[#ff6363] animate-pulse" />
            <span className="text-[#9c9c9d]">
              Live attribution audit running silently on your machine.
            </span>
          </div>
          <div className="flex items-center gap-1 text-[11px] text-[#59d499]">
            <ShieldCheck className="w-3.5 h-3.5" />
            <span>Zero telemetry sent to cloud</span>
          </div>
        </div>
      </div>
    </div>
  );
}
