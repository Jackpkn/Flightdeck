"use client";

import React, { useRef, useState } from "react";

interface GlowBorderCardProps {
  children: React.ReactNode;
  className?: string;
  glowColor?: "coral" | "blue" | "green";
}

export default function GlowBorderCard({
  children,
  className = "",
  glowColor = "coral",
}: GlowBorderCardProps) {
  const cardRef = useRef<HTMLDivElement | null>(null);
  const [mousePos, setMousePos] = useState<{ x: number; y: number } | null>(null);
  const [isHovered, setIsHovered] = useState(false);

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!cardRef.current) return;
    const rect = cardRef.current.getBoundingClientRect();
    setMousePos({
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
    });
  };

  const getGlowRgba = () => {
    switch (glowColor) {
      case "blue":
        return "rgba(99, 161, 255, 0.25)";
      case "green":
        return "rgba(89, 212, 153, 0.25)";
      case "coral":
      default:
        return "rgba(255, 99, 99, 0.25)";
    }
  };

  return (
    <div
      ref={cardRef}
      onMouseMove={handleMouseMove}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => {
        setIsHovered(false);
        setMousePos(null);
      }}
      className={`relative rounded-[16px] bg-[#07080a] border border-[#363739]/80 overflow-hidden group transition-all duration-200 ${className}`}
      style={{
        boxShadow:
          "rgba(255, 255, 255, 0.05) 0px 1px 0px 0px inset, rgba(255, 255, 255, 0.2) 0px 0px 0px 1px, rgba(0, 0, 0, 0.4) 0px 4px 20px 0px",
      }}
    >
      {/* Dynamic Cursor Spotlight Radial Glow on Border & Surface */}
      {isHovered && mousePos && (
        <div
          className="pointer-events-none absolute -inset-px rounded-[16px] opacity-100 transition-opacity duration-300"
          style={{
            background: `radial-gradient(400px circle at ${mousePos.x}px ${mousePos.y}px, ${getGlowRgba()}, transparent 70%)`,
          }}
        />
      )}

      {/* Inset content container to preserve card surface */}
      <div className="relative z-10 w-full h-full bg-[#07080a]/95 rounded-[15px] p-6 flex flex-col justify-between">
        {children}
      </div>
    </div>
  );
}
