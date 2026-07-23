# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · **한국어** · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

Mac에서 삼성 DeX 실행 — 모니터, HDMI 더미 플러그, Miracast 모두 필요 없음.

삼성은 공식 PC용 DeX 지원을 중단했지만, One UI 8(Android 16)은 DeX를 Android 기본 데스크톱
모드 위에 재구축했고 이 모드는 **가상 디스플레이**를 지원합니다.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ 는 그런 가상 디스플레이를 직접 만들 수
있어서, 전체 DeX 데스크톱이 Mac의 창 하나에 그대로 나타납니다 — USB 케이블 하나면 됩니다.

## 요구 사항

- macOS 13+
- **One UI 8 이상**(Android 16+)을 실행하는 삼성 Galaxy 폰/태블릿
- USB 케이블
- [Homebrew](https://brew.sh)

## 사용하는 두 가지 방법

### 방법 A — DeXBar 메뉴 막대 앱 (권장)

네이티브 메뉴 막대 앱: 해상도/DPI 선택, 폰 연결 여부 확인, DeX 시작/중지 — 모두 메뉴 막대에서,
터미널 없이.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # 선택: cp -R build/DeXBar.app /Applications/
```

`scrcpy` + `adb` 가 필요합니다 (없으면 앱이 설치 명령을 알려줍니다):

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

메뉴 막대의 디스플레이 아이콘을 클릭하세요:

- **상태 줄** — 연결된 기기 모델을 표시하거나, USB 디버깅 미승인 / 기기 없음을 경고합니다.
- **DeX 시작 / 중지** — scrcpy 가상 디스플레이 세션을 시작하거나 종료합니다.
- **해상도 / DPI** — 프리셋에서 선택하며, 선택은 기억됩니다.
- **로그 열기** — `~/Library/Logs/DeXBar.log` 를 엽니다.

설정은 재시작 후에도 유지됩니다. 앱은 메뉴 막대 전용으로 실행됩니다 (Dock 아이콘 없음).

### 방법 B — install.sh (터미널 별칭 + 데스크톱 실행기)

GUI를 원치 않으면, 이 스크립트가 도구를 설치하고 `dex` 명령과 고정 해상도/DPI로 더블클릭 가능한
`DeX.app` 을 데스크톱에 만들어 줍니다.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

없으면 `scrcpy`/`adb` 를 설치하고, 해상도 + DPI(기본 `1920x1080` / `160`)를 묻고, `~/.zshrc` 에
`dex` 별칭을 추가하고, `~/Desktop/DeX.app` 을 만듭니다.

## 폰 최초 설정

1. 폰에서: **설정 → 휴대전화 정보 →** **빌드 번호**를 7번 눌러 개발자 옵션을 해제합니다.
2. **설정 → 개발자 옵션 →** **USB 디버깅**을 켭니다.
3. USB로 폰을 Mac에 연결하고 디버깅 승인 팝업을 허용합니다.

그런 다음 DeXBar에서 DeX를 시작하거나 `dex` 를 실행하세요. DeX 데스크톱이 Mac의 창에 열립니다.

## 무선 (케이블 없이)

DeX는 USB 대신 WiFi로도 실행할 수 있습니다. USB로 한 번만 초기 설정하면, 폰과 Mac이 같은 WiFi에
있는 한 케이블 없이 사용할 수 있습니다.

```bash
# 1) 일회성 설정: 폰을 USB로 연결한 상태(디버깅 승인됨)
./wireless.sh setup      # adb를 WiFi로 전환하고 폰 IP를 저장한 뒤 케이블을 뽑습니다

# 2) 이후 언제든: 재연결 후 DeX 실행, 케이블 불필요
./wireless.sh start      # 또는: ./wireless.sh connect (재연결만)
```

폰이 무선으로 연결되면 **DeXBar의 "DeX 시작"도 WiFi로 동작합니다** — 앱은 `adb` 가 보는 기기를
그대로 사용하며, WiFi에 맞춘 스트리밍 설정을 자동 적용합니다(아래 참고).

### WiFi에서의 부드러움

WiFi는 대역폭 변동과 지터가 있어서, `wireless.sh start` 와 DeXBar(기기가 무선일 때)는 조정된
플래그로 scrcpy를 실행합니다:

| 플래그 | 이유 |
|------|------|
| `--video-codec=h265` | 압축률 향상 → 대역폭 절감 → 프레임 손실 감소 |
| `--video-buffer=50` | 작은 버퍼로 네트워크 지터 흡수 — 끊김 해결의 핵심(약 50ms 지연)|
| `--max-fps=60` | 캡처 프레임 레이트를 제한해 페이싱 안정화 |
| `--video-bit-rate=8M` | 선명한 데스크톱에 충분하면서 WiFi를 포화시키지 않음 |
| `--no-audio` | 오디오 전달 오버헤드 제거 |

`wireless.sh` 는 환경 변수로 각 값을 덮어쓸 수 있습니다. 예: 오디오를 유지하고 불안정한
네트워크에서 버퍼를 늘리기:

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

USB 실행은 링크가 이미 안정적이므로 가볍게 유지됩니다(버퍼/지연 추가 없음).

참고:
- 폰은 같은 WiFi에 있어야 합니다. **폰 재부팅** 후에는 TCP 모드가 초기화되므로 USB로 다시
  `./wireless.sh setup` 을 실행하세요.
- 로컬 프록시/VPN(**Surge, Clash 등**)을 사용하면 adb의 연결을 가로채
  `failed to connect: No route to host` 가 발생할 수 있습니다. `wireless.sh` 는 LAN 주소에 대해
  프록시를 자동 우회합니다. 그래도 발생하면 프록시 앱에서 `192.168.*` 서브넷에 **DIRECT** 규칙을
  추가하세요.

## 해상도 / DPI 조정

같은 해상도에서 **낮은 DPI**는 UI 요소를 작게 만들어 더 많은 내용을 표시하고, **높은 DPI**는 모든
것을 크게 만듭니다. `1920x1080/160` 이 데스크톱에 가까운 합리적 기본값입니다. DeXBar에서는 메뉴에서
고르면 됩니다. `install.sh` 는 다시 실행하거나 `~/.zshrc` 의 `dex` 별칭에서
`--new-display=WIDTHxHEIGHT/DPI` 값을 편집하세요.

## 작동 원리

```bash
scrcpy --new-display=1920x1080/160
```

이 한 줄이 지정된 해상도/밀도로 폰에 새 가상 디스플레이를 만들고, One UI 8의 데스크톱 모드(DeX)가
거기에 렌더링되도록 하며, 그 디스플레이를 USB(또는 무선 adb)로 Mac의 창에 미러링합니다. DeXBar는
바로 이 명령과 상태 확인용 `adb devices` 를 감싼 얇은 네이티브 래퍼입니다.

## 라이선스

MIT
