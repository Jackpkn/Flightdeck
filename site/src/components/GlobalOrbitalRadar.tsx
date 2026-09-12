"use client";

import React, { useEffect, useRef, useState } from "react";

export default function GlobalOrbitalRadar() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animationFrameId: number;
    let angleY = 0;
    let scanAngle = 0;
    let targetTiltX = 0.35; // default 20 deg tilt
    let targetTiltY = 0;
    let currentTiltX = targetTiltX;
    let currentTiltY = 0;

    // Satellites / telemetry nodes orbiting the globe
    const numNodes = 28;
    const nodes = Array.from({ length: numNodes }, (_, i) => ({
      lat: (Math.random() - 0.5) * Math.PI * 0.85,
      lon: (i / numNodes) * Math.PI * 2,
      orbitSpeed: 0.002 + Math.random() * 0.003,
      size: i % 4 === 0 ? 2.5 : 1.5,
      isCore: i % 6 === 0,
      pulse: Math.random() * Math.PI * 2,
    }));

    const handleResize = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.scale(dpr, dpr);
    };

    handleResize();
    window.addEventListener("resize", handleResize);

    const handleMouseMove = (e: MouseEvent) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width - 0.5;
      const y = (e.clientY - rect.top) / rect.height - 0.5;
      targetTiltY = x * 0.4;
      targetTiltX = 0.35 + y * 0.3;
    };

    window.addEventListener("mousemove", handleMouseMove, { passive: true });

    let isVisible = true;
    const observer = new IntersectionObserver(
      ([entry]) => {
        isVisible = entry.isIntersecting;
      },
      { threshold: 0.1 }
    );
    if (containerRef.current) observer.observe(containerRef.current);

    // 3D Point Projection Helper
    const project = (
      lat: number,
      lon: number,
      radius: number,
      cx: number,
      cy: number,
      tiltX: number,
      rotY: number
    ) => {
      // Spherical to 3D Cartesian
      const x0 = radius * Math.cos(lat) * Math.sin(lon + rotY);
      const y0 = radius * Math.sin(lat);
      const z0 = radius * Math.cos(lat) * Math.cos(lon + rotY);

      // Rotate around X axis (tilt)
      const cosT = Math.cos(tiltX);
      const sinT = Math.sin(tiltX);
      const y1 = y0 * cosT - z0 * sinT;
      const z1 = y0 * sinT + z0 * cosT;

      // Perspective projection
      const perspective = 700 / (700 + z1);
      return {
        x: cx + x0 * perspective,
        y: cy + y1 * perspective,
        z: z1,
        visible: z1 > -radius * 0.1, // front-facing hemisphere test
        scale: perspective,
      };
    };

    const render = () => {
      if (!isVisible) {
        animationFrameId = requestAnimationFrame(render);
        return;
      }

      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      ctx.clearRect(0, 0, width, height);

      const cx = width / 2;
      const cy = height * 0.44;
      const radius = Math.min(width * 0.42, height * 0.38, 480);

      // Smooth mouse tilt interpolation
      currentTiltX += (targetTiltX - currentTiltX) * 0.05;
      currentTiltY += (targetTiltY - currentTiltY) * 0.05;

      angleY += 0.0035;
      scanAngle += 0.02;

      // ── 1. Atmosphere Radial Glow Behind the Globe ──
      const glowGrad = ctx.createRadialGradient(cx, cy, radius * 0.2, cx, cy, radius * 1.4);
      glowGrad.addColorStop(0, "rgba(20, 60, 160, 0.32)");
      glowGrad.addColorStop(0.45, "rgba(255, 99, 99, 0.12)");
      glowGrad.addColorStop(0.75, "rgba(56, 189, 248, 0.06)");
      glowGrad.addColorStop(1, "transparent");

      ctx.fillStyle = glowGrad;
      ctx.beginPath();
      ctx.arc(cx, cy, radius * 1.4, 0, Math.PI * 2);
      ctx.fill();

      // ── 2. Latitude Circles (Parallels) ──
      const latitudes = [-60, -40, -20, 0, 20, 40, 60];
      latitudes.forEach((deg) => {
        const lat = (deg * Math.PI) / 180;
        const isEquator = deg === 0;

        ctx.beginPath();
        let first = true;
        const steps = 64;
        for (let j = 0; j <= steps; j++) {
          const lon = (j / steps) * Math.PI * 2;
          const p = project(lat, lon, radius, cx, cy, currentTiltX, angleY + currentTiltY);

          // Render back hemisphere fainter
          if (p.z <= 0) {
            ctx.strokeStyle = "rgba(255, 255, 255, 0.035)";
          } else {
            ctx.strokeStyle = isEquator
              ? "rgba(255, 99, 99, 0.55)"
              : "rgba(56, 189, 248, 0.22)";
          }

          if (first) {
            ctx.moveTo(p.x, p.y);
            first = false;
          } else {
            ctx.lineTo(p.x, p.y);
          }
        }
        ctx.lineWidth = isEquator ? 1.6 : 0.9;
        if (!isEquator) ctx.setLineDash([4, 6]);
        else ctx.setLineDash([]);
        ctx.stroke();
      });

      // ── 3. Longitude Meridians (Great Circles) ──
      const numMeridians = 12;
      for (let i = 0; i < numMeridians; i++) {
        const baseLon = (i / numMeridians) * Math.PI * 2;
        ctx.beginPath();
        let first = true;
        const steps = 48;
        for (let j = 0; j <= steps; j++) {
          const lat = -Math.PI / 2 + (j / steps) * Math.PI;
          const p = project(lat, baseLon, radius, cx, cy, currentTiltX, angleY + currentTiltY);

          if (first) {
            ctx.moveTo(p.x, p.y);
            first = false;
          } else {
            ctx.lineTo(p.x, p.y);
          }
        }
        ctx.lineWidth = 0.8;
        ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
        ctx.setLineDash([4, 8]);
        ctx.stroke();
      }
      ctx.setLineDash([]);

      // ── 4. Concentric Circular Radar Range Rings ──
      const rangeMultipliers = [0.55, 0.85, 1.15, 1.35];
      rangeMultipliers.forEach((m, idx) => {
        ctx.beginPath();
        ctx.arc(cx, cy, radius * m, 0, Math.PI * 2);
        ctx.strokeStyle = idx === 3 ? "rgba(255, 99, 99, 0.2)" : "rgba(255, 255, 255, 0.05)";
        ctx.lineWidth = 1;
        if (idx % 2 === 1) ctx.setLineDash([2, 6]);
        else ctx.setLineDash([]);
        ctx.stroke();
      });
      ctx.setLineDash([]);

      // ── 5. Outer Orbital Telemetry Ring with Degree Ticks & Sweeping Radar Fan ──
      ctx.save();
      ctx.translate(cx, cy);

      // Sweeping radar fan/sector (35 deg trailing glow)
      const fanAngle = 0.6; // ~34 degrees
      const fanGrad = ctx.createRadialGradient(0, 0, radius * 0.1, 0, 0, radius * 1.35);
      fanGrad.addColorStop(0, "rgba(255, 99, 99, 0.25)");
      fanGrad.addColorStop(0.7, "rgba(56, 189, 248, 0.12)");
      fanGrad.addColorStop(1, "transparent");

      ctx.fillStyle = fanGrad;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, radius * 1.35, scanAngle - fanAngle, scanAngle);
      ctx.closePath();
      ctx.fill();

      // Sharp radar leading beam
      const sweepX = Math.cos(scanAngle) * radius * 1.35;
      const sweepY = Math.sin(scanAngle) * radius * 1.35;
      const sweepGrad = ctx.createLinearGradient(0, 0, sweepX, sweepY);
      sweepGrad.addColorStop(0, "rgba(255, 99, 99, 0.9)");
      sweepGrad.addColorStop(0.7, "rgba(56, 189, 248, 0.6)");
      sweepGrad.addColorStop(1, "transparent");

      ctx.strokeStyle = sweepGrad;
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(sweepX, sweepY);
      ctx.stroke();

      // Outer compass ring with degree tick marks
      ctx.strokeStyle = "rgba(255, 255, 255, 0.1)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(0, 0, radius * 1.35, 0, Math.PI * 2);
      ctx.stroke();

      for (let d = 0; d < 360; d += 15) {
        const rad = (d * Math.PI) / 180;
        const r1 = radius * 1.35;
        const isCardinal = d % 90 === 0;
        const isMajor = d % 45 === 0;
        const r2 = r1 - (isCardinal ? 10 : isMajor ? 6 : 3);
        ctx.strokeStyle = isCardinal
          ? "rgba(255, 99, 99, 0.7)"
          : isMajor
          ? "rgba(56, 189, 248, 0.4)"
          : "rgba(255, 255, 255, 0.15)";
        ctx.beginPath();
        ctx.moveTo(Math.cos(rad) * r1, Math.sin(rad) * r1);
        ctx.lineTo(Math.cos(rad) * r2, Math.sin(rad) * r2);
        ctx.stroke();
      }

      ctx.restore();

      // ── 5. Orbiting Telemetry Nodes & Inter-Node Constellation Links ──
      const projectedNodes = nodes.map((node) => {
        node.lon += node.orbitSpeed;
        node.pulse += 0.05;
        const p = project(
          node.lat,
          node.lon,
          radius * 1.05,
          cx,
          cy,
          currentTiltX,
          angleY + currentTiltY
        );
        return { ...node, ...p };
      });

      // Draw links between nearby nodes on front hemisphere
      ctx.strokeStyle = "rgba(56, 189, 248, 0.15)";
      ctx.lineWidth = 0.8;
      for (let i = 0; i < projectedNodes.length; i++) {
        if (projectedNodes[i].z < 0) continue;
        for (let j = i + 1; j < projectedNodes.length; j++) {
          if (projectedNodes[j].z < 0) continue;
          const dx = projectedNodes[i].x - projectedNodes[j].x;
          const dy = projectedNodes[i].y - projectedNodes[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < 85) {
            ctx.beginPath();
            ctx.moveTo(projectedNodes[i].x, projectedNodes[i].y);
            ctx.lineTo(projectedNodes[j].x, projectedNodes[j].y);
            ctx.stroke();
          }
        }
      }

      // Draw node blips
      projectedNodes.forEach((node) => {
        if (node.z < -radius * 0.2) return; // culling deep back
        const alpha = Math.max(0.1, (node.z + radius) / (radius * 2));
        const pulseScale = 1 + Math.sin(node.pulse) * 0.3;

        if (node.isCore) {
          // Coral pulsating hub node
          ctx.fillStyle = `rgba(255, 99, 99, ${alpha * 0.9})`;
          ctx.beginPath();
          ctx.arc(node.x, node.y, node.size * pulseScale * node.scale, 0, Math.PI * 2);
          ctx.fill();

          // Outer pulse ring
          ctx.strokeStyle = `rgba(255, 99, 99, ${alpha * 0.4})`;
          ctx.lineWidth = 0.8;
          ctx.beginPath();
          ctx.arc(node.x, node.y, node.size * 3 * pulseScale, 0, Math.PI * 2);
          ctx.stroke();
        } else {
          // Cyan telemetry node
          ctx.fillStyle = `rgba(56, 189, 248, ${alpha * 0.8})`;
          ctx.beginPath();
          ctx.arc(node.x, node.y, node.size * node.scale, 0, Math.PI * 2);
          ctx.fill();
        }
      });

      animationFrameId = requestAnimationFrame(render);
    };

    animationFrameId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animationFrameId);
      window.removeEventListener("resize", handleResize);
      window.removeEventListener("mousemove", handleMouseMove);
      observer.disconnect();
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className="absolute inset-0 pointer-events-none overflow-hidden select-none flex items-center justify-center"
    >
      <canvas ref={canvasRef} className="w-full h-full" />
    </div>
  );
}
