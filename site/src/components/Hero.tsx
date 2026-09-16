"use client";

import React, { useState } from "react";
import { Check, Copy, Terminal } from "lucide-react";
import CommandPalette from "./CommandPalette";
import CockpitHUDBackground from "./CockpitHUDBackground";

export default function Hero() {
  const [copied, setCopied] = useState(false);
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);
  const brewCommand = "brew tap Jackpkn/flightdeck && brew install flightdeck";

  const copyBrew = () => {
    navigator.clipboard.writeText(brewCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <>
      <section className="relative w-full min-h-screen flex flex-col justify-center items-center px-4 sm:px-6 pt-24 pb-16 overflow-hidden">
        {/* ── Bespoke Flightdeck Avionics Cockpit Horizon HUD Background ── */}
        <CockpitHUDBackground />

        {/* ── Centered Monumental Hero Content ── */}
        <div className="relative z-10 w-full max-w-[960px] mx-auto text-center flex flex-col items-center">
          {/* Eyebrow Badge */}
          <div className="inline-flex items-center gap-2 px-3.5 py-1 mb-6 rounded-full bg-[#111214]/90 border border-white/10 backdrop-blur-md shadow-[0_2px_12px_rgba(0,0,0,0.6)]">
            <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
            <span className="text-[11px] font-mono tracking-[0.08em] text-[#e6e6e6] uppercase">
              DEVELOPER COCKPIT &middot; AI SPEND FORENSICS &middot; MACOS 14+
            </span>
          </div>

          {/* Hero Headline: 42px to 68px Inter 400 with Shimmer & Crisp Contrast */}
          <h1
            className="text-[40px] sm:text-[56px] md:text-[68px] font-normal text-[#ffffff] tracking-tight leading-[1.1] mb-5 select-none drop-shadow-[0_4px_30px_rgba(0,0,0,0.9)]"
            style={{ fontFamily: "var(--font-inter)" }}
          >
            You already know what
            <br />
            Claude Code cost.
            <br />
            <span className="text-white">Flightdeck shows what it </span>
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-[#ff6363] to-white animate-text-shimmer font-medium">
              became.
            </span>
          </h1>

          {/* Focused 2-Line Sub-copy */}
          <p className="max-w-[580px] text-[15px] sm:text-[17px] text-[#b4b4b5] leading-[1.6] mb-7 mx-auto drop-shadow-[0_2px_16px_rgba(0,0,0,0.9)]">
            A local-first telemetry cockpit for macOS. Correlates Claude transcripts with your git history to reveal true code survival in <code className="text-white font-mono px-1.5 py-0.5 rounded bg-[#111214]/90 border border-white/10">HEAD</code>.
          </p>

          {/* Primary Action Button & Palette Trigger */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-5">
            <a
              href="https://github.com/Jackpkn/Flightdeck/releases/latest"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2.5 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#454647] hover:text-[#111214] text-[14px] font-medium px-6 py-2.5 rounded-[9px] transition-all duration-150 btn-lift shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
            >
              <svg className="w-4 h-4 fill-current" viewBox="0 0 170 170">
                <path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.69-3.04-7.6-7.77-11.74-14.19-6.08-9.43-10.74-19.89-13.98-31.39-3.24-11.5-4.86-22.37-4.86-32.61 0-14.44 3.73-26.4 11.19-35.88 7.46-9.48 17.07-14.33 28.84-14.56 4.79 0 10.36 1.34 16.71 4.02 6.35 2.68 10.22 4.08 11.61 4.2 1.9-.24 5.92-1.63 12.07-4.17 6.15-2.54 11.45-3.75 15.89-3.63 8.35.36 15.65 2.54 21.9 6.53 6.25 3.99 10.79 9.38 13.62 16.17-12.01 7.25-17.91 17.26-17.7 30.03.22 10.02 4.04 18.23 11.47 24.63 7.43 6.4 16.14 10.15 26.13 11.25-2.39 7.02-5.46 14.28-9.21 21.78zM119.22 33.64c0-7.39 2.68-14.34 8.04-20.85 5.36-6.51 12.04-10.79 20.04-12.84.44 1.77.66 3.48.66 5.13 0 7.39-2.73 14.43-8.19 21.12-5.46 6.69-12.18 10.96-20.16 12.81-.22-1.77-.39-3.56-.39-5.37z" />
              </svg>
              <span>Download for Mac</span>
            </a>

            <button
              onClick={() => setCommandPaletteOpen(true)}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[9px] bg-[#111214]/80 hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[13px] font-mono border border-[#363739]/80 transition-all backdrop-blur-sm"
            >
              <span>Press ⌘K</span>
              <kbd className="px-1.5 py-0.5 rounded bg-black/40 text-[#ff6363] text-[10px] border border-white/10">
                PALETTE
              </kbd>
            </button>
          </div>

          {/* Minimalist Monospace Metadata & Homebrew Quick Copy */}
          <div className="flex flex-col items-center gap-2 text-[11px] font-mono text-[#6a6b6c]">
            <div className="flex items-center gap-2">
              <span>macOS 14+ Sonoma &amp; Sequoia required</span>
              <span className="text-[#2f3031]">&middot;</span>
              <span>Apple Silicon &amp; Intel</span>
            </div>

            <button
              onClick={copyBrew}
              className="inline-flex items-center gap-2 px-3 py-1 rounded-[6px] bg-[#07080a] hover:bg-[#111214] border border-[#363739]/60 text-[#9c9c9d] hover:text-white transition-colors"
            >
              <Terminal className="w-3.5 h-3.5 text-[#6a6b6c]" />
              <span>Install via Homebrew: <code className="text-[#e6e6e6]">brew install flightdeck</code></span>
              {copied ? (
                <Check className="w-3.5 h-3.5 text-[#59d499]" />
              ) : (
                <Copy className="w-3.5 h-3.5 text-[#6a6b6c]" />
              )}
            </button>
          </div>

          {/* Kicker Pill Anchor into Cockpit Simulator */}
          <div className="mt-8">
            <a
              href="#forensics"
              className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-[#111214] border border-[#363739]/80 hover:border-[#ff6363]/50 text-[12px] font-mono text-[#9c9c9d] hover:text-white transition-all group shadow-[0_2px_12px_rgba(0,0,0,0.5)]"
            >
              <span>The Developer Cockpit</span>
              <span className="text-[#ff6363] group-hover:translate-y-0.5 transition-transform">&darr;</span>
            </a>
          </div>
        </div>
      </section>

      {/* Command Palette Modal */}
      <CommandPalette
        isOpen={commandPaletteOpen}
        onClose={() => setCommandPaletteOpen(false)}
      />
    </>
  );
}
