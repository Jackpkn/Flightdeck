import { ImageResponse } from "next/og";
import { NextRequest } from "next/server";

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const title = searchParams.get("title") || "Flightdeck — Developer Cockpit for macOS";
  const subtitle = searchParams.get("subtitle") || "You already know what Claude Code cost. Flightdeck shows what it became.";

  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "#040506",
          backgroundImage: "radial-gradient(circle at 50% 40%, #0b2259 0%, #040506 65%)",
          padding: "60px 80px",
          position: "relative",
          fontFamily: "sans-serif",
        }}
      >
        {/* Neon Coral Underglow Accent */}
        <div
          style={{
            position: "absolute",
            width: "600px",
            height: "300px",
            borderRadius: "50%",
            background: "radial-gradient(circle, rgba(255, 99, 99, 0.35) 0%, transparent 70%)",
            filter: "blur(60px)",
            top: "150px",
          }}
        />

        {/* Brand Eyebrow Badge */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "10px",
            padding: "8px 20px",
            borderRadius: "9999px",
            backgroundColor: "rgba(17, 18, 20, 0.9)",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            marginBottom: "30px",
          }}
        >
          <div
            style={{
              width: "10px",
              height: "10px",
              borderRadius: "50%",
              backgroundColor: "#ff6363",
            }}
          />
          <span
            style={{
              color: "#e6e6e6",
              fontSize: "14px",
              fontFamily: "monospace",
              letterSpacing: "0.1em",
              textTransform: "uppercase",
            }}
          >
            FLIGHTDECK &middot; LOCAL CLAUDE FORENSICS &middot; MACOS 14+
          </span>
        </div>

        {/* Monumental Headline */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            textAlign: "center",
            fontSize: "52px",
            fontWeight: 500,
            color: "#ffffff",
            lineHeight: 1.15,
            letterSpacing: "-0.03em",
            marginBottom: "24px",
            maxWidth: "960px",
          }}
        >
          {title}
        </div>

        {/* Subtitle */}
        <div
          style={{
            fontSize: "22px",
            color: "#b4b4b5",
            textAlign: "center",
            maxWidth: "800px",
            lineHeight: 1.5,
            marginBottom: "40px",
          }}
        >
          {subtitle}
        </div>

        {/* Footer Meta */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "24px",
            color: "#6a6b6c",
            fontFamily: "monospace",
            fontSize: "14px",
          }}
        >
          <span>1,000 HZ MACH KERNEL</span>
          <span>&middot;</span>
          <span>100% PRIVATE LOCAL SQLITE</span>
          <span>&middot;</span>
          <span>NATIVE SWIFT 6</span>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
    }
  );
}
