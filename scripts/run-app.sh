#!/bin/bash
# Builds Flightdeck and launches it as a real .app bundle.
# Always launch via this script, not `swift run` — see scripts/make-app.sh for why.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
APP="$BUILD_DIR/Flightdeck.app"

swift build -c "$CONFIG"
./scripts/make-app.sh "$BUILD_DIR/Flightdeck" "$APP" "$(cat VERSION 2>/dev/null || echo 0.1.0)" "dev" >/dev/null

# Ad-hoc sign so TCC (Accessibility) can remember the grant across launches.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

killall Flightdeck 2>/dev/null || true
sleep 0.2

echo "built $APP"
open "$APP"
