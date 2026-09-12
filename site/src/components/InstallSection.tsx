"use client";

import React, { useState } from "react";
import { Terminal, Download, Shield, Check, Copy, AlertTriangle } from "lucide-react";

export default function InstallSection() {
  const [copiedBrew, setCopiedBrew] = useState(false);
  const [copiedXattr, setCopiedXattr] = useState(false);

  const brewCmd = "brew tap Jackpkn/flightdeck\nbrew install flightdeck";
  const xattrCmd = "xattr -d com.apple.quarantine /Applications/Flightdeck.app";

  return (
    <section id="install" className="max-w-[1200px] mx-auto px-4 sm:px-6 py-16 md:py-24 border-t border-[#363739]/40">
      <div className="text-center mb-12">
        <p className="text-[11px] font-mono tracking-[0.08em] text-[#9c9c9d] uppercase mb-2">
          Distribution &amp; Security
        </p>
        <h2 className="text-[32px] sm:text-[40px] font-normal text-[#ffffff] tracking-tight">
          How It Installs
        </h2>
        <p className="text-[16px] text-[#9c9c9d] max-w-[580px] mx-auto mt-2">
          Available via Homebrew tap (clean Gatekeeper bypass) or standalone universal DMG.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Method 1: Homebrew (Recommended) */}
        <div className="p-6 sm:p-8 rounded-[16px] bg-[#07080a] border border-[#363739] key-shadow flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-[8px] bg-[#111214] flex items-center justify-center text-[#e6e6e6]">
                  <Terminal className="w-5 h-5 text-[#59d499]" />
                </div>
                <div>
                  <h3 className="text-[18px] font-medium text-white">Homebrew Tap</h3>
                  <span className="text-[12px] font-mono text-[#59d499]">Recommended method</span>
                </div>
              </div>
              <span className="px-2 py-0.5 rounded-[4px] bg-[#1b1c1e] text-[11px] font-mono text-[#9c9c9d]">
                Zero Gatekeeper Friction
              </span>
            </div>

            <p className="text-[14px] text-[#9c9c9d] leading-relaxed mb-6">
              When installed via Homebrew, macOS sets no quarantine flag. The bottle binary hash is validated against our cryptographically signed release manifest.
            </p>

            <div className="relative rounded-[8px] bg-[#040506] border border-[#363739]/80 p-4 font-mono text-[13px] text-[#e6e6e6] mb-4">
              <pre className="overflow-x-auto">
                <code>{brewCmd}</code>
              </pre>
              <button
                onClick={() => {
                  navigator.clipboard.writeText(brewCmd);
                  setCopiedBrew(true);
                  setTimeout(() => setCopiedBrew(false), 2000);
                }}
                className="absolute top-3 right-3 p-1.5 rounded-[6px] hover:bg-[#1b1c1e] text-[#6a6b6c] hover:text-white transition-colors"
                title="Copy commands"
              >
                {copiedBrew ? <Check className="w-4 h-4 text-[#59d499]" /> : <Copy className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <div className="text-[12px] font-mono text-[#6a6b6c] pt-2">
            Auto-updatable via <code className="text-[#9c9c9d]">brew upgrade flightdeck</code>
          </div>
        </div>

        {/* Method 2: Direct Universal DMG */}
        <div className="p-6 sm:p-8 rounded-[16px] bg-[#07080a] border border-[#363739] key-shadow flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-[8px] bg-[#111214] flex items-center justify-center text-[#e6e6e6]">
                  <Download className="w-5 h-5 text-[#63a1ff]" />
                </div>
                <div>
                  <h3 className="text-[18px] font-medium text-white">Universal DMG</h3>
                  <span className="text-[12px] font-mono text-[#9c9c9d]">Direct browser download</span>
                </div>
              </div>
              <span className="px-2 py-0.5 rounded-[4px] bg-[#1b1c1e] text-[11px] font-mono text-[#9c9c9d]">
                Apple Silicon &amp; Intel
              </span>
            </div>

            <p className="text-[14px] text-[#9c9c9d] leading-relaxed mb-6">
              Browser downloads receive Apple's quarantine bit. If macOS Gatekeeper displays an untrusted developer warning on first launch, clear it in one command:
            </p>

            <div className="relative rounded-[8px] bg-[#040506] border border-[#363739]/80 p-4 font-mono text-[12px] text-[#e6e6e6] mb-6">
              <pre className="overflow-x-auto">
                <code>{xattrCmd}</code>
              </pre>
              <button
                onClick={() => {
                  navigator.clipboard.writeText(xattrCmd);
                  setCopiedXattr(true);
                  setTimeout(() => setCopiedXattr(false), 2000);
                }}
                className="absolute top-3 right-3 p-1.5 rounded-[6px] hover:bg-[#1b1c1e] text-[#6a6b6c] hover:text-white transition-colors"
                title="Copy command"
              >
                {copiedXattr ? <Check className="w-4 h-4 text-[#59d499]" /> : <Copy className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <a
            href="https://github.com/Jackpkn/Flightdeck-releases/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="w-full flex items-center justify-center gap-2 bg-[#e6e6e6] hover:bg-white text-[#454647] hover:text-[#111214] text-[13px] font-medium py-2.5 rounded-[8px] transition-all btn-lift"
          >
            <Download className="w-4 h-4" />
            <span>Download Latest DMG (v0.8.4)</span>
          </a>
        </div>
      </div>
    </section>
  );
}
