# dex-for-mac

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

## License

MIT
