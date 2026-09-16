"use client";

import React, { useState } from "react";
import { Download, ShieldCheck, Check, Copy, Cpu, Terminal, Sparkles } from "lucide-react";
import { playClickSound, playSuccessChime } from "@/utils/audio";

interface ArchitectureConfig {
  arch: "universal" | "homebrew";
  label: string;
  sublabel: string;
  filename: string;
  size: string;
  sha256: string;
  downloadUrl: string;
}

const ARCH_CONFIGS: Record<"universal" | "homebrew", ArchitectureConfig> = {
  universal: {
    arch: "universal",
    label: "Universal DMG",
    sublabel: "Apple Silicon & Intel Core (Fat Binary)",
    filename: "Flightdeck-0.1.0.dmg",
    size: "12.0 MB",
    sha256: "6dd9eb7f1bed343b0a48c860faac18973d7ef71f020f4ab80bfd4b716dbf0cb3",
    downloadUrl: "https://github.com/Jackpkn/Flightdeck/releases/download/v0.1.0/Flightdeck-0.1.0.dmg",
  },
  homebrew: {
    arch: "homebrew",
    label: "Homebrew Tarball",
    sublabel: "Universal Bottle · Zero Gatekeeper Friction",
    filename: "Flightdeck-0.1.0-universal.tar.gz",
    size: "11.0 MB",
    sha256: "6dd9eb7f1bed343b0a48c860faac18973d7ef71f020f4ab80bfd4b716dbf0cb3",
    downloadUrl: "https://github.com/Jackpkn/Flightdeck/releases/download/v0.1.0/Flightdeck-0.1.0-universal.tar.gz",
  },
};

export default function ReleaseVerificationCard() {
  const [selectedArch, setSelectedArch] = useState<"universal" | "homebrew">("universal");
  const [copiedSha, setCopiedSha] = useState(false);
  const [copiedVerifyCmd, setCopiedVerifyCmd] = useState(false);

  const current = ARCH_CONFIGS[selectedArch];
  const verifyCmd = `echo "${current.sha256} *${current.filename}" | shasum -a 256 -c`;

  const copySha = () => {
    playClickSound();
    navigator.clipboard.writeText(current.sha256);
    setCopiedSha(true);
    setTimeout(() => setCopiedSha(false), 2000);
  };

  const copyVerifyCmd = () => {
    playClickSound();
    navigator.clipboard.writeText(verifyCmd);
    setCopiedVerifyCmd(true);
    playSuccessChime();
    setTimeout(() => setCopiedVerifyCmd(false), 2000);
  };

  return (
    <div className="p-6 sm:p-8 rounded-[16px] bg-[#07080a] border border-[#363739] key-shadow flex flex-col justify-between">
      <div>
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-[8px] bg-[#111214] flex items-center justify-center text-[#e6e6e6]">
              <Download className="w-5 h-5 text-[#38bdf8]" />
            </div>
            <div>
              <h3 className="text-[18px] font-medium text-white">Direct DMG Download</h3>
              <span className="text-[12px] font-mono text-[#9c9c9d]">Cryptographically verified</span>
            </div>
          </div>
          <span className="px-2 py-0.5 rounded-[4px] bg-[#10b981]/10 border border-[#10b981]/30 text-[11px] font-mono text-[#59d499] flex items-center gap-1">
            <ShieldCheck className="w-3 h-3" />
            <span>v0.1.0</span>
          </span>
        </div>

        {/* Architecture Switcher */}
        <div className="grid grid-cols-2 gap-2 p-1 rounded-[10px] bg-[#040506] border border-[#26272b] mb-4">
          {(["universal", "homebrew"] as const).map((archKey) => {
            const config = ARCH_CONFIGS[archKey];
            const isSelected = selectedArch === archKey;
            return (
              <button
                key={archKey}
                onClick={() => {
                  playClickSound();
                  setSelectedArch(archKey);
                }}
                className={`py-2 px-3 rounded-[8px] text-left transition-all duration-150 ${
                  isSelected
                    ? "bg-[#16171a] text-white border border-white/10 shadow-[0_2px_8px_rgba(0,0,0,0.6)]"
                    : "text-[#6a6b6c] hover:text-[#9c9c9d]"
                }`}
              >
                <div className="text-[12px] font-mono font-medium">{config.label}</div>
                <div className="text-[10px] font-mono text-[#6a6b6c]">{config.sublabel}</div>
              </button>
            );
          })}
        </div>

        {/* Binary Details Box */}
        <div className="rounded-[8px] bg-[#040506] border border-[#363739]/80 p-3.5 mb-4 text-[12px] font-mono">
          <div className="flex items-center justify-between text-[#9c9c9d] mb-2 pb-2 border-b border-[#232428]">
            <span>FILE: <code className="text-white">{current.filename}</code></span>
            <span>SIZE: <code className="text-white">{current.size}</code></span>
          </div>

          <div className="flex items-center justify-between text-[#6a6b6c]">
            <span className="truncate pr-2">SHA-256: {current.sha256.slice(0, 20)}...</span>
            <button
              onClick={copySha}
              className="text-[#9c9c9d] hover:text-white flex items-center gap-1 shrink-0"
              title="Copy full SHA-256"
            >
              {copiedSha ? <Check className="w-3.5 h-3.5 text-[#59d499]" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copiedSha ? "COPIED" : "COPY HASH"}</span>
            </button>
          </div>
        </div>

        {/* Verification Command Box */}
        <div className="relative rounded-[8px] bg-[#040506] border border-[#363739]/80 p-3.5 font-mono text-[11px] text-[#e6e6e6] mb-5">
          <div className="text-[10px] text-[#6a6b6c] uppercase mb-1">TERMINAL VERIFY COMMAND</div>
          <pre className="overflow-x-auto pr-8 text-[#9c9c9d]">
            <code>{verifyCmd}</code>
          </pre>
          <button
            onClick={copyVerifyCmd}
            className="absolute top-3 right-3 p-1.5 rounded-[6px] hover:bg-[#1b1c1e] text-[#6a6b6c] hover:text-white transition-colors"
            title="Copy verification command"
          >
            {copiedVerifyCmd ? <Check className="w-3.5 h-3.5 text-[#59d499]" /> : <Copy className="w-3.5 h-3.5" />}
          </button>
        </div>
      </div>

      {/* Primary Download Button */}
      <a
        href={current.downloadUrl}
        target="_blank"
        rel="noopener noreferrer"
        onClick={playClickSound}
        className="w-full flex items-center justify-center gap-2 bg-[#e6e6e6] hover:bg-white text-[#454647] hover:text-[#111214] text-[13px] font-medium py-2.5 rounded-[8px] transition-all btn-lift"
      >
        <Download className="w-4 h-4" />
        <span>Download {current.filename} ({current.size})</span>
      </a>
    </div>
  );
}
