"use client";

import React, { useEffect, useRef, useState } from "react";

export default function HoloRadar() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [mouseOffset, setMouseOffset] = useState({ x: 0, y: 0 });
  const [targetOffset, setTargetOffset] = useState({ x: 0, y: 0 });
  const [activeMetrics, setActiveMetrics] = useState({
    fps: 60,
    nodes: 84,
    latency: "0.4ms",
  });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animationFrameId: number;
    let angle = 0;
    let currentX = 0;
    let currentY = 0;

    // High precision spherical coordinate nodes
    const numParticles = 84;
    const particles = Array.from({ length: numParticles }, (_, i) => {
      const u = (i / numParticles) * 2 - 1;
      const theta = i * 2.39996; // Golden spiral angle
      const r = Math.sqrt(Math.max(0, 1 - u * u));
      return {
        x: r * Math.cos(theta),
        y: u,
        z: r * Math.sin(theta),
        baseSize: i % 7 === 0 ? 2.2 : 1.2,
        isAnchor: i % 11 === 0,
      };
    });

    const handleResize = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.scale(dpr, dpr);
    };

    handleResize();
    window.addEventListener("resize", handleResize);

    const render = () => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      ctx.clearRect(0, 0, width, height);

      const cx = width / 2;
      const cy = height / 2;
      const radius = Math.min(width, height) * 0.36;

      // Smooth mouse parallax damping
      currentX += (targetOffset.x - currentX) * 0.06;
      currentY += (targetOffset.y - currentY) * 0.06;

      angle += 0.006;

      // ── Outer Telemetry HUD Compass Ring ──
      ctx.save();
      ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(cx, cy, radius * 1.2, 0, Math.PI * 2);
      ctx.stroke();

      // Cardinal tick marks
      for (let deg = 0; deg < 360; deg += 30) {
        const rad = (deg * Math.PI) / 180;
        const tickLength = deg % 90 === 0 ? 8 : 4;
        const r1 = radius * 1.2;
        const r2 = r1 - tickLength;
        ctx.strokeStyle = deg % 90 === 0 ? "rgba(255, 99, 99, 0.5)" : "rgba(255, 255, 255, 0.12)";
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(rad) * r1, cy + Math.sin(rad) * r1);
        ctx.lineTo(cx + Math.cos(rad) * r2, cy + Math.sin(rad) * r2);
        ctx.stroke();
      }

      // Inner faint dashed alignment circle
      ctx.strokeStyle = "rgba(99, 161, 255, 0.16)";
      ctx.setLineDash([3, 6]);
      ctx.beginPath();
      ctx.arc(cx, cy, radius * 1.05, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();

      // ── Subtle Laser Sweep Beam ──
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(angle);
      const sweep = ctx.createRadialGradient(0, 0, 0, 0, 0, radius);
      sweep.addColorStop(0, "rgba(255, 99, 99, 0.28)");
      sweep.addColorStop(0.75, "rgba(255, 99, 99, 0.04)");
      sweep.addColorStop(1, "transparent");

      ctx.fillStyle = sweep;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, radius, 0, Math.PI / 4);
      ctx.closePath();
      ctx.fill();

      // Sharp hairline sweep ray
      ctx.strokeStyle = "rgba(255, 99, 99, 0.55)";
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(radius, 0);
      ctx.stroke();
      ctx.restore();

      // ── Spherical Wireframe Meridians ──
      const rotY = angle + currentX * 0.8;
      const rotX = currentY * 0.8;

      const cosY = Math.cos(rotY);
      const sinY = Math.sin(rotY);
      const cosX = Math.cos(rotX);
      const sinX = Math.sin(rotX);

      ctx.save();
      // Latitude parallels
      [-0.6, -0.3, 0, 0.3, 0.6].forEach((lat) => {
        const rLat = radius * Math.sqrt(Math.max(0, 1 - lat * lat));
        const yLat = cy + (lat * cosX) * radius;
        ctx.strokeStyle = lat === 0 ? "rgba(99, 161, 255, 0.25)" : "rgba(255, 255, 255, 0.06)";
        ctx.lineWidth = lat === 0 ? 1.2 : 0.8;
        ctx.beginPath();
        ctx.ellipse(cx, yLat, rLat, rLat * 0.28 * Math.abs(cosX), 0, 0, Math.PI * 2);
        ctx.stroke();
      });

      // Longitudinal rotating ellipse
      ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.ellipse(cx, cy, Math.abs(cosY) * radius, radius, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();

      // ── 3D Particles with Perspective & Depth Sorting ──
      const sortedParticles = particles
        .map((p) => {
          // Rotate Y
          const x1 = p.x * cosY - p.z * sinY;
          const z1 = p.x * sinY + p.z * cosY;
          // Rotate X
          const y2 = p.y * cosX - z1 * sinX;
          const z2 = p.y * sinX + z1 * cosX;

          return {
            x: x1,
            y: y2,
            z: z2,
            baseSize: p.baseSize,
            isAnchor: p.isAnchor,
          };
        })
        .sort((a, b) => a.z - b.z);

      sortedParticles.forEach((p) => {
        const perspective = (p.z + 1.8) / 2.8;
        const screenX = cx + p.x * radius;
        const screenY = cy + p.y * radius;
        const alpha = Math.max(0.08, (p.z + 1.2) / 2.4);

        ctx.fillStyle = p.isAnchor ? "#ff6363" : "#63a1ff";
        ctx.globalAlpha = alpha;

        ctx.beginPath();
        ctx.arc(screenX, screenY, p.baseSize * perspective, 0, Math.PI * 2);
        ctx.fill();

        // Delicate glow on anchor telemetry beacons
        if (p.isAnchor && p.z > 0) {
          ctx.strokeStyle = "rgba(255, 99, 99, 0.4)";
          ctx.lineWidth = 0.8;
          ctx.beginPath();
          ctx.arc(screenX, screenY, p.baseSize * perspective + 4, 0, Math.PI * 2);
          ctx.stroke();
        }
      });

      ctx.globalAlpha = 1.0;

      // ── Delicate Crosshair Overlay ──
      ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(cx - radius * 1.3, cy);
      ctx.lineTo(cx - radius * 0.2, cy);
      ctx.moveTo(cx + radius * 0.2, cy);
      ctx.lineTo(cx + radius * 1.3, cy);

      ctx.moveTo(cx, cy - radius * 1.3);
      ctx.lineTo(cx, cy - radius * 0.2);
      ctx.moveTo(cx, cy + radius * 0.2);
      ctx.lineTo(cx, cy + radius * 1.3);
      ctx.stroke();

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      window.removeEventListener("resize", handleResize);
      cancelAnimationFrame(animationFrameId);
    };
  }, [targetOffset]);

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width - 0.5;
    const y = (e.clientY - rect.top) / rect.height - 0.5;
    setTargetOffset({ x, y });
  };

  const handleMouseLeave = () => {
    setTargetOffset({ x: 0, y: 0 });
  };

  return (
    <div
      ref={containerRef}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      className="relative w-full max-w-[440px] aspect-square mx-auto flex items-center justify-center select-none group"
    >
      {/* Outer tactile cockpit bezel */}
      <div
        className="absolute inset-0 rounded-full border border-[#363739]/80 bg-[#07080a]/60 backdrop-blur-md"
        style={{
          boxShadow:
            "rgba(255, 255, 255, 0.05) 0px 1px 0px 0px inset, rgba(255, 255, 255, 0.15) 0px 0px 0px 1px, rgba(0, 0, 0, 0.7) 0px 20px 50px 0px",
        }}
      />

      {/* Interactive 60fps Radar Canvas */}
      <canvas ref={canvasRef} className="relative z-10 w-full h-full" />

      {/* Technical HUD micro-labels in Geist Mono */}
      <div className="absolute top-4 left-4 z-20 px-2.5 py-1 rounded-[6px] bg-[#111214]/90 border border-white/5 text-[10px] font-mono text-[#9c9c9d] flex items-center gap-1.5 shadow-[0_4px_12px_rgba(0,0,0,0.5)]">
        <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] animate-pulse" />
        <span>MACH_PORT::ACTIVE</span>
      </div>

      <div className="absolute top-4 right-4 z-20 px-2 py-1 rounded-[6px] bg-[#111214]/90 border border-white/5 text-[10px] font-mono text-[#6a6b6c] shadow-[0_4px_12px_rgba(0,0,0,0.5)]">
        POLL 1000Hz
      </div>

      <div className="absolute bottom-4 left-4 z-20 px-2.5 py-1 rounded-[6px] bg-[#111214]/90 border border-white/5 text-[10px] font-mono text-[#6a6b6c] shadow-[0_4px_12px_rgba(0,0,0,0.5)]">
        SESSION 41d7a11b
      </div>

      <div className="absolute bottom-4 right-4 z-20 px-2.5 py-1 rounded-[6px] bg-[#111214]/90 border border-white/5 text-[10px] font-mono text-[#59d499] flex items-center gap-1 shadow-[0_4px_12px_rgba(0,0,0,0.5)]">
        <span>●</span>
        <span>ZERO CLOUD</span>
      </div>
    </div>
  );
}
