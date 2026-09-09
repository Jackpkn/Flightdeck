#!/bin/bash
# Builds Flightdeck and wraps it in a real .app bundle before launching.
#
# A bare SPM executable has no Info.plist, no bundle identifier and no main
# menu — and on macOS SwiftUI's .keyboardShortcut is implemented through the
# main menu, so ⌘K/⌘F silently do nothing when run as a plain binary. Text
# field focus and key-window behavior are unreliable too. Always launch via
# this script, not `swift run`.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
APP="$BUILD_DIR/Flightdeck.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Flightdeck" "$APP/Contents/MacOS/Flightdeck"

# Bundle.module resolves through Bundle.main.resourceURL once bundled, so the
# SPM resource bundle (the fonts) has to land in Contents/Resources.
if [ -d "$BUILD_DIR/Flightdeck_Flightdeck.bundle" ]; then
  cp -R "$BUILD_DIR/Flightdeck_Flightdeck.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Flightdeck</string>
	<key>CFBundleIdentifier</key>
	<string>com.flightdeck.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Flightdeck</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC (Accessibility) can remember the grant across launches.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
open "$APP"
