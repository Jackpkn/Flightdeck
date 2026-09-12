"use client";

import React, { useState } from "react";
import { Check, Copy, Terminal, ChevronRight, Sparkles } from "lucide-react";
import HoloRadar from "./HoloRadar";
import FloatingKeycaps from "./FloatingKeycaps";
import CommandPalette from "./CommandPalette";

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
      <section className="relative pt-28 pb-16 md:pt-36 md:pb-24 overflow-hidden">
        {/* ── Abstract Red/Blue Hero Atmospheric Gradient Geometry (Living & Animated) ── */}
        <div className="absolute inset-0 pointer-events-none overflow-hidden select-none">
          {/* Deep blue radial wash with living pulse */}
          <div
            className="absolute top-[-15%] left-1/2 -translate-x-1/2 w-[1200px] h-[640px] rounded-full opacity-75 animate-aurora-left"
            style={{
              background:
                "radial-gradient(ellipse at 50% 30%, rgba(4, 63, 150, 0.55) 0%, rgba(6, 18, 37, 0.3) 60%, transparent 80%)",
              filter: "blur(70px)",
            }}
          />

          {/* Cobalt Edge & Electric Sky deep angular beam with drifting motion */}
          <div
            className="absolute top-20 left-[6%] w-[580px] h-[300px] -rotate-12 rounded-[100px] opacity-50 animate-aurora-left"
            style={{
              background:
                "linear-gradient(135deg, #143ca3 0%, #63a1ff 70%, transparent 100%)",
              filter: "blur(60px)",
              animationDelay: "-4s",
            }}
          />

          {/* Diagonal Coral Pulse Neon Slashes (Signature Raycast Hero Art with living drift) */}
          <div
            className="absolute top-8 right-[10%] w-[500px] h-[220px] rounded-full opacity-60 animate-aurora-right"
            style={{
              background:
                "linear-gradient(90deg, transparent, #ff6363 45%, #ff6363 60%, transparent)",
              filter: "blur(46px)",
            }}
          />
          <div
            className="absolute top-36 right-[20%] w-[320px] h-[120px] rounded-full opacity-65 animate-aurora-right"
            style={{
              background:
                "radial-gradient(circle, #ff6363 0%, rgba(255, 99, 99, 0.35) 65%, transparent 100%)",
              filter: "blur(38px)",
              animationDelay: "-3s",
            }}
          />

          {/* Technical Cybernetic Matrix Grid Overlay (Crisp & Visible) */}
          <div
            className="absolute inset-0 opacity-25"
            style={{
              backgroundImage: `linear-gradient(to right, rgba(255, 255, 255, 0.1) 1px, transparent 1px), linear-gradient(to bottom, rgba(255, 255, 255, 0.1) 1px, transparent 1px)`,
              backgroundSize: "44px 44px",
              maskImage: "radial-gradient(ellipse at 50% 35%, black 40%, transparent 85%)",
            }}
          />

          {/* Sweeping Laser Scanline Beam traversing the grid */}
          <div className="absolute inset-x-0 h-44 bg-gradient-to-b from-transparent via-[#ff6363]/14 via-[#63a1ff]/10 to-transparent pointer-events-none animate-grid-beam-scan opacity-90" />

          {/* Floating Telemetry Photons / Stars */}
          <div className="absolute inset-0 overflow-hidden pointer-events-none">
            {[
              { top: "18%", left: "15%", delay: "0s" },
              { top: "25%", left: "32%", delay: "1.2s" },
              { top: "12%", left: "75%", delay: "2.5s" },
              { top: "45%", left: "10%", delay: "0.8s" },
              { top: "60%", left: "28%", delay: "3.1s" },
              { top: "35%", left: "85%", delay: "1.9s" },
              { top: "52%", left: "78%", delay: "2.2s" },
              { top: "70%", left: "92%", delay: "0.5s" },
            ].map((p, i) => (
              <div
                key={i}
                className="absolute w-1.5 h-1.5 rounded-full bg-[#ff6363] shadow-[0_0_8px_#ff6363] animate-float-particle"
                style={{
                  top: p.top,
                  left: p.left,
                  animationDelay: p.delay,
                }}
              />
            ))}
          </div>
        </div>

        <div className="relative z-10 max-w-[1200px] mx-auto px-4 sm:px-6">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-8 items-center">
            {/* ── Left Column: Headline & Controls ── */}
            <div className="lg:col-span-7 flex flex-col items-center lg:items-start text-center lg:text-left">
              {/* Eyebrow badge */}
              <div className="inline-flex items-center gap-2 px-3 py-1 mb-6 rounded-[6px] bg-[#111214] border border-[#363739]/80 shadow-[rgba(255,255,255,0.04)_0px_1px_0px_0px_inset]">
                <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
                <span className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase">
                  Developer Cockpit &middot; AI Spend Forensics &middot; macOS 14+
                </span>
              </div>

              {/* Hero Headline: 56px Inter 400, +0.22px tracking, 1.17 line-height */}
              <h1
                className="text-[36px] sm:text-[48px] md:text-[54px] font-normal text-[#ffffff] tracking-[0.22px] leading-[1.15] mb-6"
                style={{ fontFamily: "var(--font-inter)" }}
              >
                You already know what Claude Code cost.
                <br />
                Flightdeck shows what it{" "}
                <span className="text-[#ffffff] underline decoration-[#ff6363] decoration-2 underline-offset-8">
                  became
                </span>
                .
              </h1>

              {/* Subhead: 16px Inter 400, Ash #9c9c9d */}
              <p className="max-w-[580px] text-[16px] md:text-[17px] text-[#9c9c9d] leading-[1.6] mb-8">
                A usage meter stops at the invoice. Flightdeck correlates your Claude Code
                transcripts with your local git history, revealing how much of what the agent wrote
                is still in <code className="text-[13px] px-1.5 py-0.5 rounded bg-[#111214] border border-[#363739]/60 font-mono text-[#ffffff]">HEAD</code> — and what each surviving file actually cost.
              </p>

              {/* Homebrew Terminal Command Box */}
              <div className="w-full max-w-[520px] mb-6">
                <div
                  className="flex items-center justify-between px-3.5 py-2.5 rounded-[8px] bg-[#07080a] border border-[#363739]/80 key-shadow text-left group"
                >
                  <div className="flex items-center gap-3 overflow-hidden">
                    <Terminal className="w-4 h-4 text-[#6a6b6c] shrink-0" />
                    <code className="text-[13px] font-mono text-[#e6e6e6] truncate">
                      {brewCommand}
                    </code>
                  </div>
                  <button
                    onClick={copyBrew}
                    className="ml-2 p-1.5 rounded-[6px] hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-white transition-colors shrink-0"
                    title="Copy to clipboard"
                  >
                    {copied ? (
                      <Check className="w-4 h-4 text-[#59d499]" />
                    ) : (
                      <Copy className="w-4 h-4 text-[#6a6b6c] group-hover:text-[#9c9c9d]" />
                    )}
                  </button>
                </div>
              </div>

              {/* Action Button Group */}
              <div className="flex flex-wrap items-center justify-center lg:justify-start gap-3 mb-8">
                {/* Primary Action — Mist #e6e6e6 fill, Iron #454647 text */}
                <a
                  href="https://github.com/Jackpkn/Flightdeck-releases/releases/latest"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2.5 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#454647] hover:text-[#111214] text-[14px] font-medium px-5 py-2.5 rounded-[8px] transition-all duration-150 btn-lift"
                >
                  <svg className="w-4 h-4 fill-current" viewBox="0 0 170 170">
                    <path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.69-3.04-7.6-7.77-11.74-14.19-6.08-9.43-10.74-19.89-13.98-31.39-3.24-11.5-4.86-22.37-4.86-32.61 0-14.44 3.73-26.4 11.19-35.88 7.46-9.48 17.07-14.33 28.84-14.56 4.79 0 10.36 1.34 16.71 4.02 6.35 2.68 10.22 4.08 11.61 4.2 1.9-.24 5.92-1.63 12.07-4.17 6.15-2.54 11.45-3.75 15.89-3.63 8.35.36 15.65 2.54 21.9 6.53 6.25 3.99 10.79 9.38 13.62 16.17-12.01 7.25-17.91 17.26-17.7 30.03.22 10.02 4.04 18.23 11.47 24.63 7.43 6.4 16.14 10.15 26.13 11.25-2.39 7.02-5.46 14.28-9.21 21.78zM119.22 33.64c0-7.39 2.68-14.34 8.04-20.85 5.36-6.51 12.04-10.79 20.04-12.84.44 1.77.66 3.48.66 5.13 0 7.39-2.73 14.43-8.19 21.12-5.46 6.69-12.18 10.96-20.16 12.81-.22-1.77-.39-3.56-.39-5.37z" />
                  </svg>
                  <span>Download for macOS</span>
                </a>

                <button
                  onClick={() => setCommandPaletteOpen(true)}
                  className="inline-flex items-center gap-2 px-4 py-2.5 rounded-[8px] bg-[#111214] hover:bg-[#1b1c1e] text-[#9c9c9d] hover:text-[#ffffff] text-[14px] font-medium border border-[#363739]/60 transition-all"
                >
                  <span>Press ⌘K</span>
                  <kbd className="px-1.5 py-0.5 rounded bg-[#1b1c1e] text-[#ffffff] font-mono text-[11px] border border-white/10">
                    Palette
                  </kbd>
                </button>
              </div>

              {/* Floating Tactile Keycaps (Raycast signature feature) */}
              <div className="w-full flex justify-center lg:justify-start">
                <FloatingKeycaps
                  onOpenCommandPalette={() => setCommandPaletteOpen(true)}
                />
              </div>
            </div>

            {/* ── Right Column: Interactive Telemetry HoloRadar Cockpit ── */}
            <div className="lg:col-span-5 flex items-center justify-center">
              <HoloRadar />
            </div>
          </div>

          {/* Monospace Footer Metadata Strip with Pipes */}
          <div className="mt-14 pt-8 border-t border-[#1b1c1e] flex flex-wrap items-center justify-center gap-2 text-[12px] font-mono text-[#6a6b6c]">
            <span>v0.8.4</span>
            <span className="text-[#2f3031]">|</span>
            <span>macOS 14+ Sonoma & Sequoia</span>
            <span className="text-[#2f3031]">|</span>
            <span>Apple Silicon & Intel</span>
            <span className="text-[#2f3031]">|</span>
            <span>MIT License</span>
            <span className="text-[#2f3031]">|</span>
            <span className="text-[#59d499]">239 Passing Tests</span>
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
