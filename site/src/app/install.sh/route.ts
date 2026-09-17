import { NextResponse } from "next/server";

export async function GET() {
  const script = `#!/bin/bash
# ⚡️ Flightdeck Automated Installer
# https://flightdeck-app.netlify.app
#
set -euo pipefail

echo ""
echo "  ⚡️ FLIGHTDECK INSTALLER"
echo "  ──────────────────────────────────────────────────"
echo "  The Cyberpunk Activity Monitor & Developer Cockpit"
echo ""

# 1. OS Check
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  echo "!! Flightdeck requires macOS. Detected OS: $OS" >&2
  exit 1
fi

# 2. Version Check (macOS 14+ Sonoma/Sequoia required)
DARWIN_MAJOR="$(uname -r | cut -d. -f1)"
if [ "$DARWIN_MAJOR" -lt 23 ]; then
  echo "!! Flightdeck requires macOS 14 Sonoma or macOS 15 Sequoia (Darwin 23+)." >&2
  echo "   Current Darwin kernel version: $(uname -r)" >&2
  exit 1
fi

ARCH="$(uname -m)"
echo "  ✓ macOS $(sw_vers -productVersion) ($ARCH)"

# 3. Prefer Homebrew if available
if command -v brew >/dev/null 2>&1; then
  echo "  ==> Installing via Homebrew (un-quarantined binary)..."
  brew tap Jackpkn/flightdeck 2>/dev/null || true
  brew install flightdeck
  echo ""
  echo "  ✓ Installed flightdeck to PATH."
  echo "  Run it in terminal: flightdeck"
  echo "  Or inspect vitals:  flightdeck vitals"
  exit 0
fi

# 4. Fallback: Direct DMG Download
echo "  ==> Homebrew not found. Fetching latest universal DMG..."
VERSION="0.2.0"
DMG_URL="https://github.com/Jackpkn/Flightdeck/releases/download/v\${VERSION}/Flightdeck-\${VERSION}.dmg"
TMP_DIR="$(mktemp -d)"
TMP_DMG="$TMP_DIR/Flightdeck.dmg"

curl -fsSL "$DMG_URL" -o "$TMP_DMG"
echo "  ✓ Downloaded Flightdeck \${VERSION} DMG"

echo "  ==> Mounting and copying to /Applications..."
MOUNT_DIR="$TMP_DIR/mount"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -quiet -nobrowse

rm -rf "/Applications/Flightdeck.app"
cp -R "$MOUNT_DIR/Flightdeck.app" "/Applications/"
hdiutil detach "$MOUNT_DIR" -quiet || true
rm -rf "$TMP_DIR"

echo "  ==> Clearing quarantine attribute..."
xattr -dr com.apple.quarantine "/Applications/Flightdeck.app" 2>/dev/null || true

echo ""
echo "  🎉 Flightdeck \${VERSION} installed to /Applications/Flightdeck.app!"
echo "  Open it now from Spotlight, Finder, or run:"
echo "  open /Applications/Flightdeck.app"
echo ""
`;

  return new NextResponse(script, {
    headers: {
      "Content-Type": "text/x-shellscript; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=86400",
    },
  });
}
