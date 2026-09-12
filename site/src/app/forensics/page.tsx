import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import OutcomeDeepDive from "@/components/OutcomeDeepDive";
import SpendCalculator from "@/components/SpendCalculator";
import ForensicsHUDBackground from "@/components/ForensicsHUDBackground";
import { Brain, ArrowLeft, GitCommit, CheckCircle2, AlertTriangle, ShieldCheck, ChevronDown } from "lucide-react";
import Link from "next/link";

export const metadata = {
  title: "Claude Code Forensics & Outcome Engine — Flightdeck",
  description: "Measure what your Claude Code spend actually produced — code survival in git HEAD, cost per surviving file, and waste reports.",
};

export default function ForensicsPage() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />

      <main className="flex-1">
        {/* ── Full-Screen Monumental Hero Section ── */}
        <section className="relative w-full min-h-screen flex flex-col justify-center items-center px-4 sm:px-6 pt-24 pb-16 overflow-hidden">
          <ForensicsHUDBackground />

          <div className="relative z-10 w-full max-w-[960px] mx-auto text-center flex flex-col items-center">
            {/* Breadcrumb Back Link */}
            <Link
              href="/"
              className="inline-flex items-center gap-2 text-[12px] font-mono text-[#9c9c9d] hover:text-white transition-colors mb-6"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span>Back to Overview</span>
            </Link>

            {/* Eyebrow Badge */}
            <div className="inline-flex items-center gap-2 px-3.5 py-1 mb-6 rounded-full bg-[#111214]/90 border border-[#8b5cf6]/40 backdrop-blur-md shadow-[0_2px_15px_rgba(139,92,246,0.2)]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#f59e0b] animate-pulse" />
              <span className="text-[11px] font-mono tracking-[0.08em] text-[#e6e6e6] uppercase">
                DECK 02 &middot; CLAUDE CODE FORENSICS &middot; DETERMINISTIC GIT AUDIT
              </span>
            </div>

            {/* Hero Headline */}
            <h1
              className="text-[40px] sm:text-[56px] md:text-[66px] font-normal text-[#ffffff] tracking-tight leading-[1.1] mb-5 select-none drop-shadow-[0_4px_30px_rgba(0,0,0,0.9)]"
              style={{ fontFamily: "var(--font-inter)" }}
            >
              You know what
              <br />
              Claude Code billed.
              <br />
              <span className="text-white">Flightdeck proves what survived in </span>
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-[#f59e0b] via-[#ff6363] to-[#8b5cf6] animate-text-shimmer font-medium">
                HEAD.
              </span>
            </h1>

            {/* Sub-copy */}
            <p className="max-w-[620px] text-[15px] sm:text-[17px] text-[#b4b4b5] leading-[1.6] mb-7 mx-auto drop-shadow-[0_2px_16px_rgba(0,0,0,0.9)]">
              Cloud usage meters only count API tokens passed through Anthropic servers. Flightdeck cross-references local session transcripts with your git working tree to prove real code survival.
            </p>

            {/* Action Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
              <a
                href="#pipeline"
                className="inline-flex items-center gap-2 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#111214] text-[14px] font-medium px-6 py-2.5 rounded-[9px] transition-all duration-150 btn-lift shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
              >
                <span>Inspect Outcome Pipeline</span>
              </a>

              <a
                href="#calculator"
                className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[9px] bg-[#111214]/80 hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[13px] font-mono border border-[#363739]/80 transition-all backdrop-blur-sm"
              >
                <span>Live ROI Simulator ↓</span>
              </a>
            </div>

            {/* Minimalist Monospace Metadata */}
            <div className="flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono text-[#6a6b6c]">
              <span>LOCAL SQLITE LEDGER</span>
              <span className="text-[#363739]">&middot;</span>
              <span>ZERO INVENTIONS</span>
              <span className="text-[#363739]">&middot;</span>
              <span>100% PRIVATE &amp; ON-DEVICE</span>
            </div>

            {/* Scroll Down Hint */}
            <div className="mt-10 animate-bounce text-[#6a6b6c] flex items-center gap-1.5 text-[11px] font-mono">
              <ChevronDown className="w-3.5 h-3.5 text-[#f59e0b]" />
              <span>SCROLL FOR OUTCOME ENGINE</span>
            </div>
          </div>
        </section>

        {/* ── Subpage Content Instruments Below the Fold ── */}
        <div className="py-20 md:py-28 max-w-[1240px] mx-auto px-4 sm:px-6 border-t border-[#363739]/40">
          {/* Interactive Outcome Engine & Pipeline */}
          <div id="pipeline">
            <OutcomeDeepDive />
          </div>

          {/* Interactive ROI & Survival Simulator */}
          <div id="calculator" className="mt-14">
            <SpendCalculator />
          </div>

          {/* Detailed Attribution Rules Table */}
          <div className="mt-12 p-6 sm:p-8 rounded-[16px] bg-[#07080a] border border-[#363739] key-shadow">
            <div className="flex items-center justify-between mb-6 pb-4 border-b border-[#363739]/60">
              <div>
                <h3 className="text-[18px] font-medium text-white">
                  Deterministic Attribution Matrix
                </h3>
                <p className="text-[12px] text-[#6a6b6c] mt-0.5">
                  How Flightdeck attributes every cent without extrapolation or guessing.
                </p>
              </div>
              <span className="px-2.5 py-1 rounded-[6px] bg-[#111214] border border-white/5 text-[11px] font-mono text-[#59d499]">
                SQLite Local Ledger
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-[13px]">
              <div className="space-y-4">
                <div className="p-4 rounded-[10px] bg-[#111214] border border-white/5">
                  <span className="font-mono text-[#59d499] block mb-1">1. Code Survival Ratio</span>
                  <p className="text-[#9c9c9d] leading-relaxed">
                    Calculated by executing a git blob existence check on every path touched by the session. If a file was written in turn 4 but deleted in turn 12, it is attributed as session churn.
                  </p>
                </div>
                <div className="p-4 rounded-[10px] bg-[#111214] border border-white/5">
                  <span className="font-mono text-[#ff6363] block mb-1">2. Waste Diagnostic</span>
                  <p className="text-[#9c9c9d] leading-relaxed">
                    Flags conversation threads where context ceilings forced repeated re-reading of source trees, or where failed tool calls generated billed tokens without writing persistent code.
                  </p>
                </div>
              </div>

              <div className="space-y-4">
                <div className="p-4 rounded-[10px] bg-[#111214] border border-white/5">
                  <span className="font-mono text-[#63a1ff] block mb-1">3. Churn Signals</span>
                  <p className="text-[#9c9c9d] leading-relaxed">
                    Highlights files modified repeatedly across distinct sessions. This directly informs where your repository lacks clear architectural documentation or needs a targeted <code className="text-white">CLAUDE.md</code> rule.
                  </p>
                </div>
                <div className="p-4 rounded-[10px] bg-[#111214] border border-white/5">
                  <span className="font-mono text-[#e6e6e6] block mb-1">4. Rate Limit Reset Countdowns</span>
                  <p className="text-[#9c9c9d] leading-relaxed">
                    Tracks the real 5-hour and 7-day rate consumption read directly from Claude Code's local cache on disk, complete with exact reset countdown timers.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>

      <Footer />
    </div>
  );
}
