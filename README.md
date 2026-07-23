# dex-for-mac

**English** · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

Run Samsung DeX on your Mac — no monitor, no HDMI dummy plug, no Miracast.

Samsung dropped official DeX-on-PC support, but One UI 8 (Android 16) rebuilt DeX
on top of Android's native Desktop Mode, which supports **virtual displays**.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ can create one of those virtual
displays directly, so the whole DeX desktop shows up in a window on your Mac —
just from a USB cable.

## Requirements

- macOS 13+
- A Samsung Galaxy phone/tablet running **One UI 8 or later** (Android 16+)
- USB cable
- [Homebrew](https://brew.sh)

## Two ways to use it

### Option A — DeXBar menu-bar app (recommended)

A native menu-bar app: pick resolution/DPI, see whether your phone is connected,
and start/stop DeX — all from the menu bar, no terminal.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # optionally: cp -R build/DeXBar.app /Applications/
```

Requires `scrcpy` + `adb` (the app tells you the install command if they're missing):

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Click the display icon in the menu bar:

- **Status line** — shows the connected device model, or a warning if USB debugging
  isn't authorized / no device is connected.
- **Start / Stop DeX** — launches or kills the scrcpy virtual-display session.
- **Resolution** / **DPI** — pick from presets; your choice is remembered.
- **Open Log** — opens `~/Library/Logs/DeXBar.log`.

Settings persist across restarts. The app runs menu-bar-only (no Dock icon).

### Option B — install.sh (terminal alias + Desktop launcher)

If you prefer no GUI, this installs the tools and sets up a `dex` command plus a
double-clickable `DeX.app` on your Desktop at a fixed resolution/DPI.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

It installs `scrcpy`/`adb` if missing, asks for resolution + DPI (defaults
`1920x1080` / `160`), adds a `dex` alias to `~/.zshrc`, and builds `~/Desktop/DeX.app`.

## First-time phone setup

1. On the phone: **Settings → About phone →** tap **Build number** 7× to unlock
   Developer options.
2. **Settings → Developer options →** turn on **USB debugging**.
3. Connect the phone to your Mac by USB and approve the debugging prompt.

Then start DeX from DeXBar (or run `dex`). The DeX desktop opens in a window on your Mac.

## Wireless (no cable)

DeX can run over WiFi instead of USB. You bootstrap once over USB, then go cable-free
as long as the phone and Mac share a WiFi network.

```bash
# 1) One-time setup: phone plugged in via USB (debugging authorized)
./wireless.sh setup      # switches adb to WiFi, saves the phone IP, then you unplug

# 2) Any time after: reconnect and launch DeX, no cable
./wireless.sh start      # or: ./wireless.sh connect   (just reconnect)
```

Once the phone is connected wirelessly, **DeXBar's Start DeX works over WiFi too** —
the app just uses whatever device `adb` sees, and automatically applies WiFi-tuned
streaming settings (see below).

### Smoothness over WiFi

WiFi adds bandwidth variance and jitter, so both `wireless.sh start` and DeXBar
(when the device is wireless) launch scrcpy with tuned flags:

| Flag | Why |
|------|-----|
| `--video-codec=h265` | Better compression → less bandwidth → fewer dropped frames |
| `--video-buffer=50` | Small buffer absorbs network jitter — the main stutter fix (≈50 ms latency) |
| `--max-fps=60` | Caps capture rate for steady pacing |
| `--video-bit-rate=8M` | Enough for a crisp desktop without saturating WiFi |
| `--no-audio` | Drops audio-forwarding overhead |

Override any of them for `wireless.sh` via env vars, e.g. keep audio and raise the
buffer on a flaky network:

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

USB launches stay lean (no buffer/latency added) since the link is already stable.

Notes:
- The phone must stay on the same WiFi. After a **phone reboot**, TCP mode resets —
  run `./wireless.sh setup` again with USB.
- If you run a local proxy/VPN (**Surge, Clash, etc.**), it can hijack adb's connection
  and cause `failed to connect: No route to host`. `wireless.sh` bypasses the proxy for
  LAN addresses automatically; if you still hit it, add a **DIRECT** rule for your
  `192.168.*` subnet in the proxy app.

## Tuning resolution / DPI

At a given resolution, **lower DPI** packs more content on screen with smaller UI
elements; **higher DPI** makes everything larger. `1920x1080/160` is a reasonable
desktop-like default. In DeXBar, just pick from the menus. For `install.sh`, re-run it
or edit the `--new-display=WIDTHxHEIGHT/DPI` value in the `dex` alias (`~/.zshrc`).

## How it works

```bash
scrcpy --new-display=1920x1080/160
```

This one command creates a new virtual display on the phone at the given
resolution/density, which triggers One UI 8's Desktop Mode (DeX) to render onto it,
and mirrors that display to a window on your Mac over USB (or wireless adb). DeXBar is
a thin native wrapper around exactly this command plus `adb devices` for status.

## Support

If this saved you some hassle, you can [buy me a coffee via PayPal](https://paypal.me/yongtingzheng741) ☕ — thanks!

## License

MIT
