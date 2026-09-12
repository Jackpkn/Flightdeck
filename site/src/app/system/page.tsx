import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import { Activity, ArrowLeft, Cpu, Terminal, Zap, Shield, Radio } from "lucide-react";
import Link from "next/link";
import GlowBorderCard from "@/components/GlowBorderCard";

export const metadata = {
  title: "Mach Kernel Telemetry & Process Control — Flightdeck",
  description: "Kernel-level hardware telemetry via Mach HOST_CPU_LOAD_INFO, HOST_VM_INFO64, and zero-lag POSIX process kill.",
};

export default function SystemPage() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />

      <main className="flex-1 pt-28 pb-20">
        <div className="max-w-[1240px] mx-auto px-4 sm:px-6">
          {/* Breadcrumb Header */}
          <div className="mb-12">
            <Link
              href="/"
              className="inline-flex items-center gap-2 text-[12px] font-mono text-[#9c9c9d] hover:text-white transition-colors mb-6"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span>Back to Overview</span>
            </Link>

            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 text-[11px] font-mono text-[#56c2ff] uppercase mb-4">
              <Activity className="w-3.5 h-3.5" />
              <span>Deck 03 &middot; Hardware Telemetry</span>
            </div>

            <h1 className="text-[36px] sm:text-[48px] font-normal text-white tracking-tight leading-[1.15] max-w-[800px] mb-4">
              Mach HOST_CPU_LOAD_INFO &amp; Real Memory. Never Estimated.
            </h1>
            <p className="text-[16px] sm:text-[18px] text-[#9c9c9d] max-w-[680px] leading-relaxed">
              Standard Mac monitors spawn shell sub-processes like <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214] border border-white/10">top</code> or <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214] border border-white/10">ps</code>, consuming CPU just to report CPU. Flightdeck talks directly to the Darwin Mach kernel in native C.
            </p>
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
