#!/bin/bash
# Builds Flightdeck and registers its statusline & hook integration in ~/.claude/settings.json
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
echo "Building Flightdeck ($CONFIG)..."
swift build -c "$CONFIG"

BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
if [ ! -f "$BUILD_DIR/Flightdeck" ]; then
    # Fallback to general release/debug dir if architecture path differs
    BUILD_DIR=".build/$CONFIG"
fi

echo "Installing Claude Code statusline and hooks..."
"$BUILD_DIR/Flightdeck" install-hooks

echo ""
echo "Claude Code integration setup complete!"
echo "Flightdeck is now registered to receive statusline telemetry and hook events."
