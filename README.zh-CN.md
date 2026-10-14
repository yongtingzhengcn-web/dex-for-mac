# dex-for-mac

[English](README.md) · **简体中文** · [한국어](README.ko.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

在 Mac 上运行三星 DeX —— 无需显示器、无需 HDMI 假负载、无需 Miracast。

三星取消了官方的 PC 版 DeX，但 One UI 8（Android 16）把 DeX 重构在了 Android 原生的桌面模式
之上，而桌面模式支持**虚拟显示器**。[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ 可以
直接创建这样一个虚拟显示器，于是完整的 DeX 桌面就出现在你 Mac 的一个窗口里 —— 只需一根 USB 线。

## 环境要求

- macOS 13+
- 一台运行 **One UI 8 或更新版本**（Android 16+）的三星 Galaxy 手机/平板
- USB 数据线
- [Homebrew](https://brew.sh)

## 两种使用方式

### 方式 A —— DeXBar 菜单栏 App（推荐）

一个原生菜单栏 App：选分辨率/DPI、查看手机是否已连接、启停 DeX —— 全在菜单栏完成，无需终端。

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # 可选：cp -R build/DeXBar.app /Applications/
```

需要 `scrcpy` + `adb`（缺失时 App 会提示安装命令）：

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

点击菜单栏的显示器图标：

- **状态行** —— 显示已连接的设备型号，或在未授权 USB 调试 / 无设备时给出提示。
- **启动 / 停止 DeX** —— 开启或关闭 scrcpy 虚拟显示会话。
- **分辨率 / DPI** —— 从预设中选择，选择会被记住。
- **打开日志** —— 打开 `~/Library/Logs/DeXBar.log`。

设置在重启后保留。App 仅在菜单栏运行（无程序坞图标）。

### 方式 B —— install.sh（终端别名 + 桌面启动器）

如果你不想用图形界面，这个脚本会装好工具，并设置一个 `dex` 命令，外加在桌面生成一个固定
分辨率/DPI、可双击的 `DeX.app`。

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

它会在缺失时安装 `scrcpy`/`adb`，询问分辨率 + DPI（默认 `1920x1080` / `160`），向 `~/.zshrc`
添加 `dex` 别名，并生成 `~/Desktop/DeX.app`。

## 手机首次设置

1. 手机上：**设置 → 关于手机 →** 连点**版本号** 7 次以解锁开发者选项。
2. **设置 → 开发者选项 →** 打开 **USB 调试**。
3. 用 USB 把手机连到 Mac 并确认调试授权。

然后从 DeXBar 启动 DeX（或运行 `dex`），DeX 桌面就会出现在 Mac 的窗口里。

## 无线（免数据线）

DeX 也能走 WiFi 而不是 USB。首次用 USB 引导一次，之后只要手机和 Mac 在同一个 WiFi 下就能免线使用。

```bash
# 1）一次性设置：手机通过 USB 插着（已授权调试）
./wireless.sh setup      # 把 adb 切到 WiFi，保存手机 IP，然后你拔线

# 2）之后任意时候：重连并启动 DeX，无需数据线
./wireless.sh start      # 或：./wireless.sh connect（仅重连）
```

一旦手机无线连上，**DeXBar 的"启动 DeX"也会走 WiFi** —— App 用的就是 `adb` 能看到的设备，并
自动套用 WiFi 优化的串流参数（见下文）。

### WiFi 下的流畅度

WiFi 有带宽波动和抖动，因此 `wireless.sh start` 和 DeXBar（设备为无线时）都会用调优过的参数启动 scrcpy：

| 参数 | 作用 |
|------|------|
| `--video-codec=h265` | 压缩率更高 → 带宽更省 → 更少丢帧 |
| `--video-buffer=50` | 小缓冲吸收网络抖动 —— 解决卡顿的关键（约 50 毫秒延迟）|
| `--max-fps=60` | 限制采集帧率，节奏更稳 |
| `--video-bit-rate=8M` | 清晰桌面够用，又不塞满 WiFi |
| `--no-audio` | 省掉音频转发开销 |

`wireless.sh` 的这些参数都能用环境变量覆盖，例如保留音频并在不稳的网络下加大缓冲：

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

USB 启动保持精简（不加缓冲/延迟），因为链路本身已经稳定。

注意：
- 手机必须保持在同一 WiFi。手机**重启后** TCP 模式会失效 —— 需再插 USB 运行一次 `./wireless.sh setup`。
- 如果你使用本地代理/VPN（**Surge、Clash 等**），它可能劫持 adb 到手机的连接，导致
  `failed to connect: No route to host`。`wireless.sh` 会自动对局域网地址绕过代理；若仍出现，
  在代理软件里给 `192.168.*` 网段加一条 **DIRECT（直连）** 规则。

## 调整分辨率 / DPI

同一分辨率下，**DPI 越低**界面元素越小、能显示的内容越多；**DPI 越高**则一切越大。`1920x1080/160`
是接近桌面的合理默认值。在 DeXBar 里直接从菜单选即可。用 `install.sh` 时，重新运行它，或编辑
`~/.zshrc` 里 `dex` 别名的 `--new-display=宽x高/DPI` 数值。

## One UI 8.5 说明

在 **One UI 8.5** 上，`scrcpy --new-display` 已无法启动完整的 DeX——得到的只是安卓原生桌面模式
（应用全屏打开、没有窗口标题栏、无法多窗口）。本项目通过创建带 `hdmi` 标记的
[overlay 显示器](https://github.com/yongtingzhengcn-web/dex-for-mac/issues/1)
（`settings put global overlay_display_devices "宽x高/DPI,hdmi"`）绕过：One UI 会把它当作
外接显示器，从而启动完整的 DeX，然后 scrcpy 按 display id 连接这个显示器。

无需手动操作：**DeXBar** 和 **wireless.sh** 会自动检测 One UI 版本并选择正确的路径。在 DeXBar 里
也可以通过 *Display mode* 菜单手动强制 `Virtual display (One UI 8.0)` 或 `Overlay display (One UI 8.5+)`。

## 工作原理

```bash
scrcpy --new-display=1920x1080/160          # One UI 8.0
# 在 One UI 8.5+ 上：
adb shell settings put global overlay_display_devices "1920x1080/160,hdmi"
scrcpy --display-id=<从 dumpsys display 获取的 id>
```

第一条命令在手机上按给定分辨率/密度创建一个新的虚拟显示器，触发 One UI 8 的桌面模式（DeX）
渲染到它上面，再通过 USB（或无线 adb）把这个显示器投到 Mac 的一个窗口里。DeXBar 就是围绕这些
命令、外加 `adb devices` 状态检测的一层轻量原生封装。

## 许可证

MIT
