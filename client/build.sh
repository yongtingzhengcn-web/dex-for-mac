#!/usr/bin/env bash
set -euo pipefail

# Build DeXClient.app — a self-contained native DeX client.
#
# Bundles the scrcpy server jar (pinned version, SHA-256 verified) and Google's
# platform-tools adb, so users don't need Homebrew. Produces a universal binary.
#
# Usage: ./build.sh [output-dir] [version]

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HERE/build}"
APP="$OUT_DIR/DeXClient.app"
VERSION="${2:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$HERE" describe --tags 2>/dev/null || echo 2.0.0)"
fi
VERSION="${VERSION#v}"

SCRCPY_VERSION="5.0.1"
SCRCPY_SERVER_SHA256="764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536"
SCRCPY_SERVER_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-server-v${SCRCPY_VERSION}"
PLATFORM_TOOLS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"

DEPS="$HERE/.deps"
mkdir -p "$DEPS"

echo "== Building DeXClient.app v${VERSION} (universal) =="

# 1. scrcpy server (pinned + checksum-verified)
SERVER_JAR="$DEPS/scrcpy-server"
if [ ! -f "$SERVER_JAR" ]; then
  echo "Downloading scrcpy-server v${SCRCPY_VERSION} …"
  curl -fSL "$SCRCPY_SERVER_URL" -o "$SERVER_JAR"
fi
echo "$SCRCPY_SERVER_SHA256 *$SERVER_JAR" | shasum -a 256 -c - >/dev/null \
  || { echo "scrcpy-server checksum mismatch"; exit 1; }

# 2. adb from Google platform-tools
ADB="$DEPS/adb"
if [ ! -f "$ADB" ]; then
  echo "Downloading platform-tools …"
  curl -fSL "$PLATFORM_TOOLS_URL" -o "$DEPS/platform-tools.zip"
  unzip -o -q "$DEPS/platform-tools.zip" "platform-tools/adb" -d "$DEPS"
  mv "$DEPS/platform-tools/adb" "$ADB"
  rm -rf "$DEPS/platform-tools" "$DEPS/platform-tools.zip"
fi
chmod +x "$ADB"

# 3. Compile (universal)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
MIN_MACOS="13.0"
BIN_DIR="$APP/Contents/MacOS"
SOURCES=("$HERE"/Sources/*.swift)
swiftc -O -target "arm64-apple-macos${MIN_MACOS}" \
  -framework AppKit -framework Metal -framework MetalKit \
  -framework AVFoundation -framework Network \
  -o "$BIN_DIR/DeXClient-arm64" "${SOURCES[@]}"
swiftc -O -target "x86_64-apple-macos${MIN_MACOS}" \
  -framework AppKit -framework Metal -framework MetalKit \
  -framework AVFoundation -framework Network \
  -o "$BIN_DIR/DeXClient-x86_64" "${SOURCES[@]}"
lipo -create "$BIN_DIR/DeXClient-arm64" "$BIN_DIR/DeXClient-x86_64" -o "$BIN_DIR/DeXClient"
rm -f "$BIN_DIR/DeXClient-arm64" "$BIN_DIR/DeXClient-x86_64"

# 4. Bundle resources
cp "$SERVER_JAR" "$APP/Contents/Resources/scrcpy-server"
cp "$ADB" "$APP/Contents/Resources/adb"

# 5. Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DeXClient</string>
    <key>CFBundleDisplayName</key>
    <string>DeXClient</string>
    <key>CFBundleIdentifier</key>
    <string>com.github.dexformac.dexclient</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DeXClient</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets a locally built app run.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP (v${VERSION}, $(lipo -archs "$BIN_DIR/DeXClient"))"
echo "Run it with:  open \"$APP\""
