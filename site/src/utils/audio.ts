"use client";

// Web Audio API Synthesizer for Cyberpunk Sci-Fi Telemetry Feedback
// 100% Client-Side, zero audio file downloads

let audioCtx: AudioContext | null = null;
let isMuted = true; // Default muted for unobtrusive UX

function getAudioContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
  if (audioCtx && audioCtx.state === "suspended") {
    audioCtx.resume();
  }
  return audioCtx;
}

export function isAudioMuted(): boolean {
  if (typeof window !== "undefined") {
    const saved = localStorage.getItem("flightdeck_audio_muted");
    if (saved !== null) {
      isMuted = saved === "true";
    }
  }
  return isMuted;
}

export function toggleAudioMute(): boolean {
  isMuted = !isAudioMuted();
  if (typeof window !== "undefined") {
    localStorage.setItem("flightdeck_audio_muted", String(isMuted));
    window.dispatchEvent(new CustomEvent("flightdeck-audio-toggle", { detail: { muted: isMuted } }));
  }
  if (!isMuted) {
    playSuccessChime();
  }
  return isMuted;
}

// 1. Mechanical Keycap Pulse (Short tactile click)
export function playClickSound() {
  if (isAudioMuted()) return;
  const ctx = getAudioContext();
  if (!ctx) return;

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  const filter = ctx.createBiquadFilter();

  osc.type = "sine";
  osc.frequency.setValueAtTime(1200, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(300, ctx.currentTime + 0.03);

  filter.type = "bandpass";
  filter.frequency.value = 1400;
  filter.Q.value = 3;

  gain.gain.setValueAtTime(0.06, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.03);

  osc.connect(filter);
  filter.connect(gain);
  gain.connect(ctx.destination);

  osc.start(ctx.currentTime);
  osc.stop(ctx.currentTime + 0.03);
}

// 2. Radar Sonar Blip (Smooth resonant sweep)
export function playRadarBlip() {
  if (isAudioMuted()) return;
  const ctx = getAudioContext();
  if (!ctx) return;

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();

  osc.type = "sine";
  osc.frequency.setValueAtTime(600, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(1100, ctx.currentTime + 0.08);

  gain.gain.setValueAtTime(0.05, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.12);

  osc.connect(gain);
  gain.connect(ctx.destination);

  osc.start(ctx.currentTime);
  osc.stop(ctx.currentTime + 0.12);
}

// 3. Process Kill Laser (Descending saw bite)
export function playKillLaser() {
  if (isAudioMuted()) return;
  const ctx = getAudioContext();
  if (!ctx) return;

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();

  osc.type = "sawtooth";
  osc.frequency.setValueAtTime(850, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(120, ctx.currentTime + 0.14);

  gain.gain.setValueAtTime(0.07, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.14);

  osc.connect(gain);
  gain.connect(ctx.destination);

  osc.start(ctx.currentTime);
  osc.stop(ctx.currentTime + 0.14);
}

// 4. Confirmation Chime (Crisp dual harmonic)
export function playSuccessChime() {
  const ctx = getAudioContext();
  if (!ctx) return;

  [880, 1320].forEach((freq, i) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = "sine";
    osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.06);

    gain.gain.setValueAtTime(0.05, ctx.currentTime + i * 0.06);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + i * 0.06 + 0.16);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start(ctx.currentTime + i * 0.06);
    osc.stop(ctx.currentTime + i * 0.06 + 0.16);
  });
}
