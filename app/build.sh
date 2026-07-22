#!/usr/bin/env bash
set -euo pipefail

# Build DeXBar.app from DeXBar.swift into an .app bundle.
# Usage: ./build.sh [output-dir]   (default: ./build)

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HERE/build}"
APP="$OUT_DIR/DeXBar.app"

echo "== Building DeXBar.app =="

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Compile the binary.
swiftc -O \
  -framework AppKit \
  -o "$APP/Contents/MacOS/DeXBar" \
  "$HERE/DeXBar.swift"

# Info.plist — LSUIElement hides the Dock icon (menu-bar-only app).
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DeXBar</string>
    <key>CFBundleDisplayName</key>
    <string>DeXBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.github.dexformac.dexbar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DeXBar</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code signature so Gatekeeper lets a locally built app run.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
echo "Run it with:  open \"$APP\""
