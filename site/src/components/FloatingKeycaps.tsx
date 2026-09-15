"use client";

import React, { useState } from "react";

interface KeycapProps {
  label: string;
  sublabel?: string;
  onClick: () => void;
  highlight?: boolean;
}

function Keycap({ label, sublabel, onClick, highlight }: KeycapProps) {
  const [pressed, setPressed] = useState(false);

  return (
    <button
      onClick={onClick}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => setPressed(false)}
      onMouseLeave={() => setPressed(false)}
      className={`group relative flex flex-col items-center justify-center min-w-[54px] h-[52px] px-3.5 rounded-[10px] select-none transition-all duration-100 ${
        pressed ? "translate-y-[2px]" : "hover:-translate-y-[1px]"
      } ${
        highlight
          ? "bg-[#111214] border border-[#ff6363]/60"
          : "bg-[#07080a] border border-[#363739]/90"
      }`}
      style={{
        boxShadow: pressed
          ? "rgba(0,0,0,0.6) 0px 1px 1px 0px inset, rgba(255,255,255,0.08) 0px 0px 0px 1px"
          : "rgba(255, 255, 255, 0.08) 0px 1px 0px 0px inset, rgba(255, 255, 255, 0.25) 0px 0px 0px 1px, rgba(0, 0, 0, 0.5) 0px 4px 6px 0px, rgba(0, 0, 0, 0.3) 0px -1px 0px 0px inset",
      }}
      title={`Shortcut: ${label} ${sublabel || ""}`}
    >
      <span
        className={`text-[15px] font-mono font-medium leading-none ${
          highlight ? "text-[#ff6363]" : "text-white"
        }`}
      >
        {label}
      </span>
      {sublabel && (
        <span className="text-[10px] font-mono text-[#6a6b6c] mt-1 uppercase tracking-wider">
          {sublabel}
        </span>
      )}
    </button>
  );
}

interface FloatingKeycapsBarProps {
  onOpenCommandPalette: () => void;
}

export default function FloatingKeycaps({ onOpenCommandPalette }: FloatingKeycapsBarProps) {
  return (
    <div className="flex flex-wrap items-center justify-center gap-3 p-2 rounded-[14px] bg-[#040506]/80 border border-[#363739]/50 backdrop-blur-md">
      <div className="flex items-center gap-1.5 px-2 text-[11px] font-mono text-[#6a6b6c] hidden sm:flex">
        <span>KEYBOARD FIRST:</span>
      </div>

      <div className="flex items-center gap-2">
        <Keycap
          label="⌘K"
          sublabel="Palette"
          highlight={true}
          onClick={onOpenCommandPalette}
        />
        <Keycap
          label="⌘1"
          sublabel="Spend"
          onClick={() => {
            document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
          }}
        />
        <Keycap
          label="⌘2"
          sublabel="Mach"
          onClick={() => {
            document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
          }}
        />
        <Keycap
          label="⌘3"
          sublabel="Kill"
          onClick={() => {
            document.getElementById("forensics")?.scrollIntoView({ behavior: "smooth" });
          }}
        />
        <Keycap
          label="⎋"
          sublabel="Esc"
          onClick={() => {
            window.scrollTo({ top: 0, behavior: "smooth" });
          }}
        />
      </div>
    </div>
  );
}
