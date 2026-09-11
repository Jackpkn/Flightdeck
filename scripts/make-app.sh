#!/bin/bash
# Assembles Flightdeck.app from a built binary.
#
# A bare SPM executable has no Info.plist, no bundle identifier and no main menu —
# and on macOS SwiftUI's .keyboardShortcut is routed through the main menu, so ⌘K/⌘F
# silently do nothing when run unbundled. Everything that produces a runnable app
# goes through here so the dev and release paths can't drift.
set -euo pipefail

BINARY="$1"        # path to the compiled Flightdeck executable
APP="$2"           # path of the .app bundle to create
VERSION="${3:-0.1.0}"
BUILD="${4:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Flightdeck"

# Bundle.module resolves through Bundle.main.resourceURL once bundled, so the SPM
# resource bundle (the fonts) has to land in Contents/Resources.
BIN_DIR="$(dirname "$BINARY")"
if [ -d "$BIN_DIR/Flightdeck_Flightdeck.bundle" ]; then
  cp -R "$BIN_DIR/Flightdeck_Flightdeck.bundle" "$APP/Contents/Resources/"
fi

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Flightdeck</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.flightdeck.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Flightdeck</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>MIT Licensed</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
</dict>
</plist>
PLIST

echo "$APP"
