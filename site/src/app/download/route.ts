import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const version = searchParams.get("version") || "0.2.0";
  const format = searchParams.get("format");

  // If user requests the un-quarantined Homebrew tarball
  if (format === "tar" || format === "tarball") {
    const tarUrl = `https://github.com/Jackpkn/Flightdeck/releases/download/v${version}/Flightdeck-${version}-universal.tar.gz`;
    return NextResponse.redirect(tarUrl, 307);
  }

  // Default: Universal DMG installer
  const dmgUrl = `https://github.com/Jackpkn/Flightdeck/releases/download/v${version}/Flightdeck-${version}.dmg`;
  return NextResponse.redirect(dmgUrl, 307);
}
