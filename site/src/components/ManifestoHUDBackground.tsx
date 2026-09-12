"use client";

import React, { useState, useEffect } from "react";

export default function ManifestoHUDBackground() {
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
      {/* 1. Deep Amber & Gold Stratosphere Wash (100% Full Width Edge-to-Edge) */}
      <div
        className="absolute w-[140vw] min-w-[1400px] h-[95vh] rounded-full opacity-55"
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, #78350f 0%, #291804 50%, transparent 75%)",
          filter: "blur(110px)",
        }}
      />

      <div
        className="absolute w-[80vw] min-w-[900px] h-[55vh] rounded-full opacity-40"
        style={{
          background:
            "radial-gradient(ellipse at center, #f59e0b 0%, #eab308 40%, transparent 70%)",
          filter: "blur(95px)",
          transform: `translate(${mousePos.x * 0.4}px, ${mousePos.y * 0.4}px)`,
          transition: "transform 0.2s ease-out",
        }}
      />

      {/* 2. Parallax Integrity Matrix & Merkle Lattice (100% Full Width Edge-to-Edge) */}
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
            {/* Gold Integrity Core Gradient */}
            <linearGradient id="goldLaser" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#f59e0b" stopOpacity="0" />
              <stop offset="30%" stopColor="#f59e0b" stopOpacity="0.5" />
              <stop offset="50%" stopColor="#eab308" stopOpacity="0.9" />
              <stop offset="70%" stopColor="#f59e0b" stopOpacity="0.5" />
              <stop offset="100%" stopColor="#f59e0b" stopOpacity="0" />
            </linearGradient>

            <linearGradient id="merkleGrid" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#eab308" stopOpacity="0.25" />
              <stop offset="100%" stopColor="#59d499" stopOpacity="0.05" />
            </linearGradient>
          </defs>

          {/* Cryptographic Geometric Lattice */}
          <g stroke="#f59e0b" strokeWidth="0.8" strokeDasharray="3 7" opacity="0.25">
            <polygon points="700,100 860,190 860,370 700,460 540,370 540,190" />
            <polygon points="700,160 810,225 810,345 700,410 590,345 590,225" />
            <line x1="700" y1="100" x2="700" y2="460" />
            <line x1="540" y1="190" x2="860" y2="370" />
            <line x1="540" y1="370" x2="860" y2="190" />
          </g>

          {/* Central Integrity Seal Reticle */}
          <g transform="translate(700, 280)">
            <circle cx="0" cy="0" r="70" stroke="#f59e0b" strokeWidth="1.2" strokeDasharray="6 4" opacity="0.6" className="animate-spin" style={{ animationDuration: "16s" }} />
            <circle cx="0" cy="0" r="110" stroke="#59d499" strokeWidth="0.75" strokeDasharray="4 8" opacity="0.4" className="animate-spin" style={{ animationDuration: "28s", animationDirection: "reverse" }} />
            <polygon points="0,-25 21,12 -21,12" stroke="#eab308" strokeWidth="1.5" fill="none" opacity="0.7" />
            <circle cx="0" cy="0" r="4" fill="#59d499" className="animate-ping" style={{ animationDuration: "2.5s" }} />
          </g>

          {/* Horizontal Calibration Scale Line */}
          <line x1="160" y1="280" x2="1240" y2="280" stroke="url(#goldLaser)" strokeWidth="1.5" />

          {/* Cryptographic Ledger Callouts */}
          <g fill="#9c9c9d" fontSize="9" fontFamily="monospace" letterSpacing="0.1em" opacity="0.65">
            <text x="140" y="140" fill="#f59e0b">INTEGRITY_PRIMITIVE: DETERMINISTIC</text>
            <text x="140" y="160">CLOUD_DEPENDENCY: 0.00% (LOCAL ONLY)</text>
            <text x="1060" y="140" fill="#59d499">SQLITE_MONOTONIC: TRUE</text>
            <text x="1060" y="160">EXTRAPOLATION_POLICY: STRICT_REJECT</text>

            <text x="730" y="220" fill="#f59e0b">ZERO_INVENTIONS</text>
            <text x="590" y="380" fill="#59d499">PROVABLE_MEASUREMENT</text>
          </g>

          {/* Cyber Edge Corner Reticles */}
          <path d="M 120 120 L 80 120 L 80 160" stroke="#f59e0b" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1280 120 L 1320 120 L 1320 160" stroke="#f59e0b" strokeWidth="1.5" opacity="0.5" />
          <path d="M 80 460 L 80 500 L 120 500" stroke="#f59e0b" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1320 460 L 1320 500 L 1280 500" stroke="#f59e0b" strokeWidth="1.5" opacity="0.5" />
        </svg>
      </div>

      {/* 3. Cybernetic Fine Dot Grid Overlay */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage:
            "radial-gradient(rgba(245, 158, 11, 0.35) 1px, transparent 1px)",
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
