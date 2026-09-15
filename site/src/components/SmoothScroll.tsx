"use client";

import { useEffect, useState } from "react";
import Lenis from "lenis";

export default function SmoothScroll() {
  const [scrollProgress, setScrollProgress] = useState(0);

  useEffect(() => {
    // Initialize buttery-smooth Lenis momentum scrolling
    const lenis = new Lenis({
      duration: 1.1,
      easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)), // Exponential ease-out
      orientation: "vertical",
      gestureOrientation: "vertical",
      smoothWheel: true,
      wheelMultiplier: 0.95,
      touchMultiplier: 1.2,
    });

    lenis.on("scroll", (e: { progress: number }) => {
      setScrollProgress(e.progress * 100);
    });

    let animationFrameId: number;
    function raf(time: number) {
      lenis.raf(time);
      animationFrameId = requestAnimationFrame(raf);
    }

    animationFrameId = requestAnimationFrame(raf);

    // Smooth handle for internal hash links
    const handleAnchorClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const anchor = target.closest("a");
      if (anchor && anchor.hash && anchor.origin === window.location.origin) {
        const targetElem = document.querySelector(anchor.hash);
        if (targetElem) {
          e.preventDefault();
          lenis.scrollTo(targetElem as HTMLElement, {
            offset: -80,
            duration: 1.2,
          });
        }
      }
    };

    document.addEventListener("click", handleAnchorClick);

    return () => {
      cancelAnimationFrame(animationFrameId);
      document.removeEventListener("click", handleAnchorClick);
      lenis.destroy();
    };
  }, []);

  return (
    <>
      {/* ── Fixed High-Tech Top Scroll Progress Laser Bar ── */}
      <div className="fixed top-0 left-0 right-0 h-[2px] z-[100] pointer-events-none bg-transparent">
        <div
          className="h-full bg-gradient-to-r from-[#143ca3] via-[#ff6363] to-[#ff6363] transition-[width] duration-75 ease-out shadow-[0_0_8px_rgba(255,99,99,0.8)]"
          style={{ width: `${scrollProgress}%` }}
        />
      </div>
    </>
  );
}
