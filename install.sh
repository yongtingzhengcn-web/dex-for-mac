#!/usr/bin/env bash
set -euo pipefail

echo "== dex-for-mac installer =="

# 1. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi
fi

# 2. scrcpy + adb
brew list scrcpy >/dev/null 2>&1 || brew install scrcpy
brew list --cask android-platform-tools >/dev/null 2>&1 || brew install --cask android-platform-tools

BREW_PREFIX="$(brew --prefix)"

# 3. Resolution / DPI prompt
read -rp "Virtual display resolution [1920x1080]: " RES
RES="${RES:-1920x1080}"
read -rp "DPI (density) [160]: " DPI
DPI="${DPI:-160}"

DISPLAY_ARG="${RES}/${DPI}"

# 4. Shell alias — absolute paths with ADB set explicitly, so every new shell
#    doesn't pay for a `brew shellenv` eval just to run dex.
SHELL_RC="$HOME/.zshrc"
ALIAS_LINE="alias dex=\"ADB=${BREW_PREFIX}/bin/adb ${BREW_PREFIX}/bin/scrcpy --new-display=${DISPLAY_ARG}\""
touch "$SHELL_RC"
if grep -q "^alias dex=" "$SHELL_RC"; then
  grep -v "^alias dex=" "$SHELL_RC" > "$SHELL_RC.tmp" || true
  mv "$SHELL_RC.tmp" "$SHELL_RC"
  echo "$ALIAS_LINE" >> "$SHELL_RC"
  echo "Updated 'dex' alias in $SHELL_RC"
else
  echo "$ALIAS_LINE" >> "$SHELL_RC"
  echo "Added 'dex' alias to $SHELL_RC"
fi

# 5. Double-clickable Desktop app
APP_PATH="$HOME/Desktop/DeX.app"
TMP_SCPT="$(mktemp /tmp/dex_launcher.XXXXXX.applescript)"
cat > "$TMP_SCPT" <<EOF
do shell script "ADB=${BREW_PREFIX}/bin/adb nohup ${BREW_PREFIX}/bin/scrcpy --new-display=${DISPLAY_ARG} > /tmp/dex_scrcpy.log 2>&1 & disown"
EOF
rm -rf "$APP_PATH"
osacompile -o "$APP_PATH" "$TMP_SCPT"
rm -f "$TMP_SCPT"
echo "Created double-click app at $APP_PATH"

echo ""
echo "Done. Connect your Galaxy phone (One UI 8 / Android 16+) via USB, then either:"
echo "  - double-click $APP_PATH, or"
echo "  - open a new terminal and run: dex"
