#!/bin/bash
# Builds a distributable Flightdeck: universal binary, signed, packaged into a DMG.
#
# Signing and notarisation need an Apple Developer account ($99/yr). Without one the
# script still produces a working universal DMG — it just stays ad-hoc signed, and
# Gatekeeper will warn anyone who downloads it. Set the env vars below to get a
# release that opens cleanly on other people's machines:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="flightdeck"   # from: xcrun notarytool store-credentials
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/Flightdeck.app"
DMG="$DIST/Flightdeck-$VERSION.dmg"
TARBALL="$DIST/Flightdeck-$VERSION-universal.tar.gz"

echo "==> Flightdeck $VERSION (build $BUILD)"
rm -rf "$DIST"
mkdir -p "$DIST"

# 1. Universal binary — Apple Silicon and Intel in one build.
echo "==> Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

UNIVERSAL="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Flightdeck"
if [ ! -f "$UNIVERSAL" ]; then
  echo "!! universal binary not found at $UNIVERSAL" >&2
  exit 1
fi
echo "    $(lipo -archs "$UNIVERSAL")"

# 2. Bundle.
echo "==> Assembling app bundle"
./scripts/make-app.sh "$UNIVERSAL" "$APP" "$VERSION" "$BUILD" >/dev/null

# 3. Sign. A hardened runtime is required for notarisation.
if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing with Developer ID"
  codesign --force --deep --options runtime --timestamp \
           --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No DEVELOPER_ID set — ad-hoc signing (Gatekeeper will warn on other Macs)"
  codesign --force --deep --sign - "$APP"
fi

# 4. DMG.
echo "==> Building DMG"
STAGING="$DIST/staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Flightdeck $VERSION" -srcfolder "$STAGING" \
        -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# 5. Tarball, for Homebrew.
#
# This is the install path that works without a certificate. macOS applies
# com.apple.quarantine at *download* time, and only browsers do it — Homebrew
# fetches with curl, so a tarball it installs is never quarantined and Gatekeeper
# never engages. A cask cannot be used for the same job: Homebrew 6 removed
# --no-quarantine, so casks always quarantine.
echo "==> Building tarball (the un-quarantined Homebrew path)"
TAR_STAGING="$DIST/Flightdeck-$VERSION"
rm -rf "$TAR_STAGING"
mkdir -p "$TAR_STAGING"
cp -R "$APP" "$TAR_STAGING/"
tar czf "$TARBALL" -C "$DIST" "Flightdeck-$VERSION"
rm -rf "$TAR_STAGING"
shasum -a 256 "$TARBALL" | awk '{print $1}' > "$TARBALL.sha256"
echo "    sha256 $(cat "$TARBALL.sha256")"

# 6. Notarise and staple, so the DMG opens without a warning.
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Submitting for notarisation (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature -vv "$DMG" || true
else
  echo "==> Skipping notarisation (set DEVELOPER_ID and NOTARY_PROFILE to enable)"
fi

echo ""
echo "==> Done"
du -h "$DMG" "$TARBALL"
