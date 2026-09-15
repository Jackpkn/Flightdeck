import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import GlowBorderCard from "@/components/GlowBorderCard";
import StorageRadarScanner from "@/components/StorageRadarScanner";
import StorageHUDBackground from "@/components/StorageHUDBackground";
import { HardDrive, ArrowLeft, Trash2, FolderSearch, FileCheck, Layers, ChevronDown } from "lucide-react";
import Link from "next/link";

export const metadata = {
  title: "Disk Radar & Developer Cruft Reclaim — Flightdeck",
  description: "Find where your SSD went. Deep developer cruft cleaning for Xcode DerivedData, SPM .build folders, and duplicate files.",
};

export default function StoragePage() {
  return (
    <div className="min-h-screen bg-[#040506] text-white selection:bg-[#ff6363] selection:text-white flex flex-col">
      <SmoothScroll />
      <Navbar />

      <main className="flex-1">
        {/* ── Full-Screen Monumental Hero Section ── */}
        <section className="relative w-full min-h-screen flex flex-col justify-center items-center px-4 sm:px-6 pt-24 pb-16 overflow-hidden">
          <StorageHUDBackground />

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
            <div className="inline-flex items-center gap-2 px-3.5 py-1 mb-6 rounded-full bg-[#111214]/90 border border-[#10b981]/40 backdrop-blur-md shadow-[0_2px_15px_rgba(16,185,129,0.2)]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#59d499] animate-pulse" />
              <span className="text-[11px] font-mono tracking-[0.08em] text-[#e6e6e6] uppercase">
                DECK 04 &middot; APFS STORAGE RADAR &middot; DEVELOPER CRUFT RECLAIM
              </span>
            </div>

            {/* Hero Headline */}
            <h1
              className="text-[40px] sm:text-[56px] md:text-[66px] font-normal text-[#ffffff] tracking-tight leading-[1.1] mb-5 select-none drop-shadow-[0_4px_30px_rgba(0,0,0,0.9)]"
              style={{ fontFamily: "var(--font-inter)" }}
            >
              Where your SSD
              <br />
              actually went.
              <br />
              <span className="text-white">Xcode, SPM, &amp; build trees </span>
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-[#59d499] to-[#10b981] animate-text-shimmer font-medium">
                reclaimed.
              </span>
            </h1>

            {/* Sub-copy */}
            <p className="max-w-[620px] text-[15px] sm:text-[17px] text-[#b4b4b5] leading-[1.6] mb-7 mx-auto drop-shadow-[0_2px_16px_rgba(0,0,0,0.9)]">
              Built specifically for macOS developers whose 1TB drive is swallowed by hidden DerivedData, abandoned SPM builds, and duplicate node_modules. 1-click purge with auto-regenerate safety tags.
            </p>

            {/* Action Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
              <a
                href="#scanner"
                className="inline-flex items-center gap-2 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#111214] text-[14px] font-medium px-6 py-2.5 rounded-[9px] transition-all duration-150 btn-lift shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
              >
                <span>Launch Cruft Scanner</span>
              </a>

              <a
                href="#scanner"
                className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[9px] bg-[#111214]/80 hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[13px] font-mono border border-[#363739]/80 transition-all backdrop-blur-sm"
              >
                <span>Live Disk Gauge ↓</span>
              </a>
            </div>

            {/* Minimalist Monospace Metadata */}
            <div className="flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono text-[#6a6b6c]">
              <span>APFS FAST DIRECTORY CLONING</span>
              <span className="text-[#363739]">&middot;</span>
              <span>100% REGEN SAFE</span>
              <span className="text-[#363739]">&middot;</span>
              <span>ZERO TRASH DELAYS</span>
            </div>

            {/* Scroll Down Hint */}
            <div className="mt-10 animate-bounce text-[#6a6b6c] flex items-center gap-1.5 text-[11px] font-mono">
              <ChevronDown className="w-3.5 h-3.5 text-[#59d499]" />
              <span>SCROLL FOR STORAGE RADAR</span>
            </div>
          </div>
        </section>

        {/* ── Subpage Content Instruments Below the Fold ── */}
        <div id="scanner" className="py-20 md:py-28 max-w-[1240px] mx-auto px-4 sm:px-6 border-t border-[#363739]/40">
          {/* Interactive Disk Cruft Hunter Scanner */}
          <div className="mb-14">
            <StorageRadarScanner />
          </div>

          {/* Storage Instruments Grid */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
            <GlowBorderCard glowColor="coral">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#ff6363] mb-4">
                  <Trash2 className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Dev Cruft Hunter
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Indexes every Xcode workspace, SPM repository, Cargo target folder, and node cache. Reclaim tens of gigabytes of stale intermediate object files in one click.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#ff6363]">
                Average reclaim: 18&ndash;45 GB per engineer
              </div>
            </GlowBorderCard>

            <GlowBorderCard glowColor="blue">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#63a1ff] mb-4">
                  <FolderSearch className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Blake3 Content Hashing
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Finds exact duplicate files across completely different directories using hardware-accelerated Blake3 hashing. It ignores timestamps and compares cryptographic content.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#63a1ff]">
                Zero false positives &middot; Multithreaded NVMe scan
              </div>
            </GlowBorderCard>

            <GlowBorderCard glowColor="green">
              <div>
                <div className="w-10 h-10 rounded-[8px] bg-[#111214] border border-white/5 flex items-center justify-center text-[#59d499] mb-4">
                  <Layers className="w-5 h-5" />
                </div>
                <h3 className="text-[18px] font-medium text-white mb-2">
                  Deep Leftover Uninstaller
                </h3>
                <p className="text-[13px] text-[#9c9c9d] leading-relaxed mb-4">
                  Moving an app to the Trash leaves behind gigabytes in <code className="text-white font-mono">~/Library/Caches</code>, Application Support, and LaunchAgents. Flightdeck cleans the root and the traces.
                </p>
              </div>
              <div className="pt-4 border-t border-[#1b1c1e] text-[11px] font-mono text-[#59d499]">
                Deep APFS directory traversal
              </div>
            </GlowBorderCard>
          </div>
        </div>
      </main>

      <Footer />
    </div>
  );
}
