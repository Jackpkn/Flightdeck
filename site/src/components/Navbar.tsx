"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Terminal, Menu, X, Volume2, VolumeX } from "lucide-react";
import { isAudioMuted, toggleAudioMute, playClickSound } from "@/utils/audio";

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [muted, setMuted] = useState(true);
  const pathname = usePathname();

  useEffect(() => {
    setMuted(isAudioMuted());
    const onAudioToggle = (e: Event) => {
      const customEvent = e as CustomEvent<{ muted: boolean }>;
      if (customEvent.detail) setMuted(customEvent.detail.muted);
    };
    window.addEventListener("flightdeck-audio-toggle", onAudioToggle);
    return () => window.removeEventListener("flightdeck-audio-toggle", onAudioToggle);
  }, []);

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20);
    };
    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  // Close mobile menu on route change
  useEffect(() => {
    setMobileMenuOpen(false);
  }, [pathname]);

  const navLinks = [
    { href: "/", label: "Overview" },
    { href: "/forensics", label: "Claude Spend" },
    { href: "/system", label: "Mach Vitals" },
    { href: "/storage", label: "Storage Radar" },
    { href: "/manifesto", label: "Manifesto" },
  ];

  return (
    <header className="fixed top-4 inset-x-0 z-50 flex flex-col items-center px-4 pointer-events-none">
      <nav
        className={`pointer-events-auto w-full max-w-[1060px] h-12 px-4 rounded-[8px] border border-[#363739]/60 flex items-center justify-between transition-all duration-300 ${
          scrolled || mobileMenuOpen
            ? "bg-[#07080a]/85 backdrop-blur-[48px] shadow-[0_8px_32px_rgba(0,0,0,0.8)] border-[#363739]"
            : "bg-[#07080a]/55 backdrop-blur-[24px]"
        }`}
        style={{
          boxShadow:
            "rgba(255, 255, 255, 0.05) 0px 1px 0px 0px inset, rgba(0, 0, 0, 0.5) 0px 10px 30px 0px",
        }}
      >
        {/* Brand Logo */}
        <Link href="/" className="flex items-center gap-2.5 group">
          <div className="w-3.5 h-3.5 rotate-45 bg-[#ff6363] shadow-[0_0_12px_rgba(255,99,99,0.7)] group-hover:scale-110 transition-transform duration-200" />
          <span className="text-[13px] font-medium tracking-[0.04em] text-[#ffffff] font-sans">
            FLIGHTDECK
          </span>
          <span className="hidden sm:inline-block px-1.5 py-0.5 text-[10px] font-mono tracking-wider text-[#9c9c9d] bg-[#1b1c1e] rounded-[4px] border border-white/5">
            v0.8.4
          </span>
        </Link>

        {/* Center Multi-Tab Navigation Links (Desktop) */}
        <div className="hidden md:flex items-center gap-5 text-[13px] font-medium">
          {navLinks.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                onClick={playClickSound}
                className={`relative py-1 transition-colors flex items-center gap-1.5 ${
                  isActive
                    ? "text-white"
                    : "text-[#9c9c9d] hover:text-white"
                }`}
              >
                {isActive && (
                  <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] shadow-[0_0_6px_#ff6363]" />
                )}
                <span>{link.label}</span>
              </Link>
            );
          })}
        </div>

        {/* Right Actions */}
        <div className="flex items-center gap-2">
          {/* Audio Telemetry Toggle */}
          <button
            onClick={() => {
              toggleAudioMute();
            }}
            className="p-1.5 rounded-[6px] text-[#9c9c9d] hover:text-white hover:bg-white/5 transition-colors flex items-center gap-1 text-[11px] font-mono"
            title={muted ? "Enable telemetry sound effects" : "Mute telemetry sound effects"}
            aria-label={muted ? "Enable audio" : "Mute audio"}
          >
            {muted ? (
              <VolumeX className="w-3.5 h-3.5 text-[#6a6b6c]" />
            ) : (
              <Volume2 className="w-3.5 h-3.5 text-[#ff6363] animate-pulse" />
            )}
            <span className="hidden lg:inline text-[10px] text-[#6a6b6c]">{muted ? "MUTED" : "AUDIO"}</span>
          </button>

          <a
            href="https://github.com/Jackpkn/Flightdeck"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:flex items-center gap-1.5 text-[12px] font-mono text-[#9c9c9d] hover:text-[#ffffff] transition-colors px-2 py-1 rounded-[6px] hover:bg-white/5"
          >
            <Terminal className="w-3.5 h-3.5 text-[#6a6b6c]" />
            <span>GitHub</span>
          </a>

          {/* Primary Action Button — Mist (#e6e6e6) fill, Iron (#454647) text */}
          <a
            href="https://github.com/Jackpkn/Flightdeck-releases/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 bg-[#e6e6e6] hover:bg-[#ffffff] text-[#454647] hover:text-[#111214] text-[13px] font-medium px-3.5 py-1.5 rounded-[8px] transition-all duration-150 btn-lift"
          >
            <svg
              className="w-3.5 h-3.5 fill-current"
              viewBox="0 0 170 170"
            >
              <path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.69-3.04-7.6-7.77-11.74-14.19-6.08-9.43-10.74-19.89-13.98-31.39-3.24-11.5-4.86-22.37-4.86-32.61 0-14.44 3.73-26.4 11.19-35.88 7.46-9.48 17.07-14.33 28.84-14.56 4.79 0 10.36 1.34 16.71 4.02 6.35 2.68 10.22 4.08 11.61 4.2 1.9-.24 5.92-1.63 12.07-4.17 6.15-2.54 11.45-3.75 15.89-3.63 8.35.36 15.65 2.54 21.9 6.53 6.25 3.99 10.79 9.38 13.62 16.17-12.01 7.25-17.91 17.26-17.7 30.03.22 10.02 4.04 18.23 11.47 24.63 7.43 6.4 16.14 10.15 26.13 11.25-2.39 7.02-5.46 14.28-9.21 21.78zM119.22 33.64c0-7.39 2.68-14.34 8.04-20.85 5.36-6.51 12.04-10.79 20.04-12.84.44 1.77.66 3.48.66 5.13 0 7.39-2.73 14.43-8.19 21.12-5.46 6.69-12.18 10.96-20.16 12.81-.22-1.77-.39-3.56-.39-5.37z" />
            </svg>
            <span>Download</span>
          </a>

          {/* Mobile Menu Toggle Button */}
          <button
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="md:hidden p-1.5 rounded-[6px] text-[#9c9c9d] hover:text-white hover:bg-white/5 transition-colors"
            aria-label="Toggle Navigation Menu"
          >
            {mobileMenuOpen ? (
              <X className="w-5 h-5 text-white" />
            ) : (
              <Menu className="w-5 h-5" />
            )}
          </button>
        </div>
      </nav>

      {/* Mobile Dropdown Menu Drawer */}
      {mobileMenuOpen && (
        <div
          className="pointer-events-auto w-full max-w-[1060px] mt-2 p-3 rounded-[12px] bg-[#07080a]/95 backdrop-blur-[48px] border border-[#363739] shadow-[0_16px_40px_rgba(0,0,0,0.9)] flex flex-col gap-1 md:hidden transition-all duration-200 animate-in fade-in slide-in-from-top-2"
          style={{
            boxShadow:
              "rgba(255, 255, 255, 0.05) 0px 1px 0px 0px inset, rgba(0, 0, 0, 0.8) 0px 16px 40px 0px",
          }}
        >
          {navLinks.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`px-3 py-2 rounded-[6px] text-[14px] font-medium transition-colors flex items-center justify-between ${
                  isActive
                    ? "bg-[#1b1c1e] text-white"
                    : "text-[#9c9c9d] hover:text-white hover:bg-white/5"
                }`}
              >
                <span>{link.label}</span>
                {isActive && (
                  <span className="w-1.5 h-1.5 rounded-full bg-[#ff6363] shadow-[0_0_6px_#ff6363]" />
                )}
              </Link>
            );
          })}
          <div className="pt-2 mt-1 border-t border-[#1b1c1e] flex items-center justify-between px-3 text-[12px] font-mono text-[#6a6b6c]">
            <a
              href="https://github.com/Jackpkn/Flightdeck"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white transition-colors flex items-center gap-1.5"
            >
              <Terminal className="w-3.5 h-3.5" />
              <span>GitHub Repository</span>
            </a>
            <span>v0.8.4</span>
          </div>
        </div>
      )}
    </header>
  );
}
