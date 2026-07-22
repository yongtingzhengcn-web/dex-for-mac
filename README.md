# dex-for-mac

Run Samsung DeX on your Mac — no monitor, no HDMI dummy plug, no Miracast.

Samsung dropped official DeX-on-PC support, but One UI 8 (Android 16) rebuilt DeX
on top of Android's native Desktop Mode, which supports **virtual displays**.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ can create one of those virtual
displays directly, so the whole DeX desktop shows up in a window on your Mac —
just from a USB cable.

## Requirements

- macOS
- A Samsung Galaxy phone/tablet running **One UI 8 or later** (Android 16+)
- USB cable
- [Homebrew](https://brew.sh)

## Install

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

The installer will:

1. Install `scrcpy` and `adb` (`android-platform-tools`) via Homebrew if missing
2. Ask for your preferred virtual display resolution and DPI (defaults: `1920x1080` / `160`)
3. Add a `dex` alias to your `~/.zshrc`
4. Create a double-clickable `DeX.app` on your Desktop

## Use it

1. Enable **Developer options → USB debugging** on your phone, connect it to your Mac via USB, and approve the debugging prompt.
2. Either double-click `DeX.app` on your Desktop, or open a new terminal and run:
   ```bash
   dex
   ```
3. The DeX desktop opens in a window on your Mac.

## Tuning resolution / DPI

Re-run `./install.sh` any time to change resolution/DPI, or edit the `--new-display=WIDTHxHEIGHT/DPI`
value directly in the `dex` alias (`~/.zshrc`) and in `DeX.app` (rebuild it with `osacompile`).

Lower DPI at a given resolution packs more content on screen with smaller UI elements;
higher DPI makes UI elements larger. `1920x1080/160` is a reasonable desktop-like default.

## How it works

```bash
scrcpy --new-display=1920x1080/160
```

This one command creates a new virtual display on the phone at the given resolution/density,
which triggers One UI 8's Desktop Mode (DeX) to render onto it, and mirrors that display to a
window on your Mac via USB (or wireless adb).

## License

MIT
