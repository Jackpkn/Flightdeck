"use client";

import React, { useState, useEffect } from "react";

export default function CockpitHUDBackground() {
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const { innerWidth, innerHeight } = window;
      const x = (e.clientX / innerWidth - 0.5) * 30; // -15px to +15px
      const y = (e.clientY / innerHeight - 0.5) * 20; // -10px to +10px
      setMousePos({ x, y });
    };

    window.addEventListener("mousemove", handleMouseMove, { passive: true });
    return () => window.removeEventListener("mousemove", handleMouseMove);
  }, []);

  return (
    <div className="absolute inset-0 pointer-events-none overflow-hidden select-none flex items-center justify-center pt-16 md:pt-24">
      {/* 1. Deep Atmospheric Stratosphere Wash */}
      <div
        className="absolute w-[1200px] h-[700px] rounded-full opacity-50"
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, #0b2259 0%, #030b1e 55%, transparent 75%)",
          filter: "blur(90px)",
        }}
      />

      {/* 2. Core Coral Neon Reactor Underglow */}
      <div
        className="absolute w-[650px] h-[380px] rounded-full opacity-35"
        style={{
          background:
            "radial-gradient(ellipse at center, #ff6363 0%, #a81c2e 40%, transparent 70%)",
          filter: "blur(80px)",
          transform: `translate(${mousePos.x * 0.5}px, ${mousePos.y * 0.5}px)`,
          transition: "transform 0.2s ease-out",
        }}
      />

      {/* 3. Parallax HUD Avionics Geometry (Contained HUD Viewport) */}
      <div
        className="relative w-full max-w-[1500px] h-[800px] flex items-center justify-center transition-transform duration-300 ease-out"
        style={{
          transform: `translate(${mousePos.x}px, ${mousePos.y}px)`,
        }}
      >
        <svg
          viewBox="0 0 1400 750"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          className="w-full h-full opacity-75"
        >
          <defs>
            {/* Coral Laser Core Gradient */}
            <linearGradient id="hudCoralGlow" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#ff6363" stopOpacity="0" />
              <stop offset="30%" stopColor="#ff6363" stopOpacity="0.5" />
              <stop offset="50%" stopColor="#ff6363" stopOpacity="0.95" />
              <stop offset="70%" stopColor="#ff6363" stopOpacity="0.5" />
              <stop offset="100%" stopColor="#ff6363" stopOpacity="0" />
            </linearGradient>

            {/* Cyan Mach Atmosphere Gradient */}
            <linearGradient id="hudCyanGlow" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#38bdf8" stopOpacity="0" />
              <stop offset="25%" stopColor="#38bdf8" stopOpacity="0.35" />
              <stop offset="50%" stopColor="#38bdf8" stopOpacity="0.8" />
              <stop offset="75%" stopColor="#38bdf8" stopOpacity="0.35" />
              <stop offset="100%" stopColor="#38bdf8" stopOpacity="0" />
            </linearGradient>

            {/* Radar Sweep Radial Gradient */}
            <radialGradient id="radarSweep" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#ff6363" stopOpacity="0.2" />
              <stop offset="60%" stopColor="#38bdf8" stopOpacity="0.08" />
              <stop offset="100%" stopColor="#38bdf8" stopOpacity="0" />
            </radialGradient>

            {/* Perspective Flight Corridor Gradient */}
            <linearGradient id="flightCorridor" x1="50%" y1="100%" x2="50%" y2="0%">
              <stop offset="0%" stopColor="#38bdf8" stopOpacity="0.35" />
              <stop offset="50%" stopColor="#ff6363" stopOpacity="0.15" />
              <stop offset="100%" stopColor="#ff6363" stopOpacity="0" />
            </linearGradient>
          </defs>

          {/* ── Converging Forward Flight Corridor (Vanishing smoothly behind Hero) ── */}
          <g stroke="url(#flightCorridor)" strokeWidth="1" opacity="0.45">
            <line x1="80" y1="750" x2="630" y2="375" strokeDasharray="6 12" />
            <line x1="260" y1="750" x2="660" y2="375" strokeDasharray="4 8" />
            <line x1="480" y1="750" x2="685" y2="375" />
            <line x1="920" y1="750" x2="715" y2="375" />
            <line x1="1140" y1="750" x2="740" y2="375" strokeDasharray="4 8" />
            <line x1="1320" y1="750" x2="770" y2="375" strokeDasharray="6 12" />
          </g>

          {/* ── Stratospheric Curved Horizon Vector ── */}
          <ellipse
            cx="700"
            cy="375"
            rx="660"
            ry="310"
            stroke="url(#hudCyanGlow)"
            strokeWidth="1.2"
            strokeDasharray="14 10 3 10"
            opacity="0.4"
          />

          {/* ── Concentric Avionics HUD Geometry ── */}
          {/* Outer Ring 1 - Massive Canopy (r=560) */}
          <circle
            cx="700"
            cy="375"
            r="560"
            stroke="rgba(255, 255, 255, 0.06)"
            strokeWidth="1"
            strokeDasharray="4 20"
          />

          {/* Outer Ring 2 - Rotating Heading Ring (r=460) with Laser Arc */}
          <circle
            cx="700"
            cy="375"
            r="460"
            stroke="rgba(56, 189, 248, 0.15)"
            strokeWidth="1"
            strokeDasharray="2 10"
          />
          <circle
            cx="700"
            cy="375"
            r="460"
            stroke="url(#hudCoralGlow)"
            strokeWidth="1.5"
            strokeDasharray="140 400"
            className="animate-spin"
            style={{ transformOrigin: "700px 375px", animationDuration: "35s" }}
          />

          {/* Ring 3 - Supersonic Sonic Shockwave (Expanding Breathing Pulse r=380) */}
          <circle
            cx="700"
            cy="375"
            r="380"
            stroke="rgba(255, 99, 99, 0.25)"
            strokeWidth="1"
            strokeDasharray="6 14"
          />
          <circle
            cx="700"
            cy="375"
            r="380"
            stroke="rgba(255, 99, 99, 0.2)"
            strokeWidth="1.5"
            className="animate-ping"
            style={{
              transformOrigin: "700px 375px",
              animationDuration: "8s",
              opacity: 0.12,
            }}
          />

          {/* Ring 4 - Inner Precision Ring (r=260) */}
          <circle
            cx="700"
            cy="375"
            r="260"
            stroke="rgba(255, 255, 255, 0.08)"
            strokeWidth="1"
            strokeDasharray="3 12"
          />

          {/* ── Delicate Horizon Alignment Calibrations (Wide Periphery) ── */}
          <g stroke="rgba(255, 99, 99, 0.35)" strokeWidth="1.2">
            <line x1="160" y1="375" x2="250" y2="375" />
            <line x1="160" y1="370" x2="160" y2="380" />
            <line x1="1150" y1="375" x2="1240" y2="375" />
            <line x1="1240" y1="370" x2="1240" y2="380" />
          </g>

          {/* ── Four Corner Cockpit Reticles [ + ] ── */}
          <g stroke="rgba(56, 189, 248, 0.3)" strokeWidth="1">
            {/* Top Left */}
            <line x1="80" y1="90" x2="110" y2="90" />
            <line x1="80" y1="90" x2="80" y2="120" />
            {/* Top Right */}
            <line x1="1320" y1="90" x2="1290" y2="90" />
            <line x1="1320" y1="90" x2="1320" y2="120" />
            {/* Bottom Left */}
            <line x1="80" y1="660" x2="110" y2="660" />
            <line x1="80" y1="660" x2="80" y2="630" />
            {/* Bottom Right */}
            <line x1="1320" y1="660" x2="1290" y2="660" />
            <line x1="1320" y1="660" x2="1320" y2="630" />
          </g>

          {/* ── Outer Cardinal Compass Points ── */}
          <g fill="rgba(255, 99, 99, 0.45)" fontSize="10" fontFamily="monospace" fontWeight="600" letterSpacing="0.1em">
            <text x="696" y="35">N 000°</text>
            <text x="696" y="730">S 180°</text>
            <text x="50" y="379">270° W</text>
            <text x="1310" y="379">E 090°</text>
          </g>
        </svg>
      </div>

      {/* 4. Cybernetic Fine Dot Grid Overlay */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage:
            "radial-gradient(rgba(255, 255, 255, 0.4) 1px, transparent 1px)",
          backgroundSize: "36px 36px",
          maskImage:
            "radial-gradient(ellipse at 50% 50%, black 40%, transparent 85%)",
        }}
      />

      {/* 5. Film Grain / Analogue Cockpit Sensor Texture */}
      <div
        className="absolute inset-0 opacity-15 mix-blend-overlay pointer-events-none"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
        }}
      />

      {/* 6. Soft Canvas Fade to Edge */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at 50% 50%, transparent 35%, #040506 75%)",
        }}
      />
    </div>
  );
}
