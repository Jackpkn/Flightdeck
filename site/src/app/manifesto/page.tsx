import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import SmoothScroll from "@/components/SmoothScroll";
import HonestyMatrix from "@/components/HonestyMatrix";
import ArchitectureSection from "@/components/ArchitectureSection";
import { ShieldCheck, ArrowLeft, Lock, Database } from "lucide-react";
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
              <ShieldCheck className="w-3.5 h-3.5" />
              <span>Engineering Philosophy &middot; Ground Truth</span>
            </div>

            <h1 className="text-[36px] sm:text-[48px] font-normal text-white tracking-tight leading-[1.15] max-w-[800px] mb-4">
              Nothing in this app is a plausible-looking guess.
            </h1>
            <p className="text-[16px] sm:text-[18px] text-[#9c9c9d] max-w-[680px] leading-relaxed">
              Monitoring tools quietly invent numbers: a burn rate extrapolated from two samples, a context gauge pinned to a window size it assumed. Flightdeck marks anything it cannot attribute exactly, and deletes what it cannot measure honestly at all.
            </p>
          </div>

          {/* Honesty Rules Matrix Component */}
          <HonestyMatrix />

          {/* Swift & Mach C Architecture Component */}
          <ArchitectureSection />
        </div>
      </main>

      <Footer />
    </div>
  );
}
