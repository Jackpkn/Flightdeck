"use client";

import React, { useState, useEffect } from "react";

export default function SystemHUDBackground() {
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
      {/* 1. Deep Cyan & Cobalt Blue Stratosphere Wash (100% Full Width Edge-to-Edge) */}
      <div
        className="absolute w-[140vw] min-w-[1400px] h-[95vh] rounded-full opacity-55"
        style={{
          background:
            "radial-gradient(ellipse at 50% 45%, #034b75 0%, #031c38 50%, transparent 75%)",
          filter: "blur(110px)",
        }}
      />

      <div
        className="absolute w-[80vw] min-w-[900px] h-[55vh] rounded-full opacity-40"
        style={{
          background:
            "radial-gradient(ellipse at center, #00f0ff 0%, #1e40af 50%, transparent 70%)",
          filter: "blur(95px)",
          transform: `translate(${mousePos.x * 0.4}px, ${mousePos.y * 0.4}px)`,
          transition: "transform 0.2s ease-out",
        }}
      />

      {/* 2. Parallax Mach Kernel Silicon Die & Frequency Oscilloscope (100% Full Width Edge-to-Edge) */}
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
            {/* Cyan Laser Core Gradient */}
            <linearGradient id="cyanLaser" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#00f0ff" stopOpacity="0" />
              <stop offset="25%" stopColor="#00f0ff" stopOpacity="0.4" />
              <stop offset="50%" stopColor="#38bdf8" stopOpacity="0.9" />
              <stop offset="75%" stopColor="#00f0ff" stopOpacity="0.4" />
              <stop offset="100%" stopColor="#00f0ff" stopOpacity="0" />
            </linearGradient>

            <linearGradient id="siliconGridGrad" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#00f0ff" stopOpacity="0.2" />
              <stop offset="100%" stopColor="#1e3a8a" stopOpacity="0.05" />
            </linearGradient>
          </defs>

          {/* Silicon M-Series Core Die Frame */}
          <rect
            x="420"
            y="140"
            width="560"
            height="360"
            rx="8"
            stroke="#00f0ff"
            strokeWidth="1.2"
            strokeDasharray="8 6"
            opacity="0.3"
            fill="url(#siliconGridGrad)"
          />

          {/* Central P-Core vs E-Core Cluster Partitions */}
          <line x1="700" y1="140" x2="700" y2="500" stroke="#38bdf8" strokeWidth="1" strokeDasharray="4 4" opacity="0.4" />
          <line x1="420" y1="320" x2="980" y2="320" stroke="#38bdf8" strokeWidth="1" strokeDasharray="4 4" opacity="0.4" />

          {/* Core Cluster Labels */}
          <g fill="#38bdf8" fontSize="10" fontFamily="monospace" letterSpacing="0.12em" opacity="0.7">
            <text x="440" y="170">CLUSTER 0: P-CORES (8x 3.8 GHz)</text>
            <text x="720" y="170">CLUSTER 1: E-CORES (8x 2.4 GHz)</text>
            <text x="440" y="480">HOST_CPU_LOAD_INFO: 1000Hz</text>
            <text x="720" y="480">ZERO-LAG POSIX SIGKILL</text>
          </g>

          {/* High-frequency 1000Hz Oscilloscope Sine & Pulse Waveforms */}
          <path
            d="M 100 320 Q 220 230, 340 320 T 560 320 T 700 240 T 840 400 T 980 320 T 1200 320 T 1300 320"
            stroke="url(#cyanLaser)"
            strokeWidth="2"
            fill="none"
          />
          <path
            d="M 120 320 Q 240 380, 360 320 T 600 320 T 700 370 T 820 280 T 960 320 T 1180 320 T 1280 320"
            stroke="#00f0ff"
            strokeWidth="1"
            strokeDasharray="4 4"
            opacity="0.5"
            fill="none"
          />

          {/* Silicon Bus Trace Lines with Connector Pads */}
          <g stroke="#00f0ff" strokeWidth="1" opacity="0.5">
            <path d="M 280 180 L 420 180" />
            <circle cx="280" cy="180" r="3" fill="#00f0ff" />

            <path d="M 240 240 L 420 240" />
            <circle cx="240" cy="240" r="3" fill="#00f0ff" />

            <path d="M 980 180 L 1120 180" />
            <circle cx="1120" cy="180" r="3" fill="#00f0ff" />

            <path d="M 980 240 L 1160 240" />
            <circle cx="1160" cy="240" r="3" fill="#00f0ff" />

            <path d="M 240 400 L 420 400" />
            <circle cx="240" cy="400" r="3" fill="#00f0ff" />

            <path d="M 980 400 L 1160 400" />
            <circle cx="1160" cy="400" r="3" fill="#00f0ff" />
          </g>

          {/* Animated Frequency Scan Reticle */}
          <g transform="translate(700, 320)">
            <circle cx="0" cy="0" r="45" stroke="#00f0ff" strokeWidth="1.2" strokeDasharray="6 4" opacity="0.6" className="animate-spin" style={{ animationDuration: "12s" }} />
            <circle cx="0" cy="0" r="85" stroke="#38bdf8" strokeWidth="0.75" strokeDasharray="3 6" opacity="0.3" className="animate-spin" style={{ animationDuration: "24s", animationDirection: "reverse" }} />
            <circle cx="0" cy="0" r="4" fill="#00f0ff" className="animate-ping" style={{ animationDuration: "2s" }} />
          </g>

          {/* Technical Telemetry Metadata Callouts */}
          <g fill="#9c9c9d" fontSize="9" fontFamily="monospace" letterSpacing="0.1em" opacity="0.6">
            <text x="140" y="140" fill="#00f0ff">SYSCTL: HW.PERFLEVEL0</text>
            <text x="140" y="160">FREQUENCY: 3840 MHz</text>
            <text x="1100" y="140" fill="#00f0ff">MACH_VM: ACTIVE</text>
            <text x="1100" y="160">COMPRESSED: 0.00 GB</text>
          </g>

          {/* Cyber Edge Corner Reticles */}
          <path d="M 120 120 L 80 120 L 80 160" stroke="#00f0ff" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1280 120 L 1320 120 L 1320 160" stroke="#00f0ff" strokeWidth="1.5" opacity="0.5" />
          <path d="M 80 500 L 80 540 L 120 540" stroke="#00f0ff" strokeWidth="1.5" opacity="0.5" />
          <path d="M 1320 500 L 1320 540 L 1280 540" stroke="#00f0ff" strokeWidth="1.5" opacity="0.5" />
        </svg>
      </div>

      {/* 3. Cybernetic Fine Dot Grid Overlay */}
      <div
        className="absolute inset-0 opacity-15 pointer-events-none"
        style={{
          backgroundImage:
            "radial-gradient(rgba(0, 240, 255, 0.35) 1px, transparent 1px)",
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
