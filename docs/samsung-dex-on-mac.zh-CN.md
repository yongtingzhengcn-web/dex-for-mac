---
title: "在 Mac 上运行三星 DeX：无需显示器，USB 或 WiFi 都行（One UI 8）"
description: "三星砍掉了 PC 版 DeX，但 One UI 8 可以把 DeX 跑在虚拟显示器上。本文教你用 scrcpy 把完整的三星 DeX 桌面搬进 Mac 窗口——不用外接显示器、不用 HDMI 线、不用假负载。"
tags: [Android, macOS, 三星, DeX, 效率工具]
---

# 在 Mac 上运行三星 DeX：无需显示器，USB 或 WiFi 都行（One UI 8）

三星悄悄下架了 Windows 和 Mac 上的官方 **Samsung DeX** 桌面客户端，有一段时间，想用 DeX
桌面就只能把手机插到真实显示器上。但 **One UI 8（Android 16）** 改变了这一点：新版 DeX 构建
在 Android 原生的桌面模式（Desktop Mode）之上，可以跑在**虚拟显示器**上——这意味着你能把完整
的 DeX 桌面直接塞进 Mac 的一个窗口里，只需要一根 USB 线，甚至只用 WiFi。

这篇教程会带你从零跑通，大约十分钟，全程使用免费开源工具，**不需要外接显示器、不需要 HDMI 线、
也不需要 HDMI 假负载（dummy plug）**。

> **太长不看** —— 装好 `scrcpy` + `adb`，手机开启 USB 调试，运行
> `scrcpy --new-display=1920x1080/160`，DeX 桌面就会出现在 Mac 窗口里。想要一键操作？
> 用菜单栏 App [DeXBar](https://github.com/yongtingzhengcn-web/dex-for-mac)。

## 需要准备什么

- 一台 **运行 One UI 8（Android 16）或更新版本的三星 Galaxy 手机/平板**。这是核心前提：老版本
  One UI 无法把 DeX 渲染到虚拟显示器上，这个方法在老系统上跑不起来。
- 一台 **Mac**（Apple 芯片或 Intel 都行），macOS 13 及以上。
- 一根 **USB 线**（至少首次要用；之后可以转无线）。
- [**Homebrew**](https://brew.sh)，macOS 的包管理器。

## 为什么现在能这么玩（原理）

以前 DeX 必须接实体 HDMI/DisplayPort，是因为 Android 只有检测到外接屏幕时才进入桌面模式。
Android 16 的桌面模式新增了对**虚拟显示器**的支持——这是一种纯软件的显示器。开源工具
[**scrcpy**](https://github.com/Genymobile/scrcpy)（4.1 及以上）可以按需创建一个这样的虚拟
显示器并投屏到电脑上。One UI 8 的 DeX 渲染到这个虚拟显示器上，你就能在 Mac 窗口里看到它，完全
不需要任何硬件障眼法。

## 第一步：安装 scrcpy 和 adb

打开**终端（Terminal）**，运行：

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

`scrcpy` 负责投屏；`adb`（Android 调试桥）是 Mac 与手机通信的通道。

## 第二步：在手机上开启 USB 调试

1. 进入 **设置 → 关于手机**，连续点击**版本号**七次，解锁开发者选项。
2. 进入 **设置 → 开发者选项**，打开 **USB 调试**。

## 第三步：连接并授权

用 USB 线把手机连到 Mac。手机上会弹出**允许 USB 调试**的提示——勾选"一律允许使用这台计算机"，
点**允许**。

确认 Mac 已识别手机：

```bash
adb devices
```

设备应显示为 `device`（而不是 `unauthorized`）。如果显示 `unauthorized`，点亮手机屏幕并确认
授权提示即可。

## 第四步：在 Mac 上启动三星 DeX

运行：

```bash
scrcpy --new-display=1920x1080/160
```

Mac 上会打开一个窗口，显示**完整的三星 DeX 桌面**——任务栏、可调整大小的窗口，一应俱全。用
Mac 的键盘和鼠标就能操作。

- `1920x1080` 是虚拟显示器分辨率，想要更大空间可以改成 `2560x1440`。
- `160` 是 DPI（显示密度）。**DPI 越低界面元素越小、可用空间越大；DPI 越高界面越大。**
  `160` 是接近桌面的默认值，可以在 `140`–`200` 之间按喜好微调。

搞定，你已经在 Mac 上跑起 DeX 了。

## 进阶：让 DeX 走 WiFi（彻底摆脱数据线）

USB 跑通后，只要手机和 Mac 在同一个 WiFi 下，就能转成无线。

```bash
# 手机仍插着 USB 时执行：
adb tcpip 5555
adb shell ip -f inet addr show wlan0     # 记下手机的 192.168.x.x 地址
# 然后就能拔线无线连了：
adb connect 192.168.x.x:5555
scrcpy --new-display=1920x1080/160
```

无线下想更流畅，给串流加上抗抖动的参数：

```bash
scrcpy --new-display=1920x1080/160 \
  --video-codec=h265 --video-bit-rate=8M --max-fps=60 --video-buffer=50 --no-audio
```

其中 `--video-buffer=50`（50 毫秒缓冲）是解决无线卡顿最有效的一项。

## 懒得敲命令？用 DeXBar 菜单栏 App

老是敲命令很烦。[**DeXBar**](https://github.com/yongtingzhengcn-web/dex-for-mac) 是一个免费
开源的 **macOS 菜单栏 App**，把上面这一切都封装好了：显示手机是否已连接、在菜单里选分辨率和
DPI、一键启停 DeX，而且检测到无线连接时会自动套用上面那套流畅度优化参数。日常使用它最省事。

## 常见问题排查

### `adb: device unauthorized`（未授权）
手机还没信任你的 Mac。点亮手机、留意**允许 USB 调试**弹窗，勾选"一律允许"并点允许。

### 无线连接报 `failed to connect: No route to host`
如果你在用 **Surge、Clash 等本地代理或 VPN**，它可能会劫持 adb 到手机的连接。先重启 adb
服务（`adb kill-server && adb start-server`），再在代理软件里给 `192.168.*` 网段加一条
**DIRECT（直连）** 规则。DeXBar 的无线脚本会自动对局域网地址绕过代理。

### 只显示 display-id 0 / DeX 不出现
确认手机确实是 **One UI 8（Android 16）**。老版本无法把 DeX 渲染到虚拟显示器，这个方法不生效。

### 有些 App 只在画面中间显示一个竖屏小窗
这是 App 自身的限制，不是配置问题。这类 App 在代码里锁死了竖屏方向、或声明了固定宽高比，DeX
只能给它加黑边居中。系统里能帮上忙的开关（`force_resizable_activities`、忽略方向请求）在 DeX
里其实默认已经开着；那些压根没做横屏布局的 App，是无法被干净地强制铺满的。

### DeX 窗口感觉卡
调低分辨率；无线的话加上 `--video-buffer=50` 并用 `--video-codec=h265` 降低带宽占用。网络较
差时把缓冲加大到 `100`–`150`。

## FAQ

**不是 One UI 8 能用吗？**
不能。虚拟显示器版的 DeX 是 One UI 8 / Android 16 才有的特性，老版本做不到。

**需要外接显示器或 HDMI 假负载吗？**
不需要。那是过去的老办法，虚拟显示器方案两样都不用。

**Apple 芯片的 Mac 能用吗？**
能。`scrcpy` 和 `adb` 都原生支持 M 系列芯片。

**免费吗？**
免费。`scrcpy`、`adb` 和 DeXBar 全部免费开源。

**能用 Mac 的键盘鼠标操作 DeX 吗？**
可以。scrcpy 会转发键鼠输入，还支持剪贴板共享。

**Pixel 或其他非三星手机能用吗？**
这个虚拟显示器的玩法是三星在 One UI 8 上实现 DeX 的特有方式。原生 Android 在 Pixel 上的桌面
模式目前仍然需要接实体外接显示器。

## 写在最后

三星虽然砍掉了 PC 版 DeX，但靠着 One UI 8 的虚拟显示器和 scrcpy，现在**在 Mac 上运行三星
DeX**比用官方工具时还要简单——不用显示器、不用转接头，还能走 WiFi。想要一键体验，去 GitHub
拿 **DeXBar**，觉得有用点个 Star，也欢迎告诉我你在哪些 One UI 8 机型上跑通了：

👉 **https://github.com/yongtingzhengcn-web/dex-for-mac**
