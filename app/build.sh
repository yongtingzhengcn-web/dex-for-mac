#!/usr/bin/env bash
set -euo pipefail

# Build DeXBar.app from DeXBar.swift into an .app bundle.
# Usage: ./build.sh [output-dir] [version]
#   output-dir: default ./build
#   version:    default from `git describe --tags`, else 1.0.0 (leading "v" stripped)
#
# Produces a universal (arm64 + x86_64) binary.

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HERE/build}"
APP="$OUT_DIR/DeXBar.app"
VERSION="${2:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$HERE" describe --tags 2>/dev/null || echo 1.0.0)"
fi
VERSION="${VERSION#v}"

echo "== Building DeXBar.app v${VERSION} (universal) =="

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Compile for both architectures, then combine with lipo.
MIN_MACOS="13.0"
BIN_DIR="$APP/Contents/MacOS"
swiftc -O -target "arm64-apple-macos${MIN_MACOS}" \
  -framework AppKit \
  -o "$BIN_DIR/DeXBar-arm64" \
  "$HERE/DeXBar.swift"
swiftc -O -target "x86_64-apple-macos${MIN_MACOS}" \
  -framework AppKit \
  -o "$BIN_DIR/DeXBar-x86_64" \
  "$HERE/DeXBar.swift"
lipo -create "$BIN_DIR/DeXBar-arm64" "$BIN_DIR/DeXBar-x86_64" -o "$BIN_DIR/DeXBar"
rm -f "$BIN_DIR/DeXBar-arm64" "$BIN_DIR/DeXBar-x86_64"

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
cat > "$APP/Contents/Info.plist" <<PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DeXBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code signature so Gatekeeper lets a locally built app run.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP (v${VERSION}, $(lipo -archs "$BIN_DIR/DeXBar"))"
echo "Run it with:  open \"$APP\""
