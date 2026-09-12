import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import { HardDrive, ArrowLeft, Trash2, FolderSearch, FileCheck, Layers } from "lucide-react";
import Link from "next/link";
import GlowBorderCard from "@/components/GlowBorderCard";

export const metadata = {
  title: "Disk Radar & Developer Cruft Reclaim — Flightdeck",
  description: "Find where your SSD went. Deep developer cruft cleaning for Xcode DerivedData, SPM .build folders, and duplicate files.",
};

export default function StoragePage() {
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

            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 text-[11px] font-mono text-[#59d499] uppercase mb-4">
              <HardDrive className="w-3.5 h-3.5" />
              <span>Deck 04 &middot; Storage Radar</span>
            </div>

            <h1 className="text-[36px] sm:text-[48px] font-normal text-white tracking-tight leading-[1.15] max-w-[800px] mb-4">
              Where your SSD went.
            </h1>
            <p className="text-[16px] sm:text-[18px] text-[#9c9c9d] max-w-[680px] leading-relaxed">
              Standard cleaners look for Safari cookies and trash bins. Flightdeck is built for software engineers whose 1TB drive is swallowed by hidden <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214] border border-white/10">DerivedData</code>, stale <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214] border border-white/10">.build</code> trees, and duplicate npm tarballs.
            </p>
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
