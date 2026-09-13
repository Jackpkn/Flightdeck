import type { Metadata, Viewport } from "next";
import { Inter, Geist_Mono } from "next/font/google";
import "./globals.css";
import KeyboardShortcutsModal from "@/components/KeyboardShortcutsModal";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  display: "swap",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  display: "swap",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#040506",
};

export const metadata: Metadata = {
  metadataBase: new URL("https://flightdeck-app.netlify.app"),
  title: "Flightdeck — The Cyberpunk Activity Monitor & Developer Cockpit for macOS",
  description: "A dark power-tool cockpit that measures what your Claude Code spend actually produced — cost per surviving file, measured against git. Everything stays on your Mac.",
  keywords: ["macOS", "activity monitor", "Claude Code", "developer cockpit", "Mach kernel", "telemetry", "system monitor", "cockpit UI"],
  authors: [{ name: "Flightdeck Team" }],
  openGraph: {
    title: "Flightdeck — Developer Cockpit for macOS",
    description: "You already know what Claude Code cost. Flightdeck shows what it became.",
    url: "https://flightdeck.run",
    siteName: "Flightdeck",
    type: "website",
    images: [
      {
        url: "/api/og",
        width: 1200,
        height: 630,
        alt: "Flightdeck — The Cyberpunk Activity Monitor & Developer Cockpit for macOS",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Flightdeck — Developer Cockpit for macOS",
    description: "You already know what Claude Code cost. Flightdeck shows what it became.",
    images: ["/api/og"],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${geistMono.variable} bg-[#040506] text-[#ffffff] antialiased selection:bg-[#ff6363] selection:text-white`}
    >
      <body className="min-h-screen bg-[#040506] text-[#ffffff] font-sans flex flex-col">
        {children}
        <KeyboardShortcutsModal />
      </body>
    </html>
  );
}
