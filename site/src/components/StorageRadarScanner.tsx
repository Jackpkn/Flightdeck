"use client";

import React, { useState } from "react";
import {
  HardDrive,
  Trash2,
  CheckCircle2,
  FolderSearch,
  RotateCcw,
  Sparkles,
  ArrowRight,
  ShieldCheck,
  Flame,
} from "lucide-react";

interface CruftCategory {
  id: string;
  name: string;
  path: string;
  sizeGB: number;
  itemCount: number;
  color: string;
  reclaimed: boolean;
  desc: string;
}

const INITIAL_CRUFT: CruftCategory[] = [
  {
    id: "derived-data",
    name: "Xcode DerivedData",
    path: "~/Library/Developer/Xcode/DerivedData",
    sizeGB: 18.4,
    itemCount: 42,
    color: "#ff6363",
    reclaimed: false,
    desc: "Stale index databases, compiled module caches, and intermediate dSYMs.",
  },
  {
    id: "spm-build",
    name: "SPM .build Folders",
    path: "~/**/.build (14 repositories)",
    sizeGB: 12.2,
    itemCount: 14,
    color: "#38bdf8",
    reclaimed: false,
    desc: "Swift Package Manager debug & release compilation artifacts.",
  },
  {
    id: "node-modules",
    name: "Orphaned node_modules",
    path: "~/Projects/**/node_modules",
    sizeGB: 14.6,
    itemCount: 28,
    color: "#59d499",
    reclaimed: false,
    desc: "Stale dependencies from unvisited branches and archived repos.",
  },
  {
    id: "cargo-target",
    name: "Cargo target Trees",
    path: "~/Projects/**/target/debug",
    sizeGB: 8.5,
    itemCount: 6,
    color: "#fbbf24",
    reclaimed: false,
    desc: "Rust incremental compilation objects and uncompressed rlib crates.",
  },
];

export default function StorageRadarScanner() {
  const [cruftList, setCruftList] = useState<CruftCategory[]>(INITIAL_CRUFT);
  const [isScanning, setIsScanning] = useState(false);
  const [totalReclaimed, setTotalReclaimed] = useState(0);

  const initialTotal = INITIAL_CRUFT.reduce((acc, c) => acc + c.sizeGB, 0);
  const currentRemaining = cruftList.filter((c) => !c.reclaimed).reduce((acc, c) => acc + c.sizeGB, 0);

  const reclaimItem = (id: string) => {
    setCruftList((prev) =>
      prev.map((c) => {
        if (c.id === id && !c.reclaimed) {
          setTotalReclaimed((t) => t + c.sizeGB);
          return { ...c, reclaimed: true };
        }
        return c;
      })
    );
  };

  const purgeAll = () => {
    setIsScanning(true);
    setTimeout(() => {
      setCruftList((prev) => prev.map((c) => ({ ...c, reclaimed: true })));
      setTotalReclaimed(initialTotal);
      setIsScanning(false);
    }, 1200);
  };

  const resetScanner = () => {
    setCruftList(INITIAL_CRUFT);
    setTotalReclaimed(0);
  };

  return (
    <div className="rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_12px_40px_rgba(0,0,0,0.8)] overflow-hidden">
      {/* Scanner Header Bar */}
      <div className="px-6 py-4 border-b border-[#363739]/60 flex flex-wrap items-center justify-between gap-4 bg-[#0a0b0d]">
        <div className="flex items-center gap-3">
          <HardDrive className="w-4 h-4 text-[#59d499]" />
          <span className="text-[13px] font-mono font-medium text-white tracking-wide">
            DISK_RADAR // APFS CRUFT HUNTER
          </span>
          <span className="text-[#363739]">|</span>
          <span className="text-[11px] font-mono text-[#6a6b6c]">
            SCAN DEPTH: 100% NVMe LOCAL
          </span>
        </div>

        <div className="flex items-center gap-3">
          {totalReclaimed > 0 ? (
            <button
              onClick={resetScanner}
              className="inline-flex items-center gap-1.5 text-[11px] font-mono text-[#9c9c9d] hover:text-white px-3 py-1.5 rounded-[6px] bg-[#111214] border border-[#363739]/80 transition-colors"
            >
              <RotateCcw className="w-3 h-3" />
              <span>Reset Cruft Ledger</span>
            </button>
          ) : (
            <button
              onClick={purgeAll}
              disabled={isScanning}
              className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-[6px] bg-[#59d499] hover:bg-[#6be2aa] text-[#040506] font-mono font-medium text-[12px] transition-all shadow-[0_0_16px_rgba(89,212,153,0.3)] disabled:opacity-50"
            >
              <Sparkles className="w-3.5 h-3.5" />
              <span>{isScanning ? "Scanning Repositories..." : "1-Click Purge All (53.7 GB)"}</span>
            </button>
          )}
        </div>
      </div>

      {/* Disk Usage Gauge Strip */}
      <div className="p-6 bg-[#050608] border-b border-[#363739]/60">
        <div className="flex flex-wrap items-end justify-between gap-4 mb-3">
          <div>
            <span className="text-[11px] font-mono text-[#6a6b6c] uppercase tracking-wider">
              Developer Cruft Accumulation
            </span>
            <div className="text-[28px] font-normal text-white tracking-tight flex items-baseline gap-2 mt-1">
              <span>{currentRemaining.toFixed(1)} GB</span>
              <span className="text-[13px] font-mono text-[#ff6363]">reclaimable</span>
              {totalReclaimed > 0 && (
                <span className="text-[13px] font-mono text-[#59d499] ml-2">
                  (+{totalReclaimed.toFixed(1)} GB freed)
                </span>
              )}
            </div>
          </div>

          <div className="flex items-center gap-4 text-[11px] font-mono">
            {cruftList.map((item) => (
              <div key={item.id} className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full" style={{ backgroundColor: item.color }} />
                <span className={item.reclaimed ? "line-through text-[#454647]" : "text-[#9c9c9d]"}>
                  {item.name}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Multi-segment Storage Bar */}
        <div className="w-full h-3.5 rounded-full bg-[#111214] border border-white/5 overflow-hidden flex">
          {cruftList.map((item) => {
            if (item.reclaimed) return null;
            const pct = (item.sizeGB / initialTotal) * 100;
            return (
              <div
                key={item.id}
                style={{ width: `${pct}%`, backgroundColor: item.color }}
                className="h-full transition-all duration-500 hover:opacity-80"
                title={`${item.name}: ${item.sizeGB} GB`}
              />
            );
          })}
          {currentRemaining === 0 && (
            <div className="w-full h-full bg-[#59d499]/20 flex items-center justify-center text-[9px] font-mono text-[#59d499]">
              DRIVE CLEANED · ZERO CRUFT REMAINING
            </div>
          )}
        </div>
      </div>

      {/* Cruft Category Cards Grid */}
      <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-4 bg-[#07080a]">
        {cruftList.map((item) => {
          return (
            <div
              key={item.id}
              className={`p-4 rounded-[10px] border transition-all duration-300 ${
                item.reclaimed
                  ? "bg-[#0b0d0f]/50 border-white/5 opacity-50"
                  : "bg-[#0c0d10] border-[#363739]/60 hover:border-[#363739]"
              }`}
            >
              <div className="flex items-start justify-between gap-3 mb-2">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full" style={{ backgroundColor: item.color }} />
                    <h5 className="text-[14px] font-medium text-white">{item.name}</h5>
                    <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-white/5 text-[#9c9c9d]">
                      {item.itemCount} targets
                    </span>
                  </div>
                  <code className="text-[11px] font-mono text-[#6a6b6c] mt-1 block">
                    {item.path}
                  </code>
                </div>

                <span className="text-[15px] font-mono font-medium text-white">
                  {item.sizeGB.toFixed(1)} GB
                </span>
              </div>

              <p className="text-[12px] text-[#9c9c9d] mb-4 leading-relaxed">
                {item.desc}
              </p>

              <div className="flex items-center justify-between pt-3 border-t border-white/5">
                <span className="text-[10px] font-mono text-[#59d499] flex items-center gap-1">
                  <ShieldCheck className="w-3 h-3" />
                  Safe to delete (Auto-regenerates)
                </span>

                {item.reclaimed ? (
                  <span className="text-[11px] font-mono text-[#59d499] flex items-center gap-1">
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    Purged
                  </span>
                ) : (
                  <button
                    onClick={() => reclaimItem(item.id)}
                    className="inline-flex items-center gap-1.5 px-3 py-1 rounded-[5px] bg-[#ff6363]/10 hover:bg-[#ff6363]/20 text-[#ff6363] border border-[#ff6363]/30 text-[11px] font-mono transition-colors"
                  >
                    <Trash2 className="w-3 h-3" />
                    <span>Reclaim {item.sizeGB} GB</span>
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
