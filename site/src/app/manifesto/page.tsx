import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import HonestyMatrix from "@/components/HonestyMatrix";
import TruthEngineDiff from "@/components/TruthEngineDiff";
import ArchitectureSection from "@/components/ArchitectureSection";
import ManifestoHUDBackground from "@/components/ManifestoHUDBackground";
import { ShieldCheck, ArrowLeft, Lock, Database, ChevronDown } from "lucide-react";
import Link from "next/link";

export const metadata = {
  title: "Measurement Integrity & Architecture — Flightdeck",
  description: "Nothing in this app is a plausible-looking guess. 100% on-device Swift and native Mach C with zero cloud analytics.",
};

export default function ManifestoPage() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />

      <main className="flex-1">
        {/* ── Full-Screen Monumental Hero Section ── */}
        <section className="relative w-full min-h-screen flex flex-col justify-center items-center px-4 sm:px-6 pt-24 pb-16 overflow-hidden">
          <ManifestoHUDBackground />

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
            <div className="inline-flex items-center gap-2 px-3.5 py-1 mb-6 rounded-full bg-[#111214]/90 border border-[#f59e0b]/40 backdrop-blur-md shadow-[0_2px_15px_rgba(245,158,11,0.2)]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#f59e0b] animate-pulse" />
              <span className="text-[11px] font-mono tracking-[0.08em] text-[#e6e6e6] uppercase">
                ENGINEERING PHILOSOPHY &middot; ZERO INVENTIONS &middot; GROUND TRUTH
              </span>
            </div>

            {/* Hero Headline */}
            <h1
              className="text-[40px] sm:text-[56px] md:text-[66px] font-normal text-[#ffffff] tracking-tight leading-[1.1] mb-5 select-none drop-shadow-[0_4px_30px_rgba(0,0,0,0.9)]"
              style={{ fontFamily: "var(--font-inter)" }}
            >
              Nothing in this app
              <br />
              is a plausible-looking
              <br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-[#f59e0b] to-[#eab308] animate-text-shimmer font-medium">
                guess.
              </span>
            </h1>

            {/* Sub-copy */}
            <p className="max-w-[620px] text-[15px] sm:text-[17px] text-[#b4b4b5] leading-[1.6] mb-7 mx-auto drop-shadow-[0_2px_16px_rgba(0,0,0,0.9)]">
              Developer tools quietly invent numbers: a burn rate extrapolated from two samples, a context gauge pinned to a window size it merely assumed. Flightdeck marks what it cannot attribute exactly, and deletes what it cannot measure honestly.
            </p>

            {/* Action Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
              <a
                href="#manifesto-content"
                className="inline-flex items-center gap-2 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#111214] text-[14px] font-medium px-6 py-2.5 rounded-[9px] transition-all duration-150 btn-lift shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
              >
                <span>Read Integrity Rules</span>
              </a>

              <a
                href="#truth-diff"
                className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[9px] bg-[#111214]/80 hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[13px] font-mono border border-[#363739]/80 transition-all backdrop-blur-sm"
              >
                <span>Truth Engine Diff ↓</span>
              </a>
            </div>

            {/* Minimalist Monospace Metadata */}
            <div className="flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono text-[#6a6b6c]">
              <span>100% ON-DEVICE SWIFT &amp; MACH C</span>
              <span className="text-[#363739]">&middot;</span>
              <span>ZERO CLOUD ANALYTICS</span>
              <span className="text-[#363739]">&middot;</span>
              <span>NO PHONE-HOME</span>
            </div>

            {/* Scroll Down Hint */}
            <div className="mt-10 animate-bounce text-[#6a6b6c] flex items-center gap-1.5 text-[11px] font-mono">
              <ChevronDown className="w-3.5 h-3.5 text-[#f59e0b]" />
              <span>SCROLL FOR GROUND TRUTH</span>
            </div>
          </div>
        </section>

        {/* ── Subpage Content Instruments Below the Fold ── */}
        <div id="manifesto-content" className="py-20 md:py-28 max-w-[1240px] mx-auto px-4 sm:px-6 border-t border-[#363739]/40">
          {/* Honesty Rules Matrix Component */}
          <HonestyMatrix />

          {/* Interactive Truth Engine Live Comparison */}
          <div id="truth-diff" className="mt-14">
            <TruthEngineDiff />
          </div>

          {/* Swift & Mach C Architecture Component */}
          <div className="mt-14">
            <ArchitectureSection />
          </div>
        </div>
      </main>

      <Footer />
    </div>
  );
}
