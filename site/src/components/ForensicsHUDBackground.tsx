"use client";

import React, { useState, useEffect } from "react";

export default function ForensicsHUDBackground() {
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
      {/* 1. Deep Violet & Claude Amber Nebula Wash (100% Full Width Edge-to-Edge) */}
      <div
        className="absolute w-[140vw] min-w-[1400px] h-[95vh] rounded-full opacity-55"
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, #4c1d95 0%, #1e1145 50%, transparent 75%)",
          filter: "blur(110px)",
        }}
      />

      <div
        className="absolute w-[80vw] min-w-[900px] h-[55vh] rounded-full opacity-40"
        style={{
          background:
            "radial-gradient(ellipse at center, #d97706 0%, #ff6363 45%, transparent 70%)",
          filter: "blur(95px)",
          transform: `translate(${mousePos.x * 0.4}px, ${mousePos.y * 0.4}px)`,
          transition: "transform 0.2s ease-out",
        }}
      />

      {/* 2. Parallax Forensics DAG & Token Flow Geometry (100% Full Width Edge-to-Edge) */}
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
          className="w-full h-full opacity-75"
        >
          <defs>
            {/* Violet-Amber Laser Gradient */}
            <linearGradient id="forensicsGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#8b5cf6" stopOpacity="0" />
              <stop offset="30%" stopColor="#8b5cf6" stopOpacity="0.6" />
              <stop offset="50%" stopColor="#f59e0b" stopOpacity="0.9" />
              <stop offset="70%" stopColor="#ff6363" stopOpacity="0.6" />
              <stop offset="100%" stopColor="#8b5cf6" stopOpacity="0" />
            </linearGradient>

            <linearGradient id="tokenStreamGrad" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#f59e0b" stopOpacity="0.8" />
              <stop offset="100%" stopColor="#8b5cf6" stopOpacity="0.1" />
            </linearGradient>
          </defs>

          {/* Background Digital Grid */}
          <g opacity="0.15" stroke="#8b5cf6" strokeWidth="0.75" strokeDasharray="3 8">
            <line x1="200" y1="50" x2="1200" y2="50" />
            <line x1="150" y1="180" x2="1250" y2="180" />
            <line x1="100" y1="320" x2="1300" y2="320" />
            <line x1="150" y1="460" x2="1250" y2="460" />
            <line x1="200" y1="580" x2="1200" y2="580" />

            <line x1="250" y1="50" x2="250" y2="580" />
            <line x1="500" y1="50" x2="500" y2="580" />
            <line x1="700" y1="50" x2="700" y2="580" />
            <line x1="900" y1="50" x2="900" y2="580" />
            <line x1="1150" y1="50" x2="1150" y2="580" />
          </g>

          {/* Git Branch DAG Curves */}
          <g stroke="url(#forensicsGradient)" strokeWidth="1.5" opacity="0.6">
            <path
              d="M 150 320 C 350 320, 450 200, 700 200 C 950 200, 1050 320, 1250 320"
              strokeDasharray="6 4"
              className="animate-[dash_20s_linear_infinite]"
            />
            <path
              d="M 250 320 C 400 320, 500 440, 700 440 C 900 440, 1000 320, 1150 320"
              strokeDasharray="4 6"
            />
            <line x1="100" y1="320" x2="1300" y2="320" stroke="#8b5cf6" strokeWidth="1" opacity="0.4" />
          </g>

          {/* Git Commit Nodes with Pulse */}
          <g fill="#07080a" stroke="#f59e0b" strokeWidth="1.5">
            <circle cx="450" cy="200" r="6" />
            <circle cx="450" cy="200" r="12" stroke="#f59e0b" strokeWidth="0.75" opacity="0.4" className="animate-ping" style={{ animationDuration: "3s" }} />

            <circle cx="700" cy="200" r="7" stroke="#ff6363" />
            <circle cx="950" cy="200" r="6" stroke="#8b5cf6" />

            <circle cx="500" cy="440" r="5" stroke="#8b5cf6" />
            <circle cx="700" cy="440" r="7" stroke="#f59e0b" />
            <circle cx="900" cy="440" r="5" stroke="#8b5cf6" />

            {/* Central Master Head Commit Node */}
            <circle cx="700" cy="320" r="10" stroke="#ff6363" strokeWidth="2" />
            <circle cx="700" cy="320" r="4" fill="#ff6363" />
            <circle cx="700" cy="320" r="22" stroke="#ff6363" strokeWidth="0.75" strokeDasharray="3 3" opacity="0.6" className="animate-spin" style={{ animationDuration: "14s" }} />
          </g>

          {/* Code & Token Forensics Hex Annotations */}
          <g fill="#9c9c9d" fontSize="9" fontFamily="monospace" letterSpacing="0.1em" opacity="0.65">
            <text x="715" y="305" fill="#ff6363">HEAD [9f8a2b] LIVE</text>
            <text x="465" y="195" fill="#f59e0b">CLAUDE_FORK: 142k TOKENS</text>
            <text x="965" y="195" fill="#8b5cf6">DIFF: +182 / -12 SURVIVING</text>
            <text x="715" y="455" fill="#f59e0b">SQLITE_LEDGER: $72.96</text>
            <text x="210" y="340">ORIGIN/MAIN</text>
            <text x="1160" y="340">SYNC_STATUS: MONOTONIC</text>
          </g>

          {/* Outer Cyber Corner Brackets */}
          <path d="M 120 140 L 90 140 L 90 170" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.6" />
          <path d="M 1280 140 L 1310 140 L 1310 170" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.6" />
          <path d="M 90 480 L 90 510 L 120 510" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.6" />
          <path d="M 1310 480 L 1310 510 L 1280 510" stroke="#8b5cf6" strokeWidth="1.5" opacity="0.6" />
        </svg>
      </div>

      {/* 3. Cybernetic Fine Dot Grid Overlay */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage:
            "radial-gradient(rgba(139, 92, 246, 0.4) 1px, transparent 1px)",
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
