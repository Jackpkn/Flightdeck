"use client";

import React from "react";
import { ShieldCheck, Info } from "lucide-react";

interface HonestyRule {
  mark: string;
  badgeType: "glyph" | "stale" | "removed";
  title: string;
  body: string;
}

const RULES: HonestyRule[] = [
  {
    mark: "≤",
    badgeType: "glyph",
    title: "At most this much.",
    body: "A windowed spend whose baseline snapshot predates the window — the true figure is somewhere below the mark, and the app says so rather than rounding into a false claim.",
  },
  {
    mark: "≥",
    badgeType: "glyph",
    title: "At least this much.",
    body: "A total that includes a model with no published API price. Real cost is higher by an unknown amount, so the number is presented honestly as a guaranteed floor.",
  },
  {
    mark: "5d old",
    badgeType: "stale",
    title: "Measured, but not now.",
    body: "Plan-limit percentages come from Claude Code's local cache, refreshed only while a session runs. A five-day-old reading describes last week — it gets a stale badge, and it never triggers a phantom alert.",
  },
  {
    mark: "Removed",
    badgeType: "removed",
    title: "Burn rate, and three others.",
    body: "They could not be computed from what is on disk without inventing the inputs, so they are deleted entirely from the interface instead of being decorative filler.",
  },
];

export default function HonestyMatrix() {
  return (
    <section id="honesty" className="max-w-[1200px] mx-auto px-4 sm:px-6 py-16 md:py-20 border-t border-[#363739]/40">
      <div className="mb-12">
        <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded-[6px] bg-[#111214] border border-[#363739]/60 text-[11px] font-mono text-[#9c9c9d] uppercase mb-3">
          <ShieldCheck className="w-3.5 h-3.5 text-[#59d499]" />
          <span>Attribution Integrity</span>
        </div>
        <h2 className="text-[32px] sm:text-[40px] font-normal text-[#ffffff] tracking-tight">
          Nothing in this app is a plausible-looking guess.
        </h2>
        <p className="text-[16px] text-[#9c9c9d] max-w-[660px] mt-2 leading-relaxed">
          Developer tools quietly invent numbers: a burn rate extrapolated from two samples, a context gauge pinned to a window size it merely assumed. Flightdeck marks anything it cannot attribute exactly, and removes what it cannot measure honestly.
        </p>
      </div>

      {/* Rail Rows */}
      <div className="space-y-3">
        {RULES.map((rule, idx) => (
          <div
            key={idx}
            className="p-4 sm:p-5 rounded-[12px] bg-[#07080a] border border-[#363739]/80 key-shadow flex flex-col sm:flex-row sm:items-center gap-4 sm:gap-6 group hover:border-[#363739] transition-colors"
          >
            {/* Mark Badge */}
            <div className="shrink-0 flex items-center">
              <span
                className={`inline-flex items-center justify-center font-mono text-[13px] font-medium px-3 py-1.5 rounded-[6px] min-w-[64px] ${
                  rule.badgeType === "glyph"
                    ? "bg-[#111214] border border-[#ff6363]/40 text-[#ff6363]"
                    : rule.badgeType === "stale"
                    ? "bg-[#111214] border border-[#63a1ff]/40 text-[#63a1ff]"
                    : "bg-[#111214] border border-[#6a6b6c]/40 text-[#9c9c9d]"
                }`}
              >
                {rule.mark}
              </span>
            </div>

            {/* Explanation */}
            <div className="flex-1 text-[14px] leading-relaxed">
              <span className="text-white font-medium mr-2">{rule.title}</span>
              <span className="text-[#9c9c9d]">{rule.body}</span>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
