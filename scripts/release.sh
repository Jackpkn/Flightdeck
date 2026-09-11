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

# 5. Notarise and staple, so the DMG opens without a warning.
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
echo "==> Done: $DMG"
du -h "$DMG"
