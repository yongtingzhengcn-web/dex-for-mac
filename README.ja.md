# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · **日本語** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

Mac で Samsung DeX を動かす — モニター不要、HDMI ダミープラグ不要、Miracast 不要。

Samsung は公式の PC 版 DeX を終了しましたが、One UI 8（Android 16）は DeX を Android ネイティブの
デスクトップモードの上に作り直しました。このモードは**仮想ディスプレイ**に対応しています。
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ はそうした仮想ディスプレイを直接作成できるため、
DeX デスクトップ全体が Mac のウィンドウにそのまま表示されます — USB ケーブル 1 本だけで。

## 必要なもの

- macOS 13+
- **One UI 8 以降**（Android 16+）を搭載した Samsung Galaxy スマホ/タブレット
- USB ケーブル
- [Homebrew](https://brew.sh)

## 2 つの使い方

### 方法 A — DeXBar メニューバーアプリ（推奨）

ネイティブのメニューバーアプリ：解像度/DPI の選択、スマホの接続状態の確認、DeX の開始/停止 —
すべてメニューバーから、ターミナル不要。

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # 任意: cp -R build/DeXBar.app /Applications/
```

`scrcpy` + `adb` が必要です（なければアプリがインストールコマンドを表示します）：

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

メニューバーのディスプレイアイコンをクリック：

- **ステータス行** — 接続中のデバイス名を表示、または USB デバッグ未承認 / デバイス未接続を警告。
- **DeX 開始 / 停止** — scrcpy の仮想ディスプレイセッションを開始・終了します。
- **解像度 / DPI** — プリセットから選択、選択内容は記憶されます。
- **ログを開く** — `~/Library/Logs/DeXBar.log` を開きます。

設定は再起動後も保持されます。アプリはメニューバー専用で動作します（Dock アイコンなし）。

### 方法 B — install.sh（ターミナルのエイリアス + デスクトップランチャー）

GUI が不要なら、このスクリプトがツールをインストールし、`dex` コマンドと、固定の解像度/DPI で
ダブルクリック起動できる `DeX.app` をデスクトップに作成します。

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

必要なら `scrcpy`/`adb` をインストールし、解像度 + DPI（既定 `1920x1080` / `160`）を尋ね、`~/.zshrc`
に `dex` エイリアスを追加し、`~/Desktop/DeX.app` を作成します。

## スマホの初回設定

1. スマホで：**設定 → 端末情報 →** **ビルド番号**を 7 回タップして開発者向けオプションを解除。
2. **設定 → 開発者向けオプション →** **USB デバッグ**をオンにします。
3. USB でスマホを Mac に接続し、デバッグ許可のプロンプトを承認します。

その後 DeXBar から DeX を開始（または `dex` を実行）。DeX デスクトップが Mac のウィンドウに開きます。

## ワイヤレス（ケーブルなし）

DeX は USB の代わりに WiFi でも動きます。USB で一度だけ初期設定すれば、スマホと Mac が同じ WiFi に
いる限りケーブルなしで使えます。

```bash
# 1) 一度きりの設定：スマホを USB 接続した状態（デバッグ承認済み）
./wireless.sh setup      # adb を WiFi に切り替え、スマホの IP を保存してからケーブルを抜く

# 2) 以降いつでも：再接続して DeX を起動、ケーブル不要
./wireless.sh start      # または: ./wireless.sh connect（再接続のみ）
```

スマホが無線で接続されると、**DeXBar の「DeX 開始」も WiFi で動作します** — アプリは `adb` が
認識するデバイスをそのまま使い、WiFi 向けに調整したストリーミング設定を自動適用します（下記参照）。

### WiFi でのなめらかさ

WiFi は帯域の変動とジッターがあるため、`wireless.sh start` と DeXBar（デバイスが無線のとき）は
調整済みのフラグで scrcpy を起動します：

| フラグ | 理由 |
|------|------|
| `--video-codec=h265` | 圧縮率が高い → 帯域を節約 → フレーム落ちを軽減 |
| `--video-buffer=50` | 小さなバッファでネットワークのジッターを吸収 — カクつき対策の要（約 50ms の遅延）|
| `--max-fps=60` | キャプチャのフレームレートを制限してペースを安定化 |
| `--video-bit-rate=8M` | 鮮明なデスクトップに十分で、WiFi を飽和させない |
| `--no-audio` | 音声転送のオーバーヘッドを削減 |

`wireless.sh` では各値を環境変数で上書きできます。例：音声を残し、不安定なネットワークでバッファを
増やす：

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

USB 起動はリンクがすでに安定しているため、軽量なまま（バッファ/遅延を追加しません）。

メモ：
- スマホは同じ WiFi にいる必要があります。**スマホの再起動**後は TCP モードがリセットされるため、
  USB で再度 `./wireless.sh setup` を実行してください。
- ローカルのプロキシ/VPN（**Surge、Clash など**）を使っていると、adb の接続を横取りして
  `failed to connect: No route to host` になることがあります。`wireless.sh` は LAN アドレスに対して
  プロキシを自動的にバイパスします。それでも起きる場合は、プロキシアプリで `192.168.*` サブネットに
  **DIRECT** ルールを追加してください。

## 解像度 / DPI の調整

同じ解像度なら、**低い DPI** は UI 要素を小さくしてより多くを表示し、**高い DPI** はすべてを大きく
します。`1920x1080/160` はデスクトップに近い妥当な既定値です。DeXBar ではメニューから選ぶだけ。
`install.sh` の場合は再実行するか、`~/.zshrc` の `dex` エイリアスにある
`--new-display=WIDTHxHEIGHT/DPI` の値を編集してください。

## 仕組み

```bash
scrcpy --new-display=1920x1080/160
```

この 1 コマンドが指定の解像度/密度でスマホに新しい仮想ディスプレイを作成し、One UI 8 の
デスクトップモード（DeX）をそこに描画させ、そのディスプレイを USB（または無線 adb）で Mac の
ウィンドウにミラーリングします。DeXBar はこのコマンドとステータス確認用の `adb devices` を包んだ
薄いネイティブラッパーです。

## ライセンス

MIT
