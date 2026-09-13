"use client";

import React, { useState, useEffect } from "react";
import { X, Command, Keyboard, Volume2 } from "lucide-react";
import { playClickSound, toggleAudioMute } from "@/utils/audio";
import { useRouter } from "next/navigation";

interface ShortcutItem {
  keys: string[];
  description: string;
  category: "Navigation" | "Cockpit Simulator" | "Audio & Controls";
}

const SHORTCUTS: ShortcutItem[] = [
  { keys: ["⌘", "K"], description: "Open Command Palette / Search", category: "Navigation" },
  { keys: ["1"], description: "Jump to Overview (Home)", category: "Navigation" },
  { keys: ["2"], description: "Jump to Claude Spend Forensics", category: "Navigation" },
  { keys: ["3"], description: "Jump to Mach Vitals & Telemetry", category: "Navigation" },
  { keys: ["4"], description: "Jump to APFS Storage Radar", category: "Navigation" },
  { keys: ["5"], description: "Jump to Architecture & Manifesto", category: "Navigation" },
  { keys: ["M"], description: "Toggle Telemetry Sound Engine (Mute/Unmute)", category: "Audio & Controls" },
  { keys: ["?"], description: "Toggle this Keyboard Shortcuts cheat-sheet", category: "Audio & Controls" },
  { keys: ["Esc"], description: "Dismiss active modal or palette", category: "Audio & Controls" },
];

export default function KeyboardShortcutsModal() {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Avoid firing when user is typing in an input
      const activeEl = document.activeElement as HTMLElement | null;
      if (
        activeEl?.tagName === "INPUT" ||
        activeEl?.tagName === "TEXTAREA" ||
        activeEl?.isContentEditable
      ) {
        return;
      }

      if (e.key === "?" || (e.shiftKey && e.key === "/")) {
        e.preventDefault();
        playClickSound();
        setIsOpen((prev) => !prev);
      } else if (e.key === "Escape" && isOpen) {
        setIsOpen(false);
      } else if (e.key === "m" || e.key === "M") {
        if (!e.metaKey && !e.ctrlKey) {
          toggleAudioMute();
        }
      } else if (!e.metaKey && !e.ctrlKey && !e.altKey) {
        if (e.key === "1") {
          playClickSound();
          router.push("/");
        } else if (e.key === "2") {
          playClickSound();
          router.push("/forensics");
        } else if (e.key === "3") {
          playClickSound();
          router.push("/system");
        } else if (e.key === "4") {
          playClickSound();
          router.push("/storage");
        } else if (e.key === "5") {
          playClickSound();
          router.push("/manifesto");
        }
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, router]);

  return (
    <>
      {/* Floating Bottom-Right Trigger Button */}
      <button
        onClick={() => {
          playClickSound();
          setIsOpen(true);
        }}
        className="fixed bottom-5 right-5 z-40 p-2.5 rounded-full bg-[#111215]/90 hover:bg-[#1b1c20] text-[#9c9c9d] hover:text-white border border-[#26272b] hover:border-white/20 shadow-[0_4px_20px_rgba(0,0,0,0.8)] backdrop-blur-md transition-all flex items-center gap-2 text-[12px] font-mono group"
        title="Keyboard shortcuts (?)"
        aria-label="Keyboard shortcuts"
      >
        <Keyboard className="w-4 h-4 text-[#ff6363] group-hover:rotate-12 transition-transform" />
        <span className="hidden sm:inline text-[#6a6b6c] group-hover:text-white transition-colors">Press</span>
        <kbd className="hidden sm:inline px-1.5 py-0.5 rounded bg-[#1f2024] text-[10px] text-white border border-white/10">?</kbd>
      </button>

      {/* Modal Backdrop */}
      {isOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md animate-fade-in"
          onClick={() => setIsOpen(false)}
        >
          <div
            className="w-full max-w-[560px] rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_24px_64px_rgba(0,0,0,0.9)] overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="flex items-center justify-between px-6 py-4 border-b border-[#232428] bg-[#0c0d10]">
              <div className="flex items-center gap-2.5">
                <div className="w-7 h-7 rounded-[6px] bg-[#18191d] border border-white/10 flex items-center justify-center">
                  <Keyboard className="w-4 h-4 text-[#ff6363]" />
                </div>
                <div>
                  <h3 className="text-[15px] font-medium text-white">Cockpit Keyboard Shortcuts</h3>
                  <p className="text-[11px] font-mono text-[#6a6b6c]">POWER-USER NAVIGATION</p>
                </div>
              </div>

              <button
                onClick={() => setIsOpen(false)}
                className="p-1 rounded-[6px] text-[#6a6b6c] hover:text-white hover:bg-white/5 transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-6 max-h-[70vh] overflow-y-auto space-y-5">
              {["Navigation", "Audio & Controls"].map((category) => {
                const items = SHORTCUTS.filter((s) => s.category === category);
                return (
                  <div key={category}>
                    <div className="text-[11px] font-mono text-[#6a6b6c] uppercase mb-2.5 tracking-wider">
                      {category}
                    </div>
                    <div className="space-y-1.5">
                      {items.map((item, idx) => (
                        <div
                          key={idx}
                          className="flex items-center justify-between p-2 rounded-[8px] hover:bg-white/[0.02] border border-transparent hover:border-white/5 transition-colors"
                        >
                          <span className="text-[13px] text-[#d4d4d4] font-medium">{item.description}</span>
                          <div className="flex items-center gap-1">
                            {item.keys.map((k, i) => (
                              <kbd
                                key={i}
                                className="min-w-[24px] h-[24px] px-1.5 flex items-center justify-center rounded-[5px] bg-[#141518] border border-[#2f3036] text-[11px] font-mono text-white shadow-[0_2px_0_rgba(255,255,255,0.05)]"
                              >
                                {k}
                              </kbd>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Modal Footer */}
            <div className="px-6 py-3 bg-[#040506] border-t border-[#232428] flex items-center justify-between text-[11px] font-mono text-[#6a6b6c]">
              <span>Tip: Press numbers 1–5 to instantly navigate</span>
              <kbd className="px-1.5 py-0.5 rounded bg-[#18191d] text-white border border-white/10">esc</kbd>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
