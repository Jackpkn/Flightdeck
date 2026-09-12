"use client";

import React, { useState, useEffect } from "react";

export default function StorageHUDBackground() {
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const { innerWidth, innerHeight } = window;
      const x = (e.clientX / innerWidth - 0.5) * 24;
      const y = (e.clientY / innerHeight - 0.5) * 16;
      setMousePos({ x, y });
    };

    window.addEventListener("mousemove", handleMouseMove, { passive: true });
    return () => window.removeEventListener("mousemove", handleMouseMove);
  }, []);

  return (
    <div className="absolute inset-0 w-full h-full pointer-events-none overflow-hidden select-none flex items-center justify-center">
      {/* 1. Deep Emerald Stratosphere Wash (100% Full Width Edge-to-Edge) */}
      <div
        className="absolute w-[140vw] min-w-[1400px] h-[95vh] rounded-full opacity-55"
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, #064e3b 0%, #022c22 50%, transparent 75%)",
          filter: "blur(110px)",
        }}
      />

      <div
        className="absolute w-[80vw] min-w-[900px] h-[55vh] rounded-full opacity-40"
        style={{
          background:
            "radial-gradient(ellipse at center, #10b981 0%, #59d499 40%, transparent 70%)",
          filter: "blur(95px)",
          transform: `translate(${mousePos.x * 0.4}px, ${mousePos.y * 0.4}px)`,
          transition: "transform 0.2s ease-out",
        }}
      />

      {/* 2. Parallax APFS Sector Radar Geometry (100% Full Width Edge-to-Edge) */}
      <div
        className="absolute inset-0 w-full h-full flex items-center justify-center transition-transform duration-300 ease-out"
        style={{
          transform: `translate(${mousePos.x}px, ${mousePos.y}px)`,
        }}
      >
        <svg
          viewBox="0 0 1400 650"
          preserveAspectRatio="xMidYMid slice"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          className="w-full h-full opacity-80"
        >
          <defs>
            {/* Emerald Radar Laser Gradient */}
            <linearGradient id="emeraldLaser" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#10b981" stopOpacity="0" />
              <stop offset="30%" stopColor="#59d499" stopOpacity="0.5" />
              <stop offset="50%" stopColor="#10b981" stopOpacity="0.9" />
              <stop offset="70%" stopColor="#59d499" stopOpacity="0.5" />
              <stop offset="100%" stopColor="#10b981" stopOpacity="0" />
            </linearGradient>

            <radialGradient id="emeraldRadarSweep" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#59d499" stopOpacity="0.3" />
              <stop offset="70%" stopColor="#10b981" stopOpacity="0.08" />
              <stop offset="100%" stopColor="#10b981" stopOpacity="0" />
            </radialGradient>
          </defs>

          {/* Central Radar Sonar System */}
          <g transform="translate(700, 320)">
            {/* Range Sonar Rings */}
            <circle cx="0" cy="0" r="100" stroke="#10b981" strokeWidth="1" strokeDasharray="4 6" opacity="0.4" />
            <circle cx="0" cy="0" r="190" stroke="#59d499" strokeWidth="0.8" strokeDasharray="8 8" opacity="0.3" />
            <circle cx="0" cy="0" r="280" stroke="#10b981" strokeWidth="0.6" strokeDasharray="3 9" opacity="0.25" />

            {/* Rotating Radar Sweep Arm */}
            <g className="animate-spin" style={{ animationDuration: "10s" }}>
              <line x1="0" y1="0" x2="280" y2="0" stroke="url(#emeraldLaser)" strokeWidth="2" />
              <path d="M 0 0 L 280 0 A 280 280 0 0 1 242 140 Z" fill="url(#emeraldRadarSweep)" opacity="0.4" />
            </g>

            {/* Sector Cluster Radar Blips */}
            <circle cx="120" cy="-70" r="4" fill="#59d499" className="animate-ping" style={{ animationDuration: "2.5s" }} />
            <circle cx="120" cy="-70" r="3" fill="#59d499" />
            
            <circle cx="-160" cy="90" r="4" fill="#ff6363" className="animate-ping" style={{ animationDuration: "3s" }} />
            <circle cx="-160" cy="90" r="3" fill="#ff6363" />

            <circle cx="80" cy="180" r="3" fill="#59d499" />
            <circle cx="-90" cy="-120" r="3" fill="#59d499" />

            {/* Crosshair Axes */}
            <line x1="-300" y1="0" x2="300" y2="0" stroke="#10b981" strokeWidth="0.8" opacity="0.3" strokeDasharray="4 8" />
            <line x1="0" y1="-260" x2="0" y2="260" stroke="#10b981" strokeWidth="0.8" opacity="0.3" strokeDasharray="4 8" />
          </g>

          {/* APFS Sector Telemetry Callouts */}
          <g fill="#9c9c9d" fontSize="9" fontFamily="monospace" letterSpacing="0.1em" opacity="0.65">
            <text x="840" y="240" fill="#59d499">XCODE_DERIVED: 42.1 GB [SAFE]</text>
            <text x="500" y="420" fill="#ff6363">SPM_BUILD_TREE: 6.8 GB [CRUFT]</text>
            <text x="800" y="520" fill="#59d499">NODE_MODULES: 4.8 GB</text>
            <text x="140" y="140" fill="#10b981">RADAR_TARGET: /DEV/DISK1S1</text>
            <text x="140" y="160">CONTAINER: APFS_FAST_CLONE</text>
            <text x="1080" y="140" fill="#10b981">RECLAIM_POTENTIAL: 53.7 GB</text>
            <text x="1080" y="160">SAFETY_INDEX: 100% REGEN</text>
          </g>

          {/* Cyber Edge Corner Reticles */}
          <path d="M 120 120 L 80 120 L 80 160" stroke="#10b981" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1280 120 L 1320 120 L 1320 160" stroke="#10b981" strokeWidth="1.5" opacity="0.5" />
          <path d="M 80 500 L 80 540 L 120 540" stroke="#10b981" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1320 500 L 1320 540 L 1280 540" stroke="#10b981" strokeWidth="1.5" opacity="0.5" />
        </svg>
      </div>

      {/* 3. Cybernetic Fine Dot Grid Overlay */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage:
            "radial-gradient(rgba(16, 185, 129, 0.35) 1px, transparent 1px)",
          backgroundSize: "36px 36px",
          maskImage:
            "radial-gradient(ellipse at 50% 50%, black 40%, transparent 85%)",
        }}
      />

      {/* 4. Film Grain / Analogue Cockpit Sensor Texture */}
      <div
        className="absolute inset-0 opacity-15 mix-blend-overlay pointer-events-none"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
        }}
      />

      {/* 5. Soft Canvas Fade to Edge */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at 50% 50%, transparent 60%, rgba(4,5,6,0.3) 85%, rgba(4,5,6,0.7) 100%)",
        }}
      />

      {/* 6. Bottom Gradient Transition */}
      <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-[#040506] via-[#040506]/80 to-transparent" />
    </div>
  );
}
