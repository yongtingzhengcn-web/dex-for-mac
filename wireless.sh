#!/usr/bin/env bash
set -euo pipefail

# Set up (or reconnect) wireless adb for DeX, then optionally launch scrcpy.
#
# Usage:
#   ./wireless.sh setup     # one-time: phone on USB -> switch to WiFi, save IP, unplug
#   ./wireless.sh connect   # reconnect later over WiFi (phone already in tcpip mode)
#   ./wireless.sh start     # connect (if needed) and launch DeX
#   ./wireless.sh status    # show adb devices
#
# The phone IP is remembered in ~/.config-dex/phone_ip after `setup`.

# --- locate brew tools ---
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi

PORT=5555
RES="${DEX_RES:-2240x1260}"
DPI="${DEX_DPI:-160}"
# Wireless-tuned streaming defaults (override via env). h265 = lighter bandwidth,
# video-buffer absorbs WiFi jitter, capped fps + moderate bitrate keep it stable.
CODEC="${DEX_CODEC:-h265}"
BITRATE="${DEX_BITRATE:-8M}"
MAXFPS="${DEX_MAXFPS:-60}"
BUFFER="${DEX_BUFFER:-50}"
AUDIO_FLAG="${DEX_AUDIO:---no-audio}"   # set DEX_AUDIO="" to keep audio
CFG_DIR="$HOME/.config-dex"
IP_FILE="$CFG_DIR/phone_ip"
mkdir -p "$CFG_DIR"

# adb and a local proxy (Surge/Clash etc.) fight over TCP routing; make adb bypass it.
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null || true
export no_proxy="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,localhost,127.0.0.1"

usb_serial() {
  adb devices | awk '$2=="device" && $1 !~ /:/ {print $1; exit}'
}

phone_ip_from_usb() {
  local s="$1"
  adb -s "$s" shell ip -f inet addr show wlan0 2>/dev/null \
    | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1
}

# Restart the adb server cleanly. A stale server caches "no route to host"
# after a proxy hiccup; a fresh start fixes wireless connects.
adb_reset() { adb kill-server >/dev/null 2>&1 || true; adb start-server >/dev/null 2>&1 || true; }

cmd_setup() {
  local s; s="$(usb_serial)"
  if [ -z "$s" ]; then
    echo "No USB device found. Plug the phone in (USB debugging authorized) and retry."
    exit 1
  fi
  local ip; ip="$(phone_ip_from_usb "$s")"
  if [ -z "$ip" ]; then echo "Couldn't read the phone's WiFi IP. Is WiFi on?"; exit 1; fi
  echo "Phone WiFi IP: $ip"
  echo "$ip" > "$IP_FILE"

  echo "Switching adb to TCP mode on port $PORT ..."
  adb -s "$s" tcpip "$PORT" >/dev/null 2>&1
  sleep 3
  adb_reset
  do_connect "$ip"
  echo "Done. You can unplug USB now. Reconnect later with: $0 connect"
}

do_connect() {
  local ip="$1"
  for i in 1 2 3 4 5; do
    if adb connect "${ip}:${PORT}" 2>&1 | grep -q "connected"; then
      echo "Connected to ${ip}:${PORT}"
      return 0
    fi
    adb_reset
    sleep 2
  done
  echo "Could not connect to ${ip}:${PORT}."
  echo "Checklist: phone + Mac on the same WiFi; phone awake; if you use Surge/Clash,"
  echo "add a DIRECT rule for ${ip} or the 192.168.* subnet."
  return 1
}

cmd_connect() {
  [ -f "$IP_FILE" ] || { echo "No saved IP. Run: $0 setup"; exit 1; }
  do_connect "$(cat "$IP_FILE")"
}

cmd_start() {
  cmd_connect
  echo "Launching DeX (${RES}/${DPI}, ${CODEC} ${BITRATE} ${MAXFPS}fps, buffer ${BUFFER}ms) ..."
  nohup scrcpy --new-display="${RES}/${DPI}" \
    --video-codec="${CODEC}" \
    --video-bit-rate="${BITRATE}" \
    --max-fps="${MAXFPS}" \
    --video-buffer="${BUFFER}" \
    ${AUDIO_FLAG} >/tmp/dex_scrcpy.log 2>&1 &
  disown
  echo "DeX starting. Log: /tmp/dex_scrcpy.log"
}

cmd_status() { adb devices -l; }

case "${1:-start}" in
  setup)   cmd_setup ;;
  connect) cmd_connect ;;
  start)   cmd_start ;;
  status)  cmd_status ;;
  *) echo "Usage: $0 {setup|connect|start|status}"; exit 1 ;;
esac
