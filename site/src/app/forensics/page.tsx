import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import OutcomeDeepDive from "@/components/OutcomeDeepDive";
import { Brain, ArrowLeft, GitCommit, CheckCircle2, AlertTriangle, ShieldCheck } from "lucide-react";
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

      <main className="flex-1 pt-28 pb-20">
        <div className="max-w-[1240px] mx-auto px-4 sm:px-6">
          {/* Breadcrumb Header */}
          <div className="mb-8">
            <Link
              href="/"
              className="inline-flex items-center gap-2 text-[12px] font-mono text-[#9c9c9d] hover:text-white transition-colors mb-6"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span>Back to Overview</span>
            </Link>

            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 text-[11px] font-mono text-[#ff6363] uppercase mb-4">
              <Brain className="w-3.5 h-3.5" />
              <span>Deck 02 &middot; Forensics Engine</span>
            </div>

            <h1 className="text-[36px] sm:text-[48px] font-normal text-white tracking-tight leading-[1.15] max-w-[800px] mb-4">
              Was the spend worth it? Measured against your actual repository.
            </h1>
            <p className="text-[16px] sm:text-[18px] text-[#9c9c9d] max-w-[680px] leading-relaxed">
              Cloud usage dashboards tell you how many tokens passed through Anthropic servers. Flightdeck reads your local session transcripts and your local git history to calculate how much code Claude wrote is still in <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214] border border-white/10">HEAD</code>.
            </p>
          </div>

          {/* Interactive Outcome Engine & Pipeline */}
          <OutcomeDeepDive />

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
