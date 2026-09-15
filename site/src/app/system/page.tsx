import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import GlowBorderCard from "@/components/GlowBorderCard";
import MachWaveformSimulator from "@/components/MachWaveformSimulator";
import SystemHUDBackground from "@/components/SystemHUDBackground";
import { Activity, ArrowLeft, Cpu, Terminal, Zap, Shield, Radio, ChevronDown } from "lucide-react";
import Link from "next/link";

export const metadata = {
  title: "Mach Kernel Telemetry & Process Control — Flightdeck",
  description: "Kernel-level hardware telemetry via Mach HOST_CPU_LOAD_INFO, HOST_VM_INFO64, and zero-lag POSIX process kill.",
};

export default function SystemPage() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />

      <main className="flex-1">
        {/* ── Full-Screen Monumental Hero Section ── */}
        <section className="relative w-full min-h-screen flex flex-col justify-center items-center px-4 sm:px-6 pt-24 pb-16 overflow-hidden">
          <SystemHUDBackground />

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
            <div className="inline-flex items-center gap-2 px-3.5 py-1 mb-6 rounded-full bg-[#111214]/90 border border-[#00f0ff]/40 backdrop-blur-md shadow-[0_2px_15px_rgba(0,240,255,0.2)]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#00f0ff] animate-pulse" />
              <span className="text-[11px] font-mono tracking-[0.08em] text-[#e6e6e6] uppercase">
                DECK 03 &middot; DARWIN MACH KERNEL &middot; DIRECT HARDWARE WIRE
              </span>
            </div>

            {/* Hero Headline */}
            <h1
              className="text-[40px] sm:text-[56px] md:text-[66px] font-normal text-[#ffffff] tracking-tight leading-[1.1] mb-5 select-none drop-shadow-[0_4px_30px_rgba(0,0,0,0.9)]"
              style={{ fontFamily: "var(--font-inter)" }}
            >
              Mach HOST_CPU_LOAD_INFO.
              <br />
              Real physical memory.
              <br />
              <span className="text-white">Zero shell lag. </span>
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-[#00f0ff] to-[#38bdf8] animate-text-shimmer font-medium">
                Never guessed.
              </span>
            </h1>

            {/* Sub-copy */}
            <p className="max-w-[620px] text-[15px] sm:text-[17px] text-[#b4b4b5] leading-[1.6] mb-7 mx-auto drop-shadow-[0_2px_16px_rgba(0,0,0,0.9)]">
              Standard Mac monitors run shell tools that spike CPU just to measure CPU. Flightdeck binds directly to Darwin Mach kernel C APIs with 0ms UI lag and 1-click POSIX process termination.
            </p>

            {/* Action Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
              <a
                href="#oscilloscope"
                className="inline-flex items-center gap-2 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#111214] text-[14px] font-medium px-6 py-2.5 rounded-[9px] transition-all duration-150 btn-lift shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
              >
                <span>Launch Kernel Oscilloscope</span>
              </a>

              <a
                href="#oscilloscope"
                className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[9px] bg-[#111214]/80 hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[13px] font-mono border border-[#363739]/80 transition-all backdrop-blur-sm"
              >
                <span>Try Process Kill ↓</span>
              </a>
            </div>

            {/* Minimalist Monospace Metadata */}
            <div className="flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono text-[#6a6b6c]">
              <span>1000Hz KERNEL DIRECT</span>
              <span className="text-[#363739]">&middot;</span>
              <span>P-CORE VS E-CORE CLUSTERS</span>
              <span className="text-[#363739]">&middot;</span>
              <span>0ms IPC OVERHEAD</span>
            </div>

            {/* Scroll Down Hint */}
            <div className="mt-10 animate-bounce text-[#6a6b6c] flex items-center gap-1.5 text-[11px] font-mono">
              <ChevronDown className="w-3.5 h-3.5 text-[#00f0ff]" />
              <span>SCROLL FOR HARDWARE OSCILLOSCOPE</span>
            </div>
          </div>
        </section>

        {/* ── Subpage Content Instruments Below the Fold ── */}
        <div id="oscilloscope" className="py-20 md:py-28 max-w-[1240px] mx-auto px-4 sm:px-6 border-t border-[#363739]/40">
          {/* Interactive 1000Hz Mach Kernel Oscilloscope & POSIX Sandbox */}
          <div className="mb-14">
            <MachWaveformSimulator />
          </div>

          {/* 4 Core Pillars Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-12">
            <GlowBorderCard glowColor="blue">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#56c2ff] mb-4">
                  <Cpu className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Performance &amp; Efficiency Cores
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Reads raw hardware CPU ticks directly via <code className="text-white font-mono">host_processor_info()</code>. It differentiates heavy compilation workloads on P-Cores from background daemon tasks running quietly on E-Cores.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#56c2ff]">
                Zero IPC shell overhead &middot; Microsecond tick registers
              </div>
            </GlowBorderCard>

            <GlowBorderCard glowColor="coral">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#ff6363] mb-4">
                  <Zap className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Dual-Layer Zero-Lag Process Kill
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  First requests graceful termination through <code className="text-white font-mono">NSRunningApplication.forceTerminate()</code>, falling back immediately to POSIX <code className="text-white font-mono">kill(pid, SIGKILL)</code> for unbundled CLI tools and runaway node daemons.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#ff6363]">
                0ms UI reaction &middot; Instant process removal
              </div>
            </GlowBorderCard>

            <GlowBorderCard glowColor="green">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#59d499] mb-4">
                  <Shield className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Real Physical Mach VM Memory
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Queries <code className="text-white font-mono">HOST_VM_INFO64</code> to accurately report wired kernel memory, active app allocations, and compressed swap. No artificial &ldquo;Memory Clean&rdquo; illusions.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#59d499]">
                Active, Wired, Compressed page tables
              </div>
            </GlowBorderCard>

            <GlowBorderCard glowColor="blue">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#63a1ff] mb-4">
                  <Radio className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  BSD getifaddrs &amp; Listening Ports
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Enumerates physical interface packet counters (<code className="text-white font-mono">en0</code>, <code className="text-white font-mono">en1</code>) and maps all local listening TCP sockets to their owning PID so you know what is running on <code className="text-white font-mono">:3000</code> or <code className="text-white font-mono">:8080</code>.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#63a1ff]">
                Zero network polling tax &middot; Local socket audit
              </div>
            </GlowBorderCard>
          </div>
        </div>
      </main>

      <Footer />
    </div>
  );
}
