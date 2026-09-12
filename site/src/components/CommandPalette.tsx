"use client";

import React, { useState, useEffect } from "react";
import {
  Search,
  Terminal,
  Activity,
  DollarSign,
  Cpu,
  HardDrive,
  Download,
  ArrowRight,
  Sparkles,
} from "lucide-react";

interface CommandItem {
  id: string;
  title: string;
  category: string;
  shortcut?: string;
  icon: React.ElementType;
  action: () => void;
}

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function CommandPalette({ isOpen, onClose }: CommandPaletteProps) {
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);

  const commands: CommandItem[] = [
    {
      id: "forensics",
      title: "Jump to Claude Code Forensics & Survival",
      category: "Telemetry",
      shortcut: "⌘1",
      icon: DollarSign,
      action: () => {
        document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
        onClose();
      },
    },
    {
      id: "telemetry",
      title: "Inspect Mach Kernel Waveforms (P/E Cores)",
      category: "System",
      shortcut: "⌘2",
      icon: Activity,
      action: () => {
        document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
        onClose();
      },
    },
    {
      id: "process",
      title: "Process Control & 1-Click POSIX Kill",
      category: "System",
      shortcut: "⌘3",
      icon: Cpu,
      action: () => {
        document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
        onClose();
      },
    },
    {
      id: "storage",
      title: "Disk Radar & Dev Cruft Hunter",
      category: "Storage",
      shortcut: "⌘4",
      icon: HardDrive,
      action: () => {
        document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
        onClose();
      },
    },
    {
      id: "brew",
      title: "Copy Homebrew install command",
      category: "Install",
      shortcut: "↵",
      icon: Terminal,
      action: () => {
        navigator.clipboard.writeText("brew tap Jackpkn/flightdeck && brew install flightdeck");
        alert("Copied Homebrew command to clipboard!");
        onClose();
      },
    },
    {
      id: "download",
      title: "Download Universal DMG (macOS 14+)",
      category: "Install",
      icon: Download,
      action: () => {
        window.open(
          "https://github.com/Jackpkn/Flightdeck-releases/releases/latest",
          "_blank"
        );
        onClose();
      },
    },
  ];

  const filtered = commands.filter((c) =>
    c.title.toLowerCase().includes(query.toLowerCase()) ||
    c.category.toLowerCase().includes(query.toLowerCase())
  );

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        isOpen ? onClose() : null;
      }
      if (e.key === "Escape" && isOpen) {
        e.preventDefault();
        onClose();
      }
      if (!isOpen) return;

      if (e.key === "ArrowDown") {
        e.preventDefault();
        setSelectedIndex((prev) => (prev + 1) % (filtered.length || 1));
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setSelectedIndex((prev) => (prev - 1 + filtered.length) % (filtered.length || 1));
      } else if (e.key === "Enter" && filtered[selectedIndex]) {
        e.preventDefault();
        filtered[selectedIndex].action();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, filtered, selectedIndex, onClose]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-24 px-4 bg-black/70 backdrop-blur-md transition-opacity"
      onClick={onClose}
    >
      <div
        className="w-full max-w-[620px] rounded-[16px] bg-[#07080a] border border-[#363739] shadow-[0_32px_120px_rgba(0,0,0,0.9)] overflow-hidden animate-in fade-in zoom-in-95 duration-150"
        style={{
          boxShadow:
            "rgba(255, 255, 255, 0.08) 0px 1px 0px 0px inset, rgba(255, 255, 255, 0.25) 0px 0px 0px 1px, rgba(0, 0, 0, 0.8) 0px 30px 90px 10px",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Search Input Well */}
        <div className="p-3 bg-[#040506] border-b border-[#363739]/60 flex items-center gap-3">
          <Search className="w-4 h-4 text-[#ff6363] ml-2 shrink-0" />
          <input
            autoFocus
            type="text"
            placeholder="Type a command or search decks..."
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setSelectedIndex(0);
            }}
            className="w-full bg-transparent text-[15px] font-sans text-white placeholder-[#6a6b6c] outline-none"
          />
          <kbd className="px-2 py-0.5 rounded bg-[#111214] border border-white/10 text-[10px] font-mono text-[#9c9c9d]">
            ESC
          </kbd>
        </div>

        {/* Results List */}
        <div className="max-h-[340px] overflow-y-auto p-2 divide-y divide-white/5">
          {filtered.length === 0 ? (
            <div className="p-8 text-center text-[13px] text-[#6a6b6c] font-mono">
              No matching commands found
            </div>
          ) : (
            filtered.map((cmd, idx) => {
              const isSelected = idx === selectedIndex;
              const Icon = cmd.icon;
              return (
                <div
                  key={cmd.id}
                  onClick={() => cmd.action()}
                  onMouseEnter={() => setSelectedIndex(idx)}
                  className={`flex items-center justify-between px-3.5 py-2.5 rounded-[8px] cursor-pointer transition-colors ${
                    isSelected
                      ? "bg-[#1b1c1e] text-white shadow-[rgba(255,255,255,0.05)_0px_1px_0px_0px_inset]"
                      : "text-[#9c9c9d] hover:bg-white/5"
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <span
                      className={`w-7 h-7 rounded-[6px] flex items-center justify-center ${
                        isSelected ? "bg-[#ff6363]/15 text-[#ff6363]" : "bg-[#111214] text-[#6a6b6c]"
                      }`}
                    >
                      <Icon className="w-3.5 h-3.5" />
                    </span>
                    <div>
                      <div className="text-[13px] font-medium text-white font-sans">
                        {cmd.title}
                      </div>
                      <div className="text-[11px] font-mono text-[#6a6b6c]">
                        {cmd.category}
                      </div>
                    </div>
                  </div>

                  {cmd.shortcut && (
                    <kbd className="px-1.5 py-0.5 rounded bg-[#111214] border border-white/5 text-[11px] font-mono text-[#9c9c9d]">
                      {cmd.shortcut}
                    </kbd>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Footer Meta */}
        <div className="px-4 py-2.5 bg-[#040506] border-t border-[#363739]/60 flex items-center justify-between text-[11px] font-mono text-[#6a6b6c]">
          <div className="flex items-center gap-3">
            <span>&uarr;&darr; Navigate</span>
            <span>↵ Select</span>
            <span>esc Close</span>
          </div>
          <span className="text-[#ff6363]">Raycast Command Palette</span>
        </div>
      </div>
    </div>
  );
}
