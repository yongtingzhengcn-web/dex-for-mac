---
title: "How to Run Samsung DeX on a Mac (One UI 8, No Monitor Needed)"
published: false
description: "Samsung killed the DeX desktop app, but One UI 8 runs DeX on a virtual display. Here's how to get the full Samsung DeX desktop in a window on your Mac — over USB or WiFi, no external monitor or HDMI dummy plug."
tags: android, macos, samsung, productivity
canonical_url: ""
cover_image: ""
---

# How to Run Samsung DeX on a Mac (One UI 8, No Monitor Needed)

Samsung quietly discontinued the official **Samsung DeX** app for Windows and Mac, and for
a while the only way to get the DeX desktop was to plug your Galaxy phone into a real
monitor. That changed with **One UI 8 (Android 16)**: DeX is now built on Android's native
Desktop Mode, which can run on a **virtual display** — and that means you can put the whole
DeX desktop in a window on your Mac, with nothing but a USB cable (or even just WiFi).

This guide shows you how, start to finish. It takes about ten minutes, uses only free and
open-source tools, and needs **no external monitor, no HDMI cable, and no HDMI dummy plug**.

> **TL;DR** — Install `scrcpy` + `adb`, enable USB debugging on your Galaxy phone, and run
> `scrcpy --new-display=1920x1080/160`. The DeX desktop opens in a Mac window. Prefer a
> one-click menu-bar app? Use [DeXBar](https://github.com/yongtingzhengcn-web/dex-for-mac).

## What you need

- A **Samsung Galaxy phone or tablet running One UI 8 (Android 16) or newer**. This is the
  key requirement — older One UI versions can't render DeX on a virtual display, so this
  method simply won't work on them.
- A **Mac** (Apple Silicon or Intel), macOS 13 or later.
- A **USB cable** (used at least once; wireless is possible afterward).
- [**Homebrew**](https://brew.sh), the macOS package manager.

## Why this works now (the short version)

DeX used to require a physical HDMI/DisplayPort connection because Android only entered
desktop mode when it detected an external screen. Android 16's Desktop Mode added support
for **virtual displays** — displays that exist only in software. The open-source tool
[**scrcpy**](https://github.com/Genymobile/scrcpy) (v4.1+) can create one of these virtual
displays on demand and mirror it to your computer. One UI 8's DeX renders onto that virtual
display, and you see it in a window on your Mac. No hardware trickery required.

## Step 1 — Install scrcpy and adb

Open **Terminal** and run:

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

`scrcpy` does the mirroring; `adb` (Android Debug Bridge) is how your Mac talks to the phone.

## Step 2 — Enable USB debugging on your phone

1. Go to **Settings → About phone** and tap **Build number** seven times to unlock
   Developer options.
2. Go to **Settings → Developer options** and turn on **USB debugging**.

## Step 3 — Connect and authorize

Plug the phone into your Mac with the USB cable. A prompt appears on the phone asking to
**Allow USB debugging** — check "Always allow from this computer" and tap **Allow**.

Confirm your Mac sees the phone:

```bash
adb devices
```

You should see your device listed as `device` (not `unauthorized`). If it says
`unauthorized`, unlock the phone and approve the prompt.

## Step 4 — Launch Samsung DeX on your Mac

Run:

```bash
scrcpy --new-display=1920x1080/160
```

A window opens on your Mac showing the **full Samsung DeX desktop** — taskbar, resizable
windows, and all. Control it with your Mac's keyboard and mouse.

- `1920x1080` is the virtual display resolution. Bump it to `2560x1440` for more space.
- `160` is the DPI (density). **Lower DPI = smaller UI, more room; higher DPI = bigger UI.**
  `160` is a good desktop-like default; try `140`–`200` to taste.

That's it — you're running DeX on your Mac.

## Optional: run DeX over WiFi (no cable)

Once it works over USB, you can go wireless as long as the phone and Mac are on the same
WiFi network.

```bash
# With the phone still on USB:
adb tcpip 5555
adb shell ip -f inet addr show wlan0     # note the phone's 192.168.x.x address
# Then, cable-free:
adb connect 192.168.x.x:5555
scrcpy --new-display=1920x1080/160
```

For smoother playback over WiFi, tune the stream to absorb network jitter:

```bash
scrcpy --new-display=1920x1080/160 \
  --video-codec=h265 --video-bit-rate=8M --max-fps=60 --video-buffer=50 --no-audio
```

The `--video-buffer=50` (a 50 ms buffer) is the single biggest fix for wireless stutter.

## Prefer a one-click app? Use DeXBar

Typing commands gets old. [**DeXBar**](https://github.com/yongtingzhengcn-web/dex-for-mac)
is a free, open-source **macOS menu-bar app** that wraps all of the above: it shows whether
your phone is connected, lets you pick resolution and DPI from a menu, starts and stops DeX
with one click, and automatically applies the WiFi smoothness settings when you're wireless.
It's the easiest way to use this day to day.

## Troubleshooting

### "adb: device unauthorized"
The phone hasn't trusted your Mac yet. Unlock it, watch for the **Allow USB debugging**
prompt, and tap Allow (check "always allow").

### `failed to connect: No route to host` (wireless)
If you run a **local proxy or VPN like Surge or Clash**, it can hijack adb's connection to
the phone. Restart the adb server (`adb kill-server && adb start-server`) and add a
**DIRECT** rule for your `192.168.*` subnet in the proxy app. DeXBar's wireless script
bypasses the proxy for LAN addresses automatically.

### Only display-id 0 shows / DeX doesn't appear
Make sure your phone is actually on **One UI 8 (Android 16)**. On older versions, DeX cannot
render to a virtual display and this method won't work.

### Some apps only show a small portrait window in the middle
That's an app limitation, not a setup problem. Those apps hard-lock portrait orientation or
declare a fixed aspect ratio in their code, so DeX letterboxes them. The system toggles that
could help (`force_resizable_activities`, ignore-orientation-request) are already on in DeX;
apps with no landscape layout simply can't be forced to fill the screen cleanly.

### The DeX window feels laggy
Lower the resolution, or over WiFi add `--video-buffer=50` and use `--video-codec=h265` to
cut bandwidth. On a weak network, raise the buffer to `100`–`150`.

## FAQ

**Does this work without One UI 8?**
No. Virtual-display DeX is a One UI 8 / Android 16 feature. Older One UI versions can't do it.

**Do I need an external monitor or HDMI dummy plug?**
No. That was the old workaround. The virtual-display method needs neither.

**Does it work on Apple Silicon Macs?**
Yes — `scrcpy` and `adb` both run natively on M-series Macs.

**Is it free?**
Yes. `scrcpy`, `adb`, and DeXBar are all free and open-source.

**Can I use my Mac keyboard and mouse in DeX?**
Yes. scrcpy forwards keyboard and mouse input, and supports clipboard sharing.

**Will this work on a Pixel or other non-Samsung phone?**
The virtual-display trick is specific to how Samsung ships DeX on One UI 8. Stock Android's
Desktop Mode on Pixels currently still expects a physical external display.

## Wrapping up

Samsung may have dropped the desktop DeX app, but thanks to One UI 8's virtual displays and
scrcpy, running **Samsung DeX on a Mac** is easier than it ever was with the official tool —
no monitor, no adapters, and it works over WiFi. If you want the one-click experience, grab
**DeXBar** on GitHub, star it if it helped, and let me know which One UI 8 devices you get it
working on:

👉 **https://github.com/yongtingzhengcn-web/dex-for-mac**
