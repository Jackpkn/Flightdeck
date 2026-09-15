"use client";

import React from "react";
import { ExternalLink } from "lucide-react";

export default function Footer() {
  return (
    <footer className="border-t border-[#363739]/60 bg-[#040506] py-12 px-4 sm:px-6">
      <div className="max-w-[1200px] mx-auto flex flex-col md:flex-row items-center justify-between gap-6">
        {/* Brand & Tagline */}
        <div className="flex items-center gap-3">
          <div className="w-3 h-3 rotate-45 bg-[#ff6363] shadow-[0_0_10px_rgba(255,99,99,0.6)]" />
          <span className="text-[13px] font-medium text-white font-sans tracking-wide">
            FLIGHTDECK
          </span>
          <span className="text-[12px] text-[#6a6b6c] hidden sm:inline">
            &mdash; The Cyberpunk Activity Monitor for macOS
          </span>
        </div>

        {/* Links */}
        <div className="flex items-center gap-6 text-[13px] text-[#9c9c9d]">
          <a
            href="https://github.com/Jackpkn/Flightdeck"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-white flex items-center gap-1.5 transition-colors"
          >
            <svg className="w-4 h-4 text-[#6a6b6c] fill-current" viewBox="0 0 24 24">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
            <span>GitHub</span>
          </a>
          <a
            href="https://github.com/Jackpkn/Flightdeck-releases/releases"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-white flex items-center gap-1.5 transition-colors"
          >
            <span>Releases</span>
            <ExternalLink className="w-3 h-3 text-[#6a6b6c]" />
          </a>
        </div>
      </div>

      {/* Monospace Technical Strip */}
      <div className="max-w-[1200px] mx-auto mt-8 pt-6 border-t border-[#1b1c1e] flex flex-wrap items-center justify-center md:justify-between gap-3 text-[12px] font-mono text-[#6a6b6c]">
        <div className="flex flex-wrap items-center justify-center gap-2">
          <span>v0.8.4</span>
          <span className="text-[#2f3031]">|</span>
          <span>macOS 14.0+</span>
          <span className="text-[#2f3031]">|</span>
          <span>Apple Silicon &amp; Intel x86_64</span>
          <span className="text-[#2f3031]">|</span>
          <span className="text-[#59d499]">239 Tests Passing</span>
          <span className="text-[#2f3031]">|</span>
          <span>MIT License</span>
        </div>

        <div>
          <span>Crafted with zero cloud dependencies</span>
        </div>
      </div>
    </footer>
  );
}
