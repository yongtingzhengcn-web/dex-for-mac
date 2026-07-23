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

# App icon (regenerate the .icns from icon.svg if the tools are available).
if command -v rsvg-convert >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/DeXBar.iconset"
  mkdir -p "$ICONSET"
  for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
              256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    rsvg-convert -w "${spec%%:*}" -h "${spec%%:*}" "$HERE/icon.svg" -o "$ICONSET/icon_${spec##*:}.png"
  done
  iconutil -c icns "$ICONSET" -o "$HERE/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi
cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
