# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · **Deutsch** · [Português](README.pt.md)

Samsung DeX auf dem Mac ausführen — ohne Monitor, ohne HDMI-Dummy-Stecker, ohne Miracast.

Samsung hat die offizielle DeX-Unterstützung für den PC eingestellt, doch One UI 8 (Android 16)
hat DeX auf Androids nativem Desktop-Modus neu aufgebaut, der **virtuelle Displays** unterstützt.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ kann ein solches virtuelles Display direkt
erstellen, sodass der komplette DeX-Desktop in einem Fenster auf deinem Mac erscheint — allein
per USB-Kabel.

## Voraussetzungen

- macOS 13+
- Ein Samsung-Galaxy-Handy/-Tablet mit **One UI 8 oder neuer** (Android 16+)
- USB-Kabel
- [Homebrew](https://brew.sh)

## Zwei Möglichkeiten der Nutzung

### Option A — DeXBar Menüleisten-App (empfohlen)

Eine native Menüleisten-App: Auflösung/DPI wählen, sehen, ob das Handy verbunden ist, und DeX
starten/stoppen — alles aus der Menüleiste, ohne Terminal.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # optional: cp -R build/DeXBar.app /Applications/
```

Benötigt `scrcpy` + `adb` (die App nennt dir den Installationsbefehl, falls sie fehlen):

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Klicke auf das Display-Symbol in der Menüleiste:

- **Statuszeile** — zeigt das Modell des verbundenen Geräts an oder warnt, wenn das USB-Debugging
  nicht autorisiert ist / kein Gerät verbunden ist.
- **DeX starten / stoppen** — startet oder beendet die scrcpy-Sitzung mit virtuellem Display.
- **Auflösung / DPI** — aus Voreinstellungen wählen; deine Wahl wird gemerkt.
- **Protokoll öffnen** — öffnet `~/Library/Logs/DeXBar.log`.

Einstellungen bleiben über Neustarts hinweg erhalten. Die App läuft nur in der Menüleiste (kein
Dock-Symbol).

### Option B — install.sh (Terminal-Alias + Desktop-Starter)

Wenn du keine GUI möchtest, installiert dieses Skript die Werkzeuge und richtet einen Befehl
`dex` sowie eine per Doppelklick startbare `DeX.app` auf deinem Schreibtisch mit fester
Auflösung/DPI ein.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

Es installiert `scrcpy`/`adb`, falls sie fehlen, fragt nach Auflösung + DPI (Standard
`1920x1080` / `160`), fügt einen `dex`-Alias zu `~/.zshrc` hinzu und erstellt `~/Desktop/DeX.app`.

## Erstmalige Einrichtung des Handys

1. Auf dem Handy: **Einstellungen → Über das Telefon →** tippe 7-mal auf die **Build-Nummer**, um
   die Entwickleroptionen freizuschalten.
2. **Einstellungen → Entwickleroptionen →** aktiviere **USB-Debugging**.
3. Verbinde das Handy per USB mit dem Mac und bestätige die Debugging-Abfrage.

Starte DeX dann über DeXBar (oder führe `dex` aus). Der DeX-Desktop öffnet sich in einem Fenster
auf deinem Mac.

## Drahtlos (ohne Kabel)

DeX kann statt über USB auch über WiFi laufen. Du richtest es einmal über USB ein und kommst dann
ohne Kabel aus, solange Handy und Mac im selben WiFi sind.

```bash
# 1) Einmalige Einrichtung: Handy per USB angeschlossen (Debugging autorisiert)
./wireless.sh setup      # schaltet adb auf WiFi um, speichert die Handy-IP; dann abstecken

# 2) Danach jederzeit: neu verbinden und DeX starten, ohne Kabel
./wireless.sh start      # oder: ./wireless.sh connect (nur neu verbinden)
```

Sobald das Handy drahtlos verbunden ist, **funktioniert auch das „DeX starten" in DeXBar über
WiFi** — die App nutzt einfach das Gerät, das `adb` sieht, und wendet automatisch WiFi-optimierte
Streaming-Einstellungen an (siehe unten).

### Flüssigkeit über WiFi

WiFi bringt Bandbreitenschwankungen und Jitter mit sich, daher starten sowohl `wireless.sh start`
als auch DeXBar (wenn das Gerät drahtlos ist) scrcpy mit angepassten Flags:

| Flag | Warum |
|------|------|
| `--video-codec=h265` | Bessere Kompression → weniger Bandbreite → weniger verworfene Frames |
| `--video-buffer=50` | Ein kleiner Puffer fängt Netzwerk-Jitter ab — der wichtigste Ruckel-Fix (≈50 ms Latenz)|
| `--max-fps=60` | Begrenzt die Aufnahme-Bildrate für gleichmäßigen Fluss |
| `--video-bit-rate=8M` | Genug für einen scharfen Desktop, ohne das WiFi zu sättigen |
| `--no-audio` | Entfernt den Overhead der Audioweiterleitung |

Jeden dieser Werte kannst du für `wireless.sh` per Umgebungsvariablen überschreiben, z. B. Audio
behalten und den Puffer in einem instabilen Netz erhöhen:

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

USB-Starts bleiben schlank (kein zusätzlicher Puffer/Latenz), da die Verbindung bereits stabil
ist.

Hinweise:
- Das Handy muss im selben WiFi bleiben. Nach einem **Neustart des Handys** wird der TCP-Modus
  zurückgesetzt — führe `./wireless.sh setup` erneut per USB aus.
- Wenn du einen lokalen Proxy/VPN nutzt (**Surge, Clash usw.**), kann er die adb-Verbindung
  abfangen und `failed to connect: No route to host` verursachen. `wireless.sh` umgeht den Proxy
  für LAN-Adressen automatisch; falls es dennoch auftritt, füge in der Proxy-App eine
  **DIRECT**-Regel für dein `192.168.*`-Subnetz hinzu.

## Auflösung / DPI anpassen

Bei gleicher Auflösung zeigt ein **niedrigerer DPI** mehr Inhalt mit kleineren UI-Elementen; ein
**höherer DPI** macht alles größer. `1920x1080/160` ist ein sinnvoller, desktopähnlicher
Standard. In DeXBar wählst du einfach aus den Menüs. Für `install.sh` führe es erneut aus oder
bearbeite den Wert `--new-display=BREITExHÖHE/DPI` im `dex`-Alias (`~/.zshrc`).

## Wie es funktioniert

```bash
scrcpy --new-display=1920x1080/160
```

Dieser eine Befehl erstellt auf dem Handy ein neues virtuelles Display mit der angegebenen
Auflösung/Dichte, wodurch der Desktop-Modus von One UI 8 (DeX) darauf gerendert wird, und
spiegelt dieses Display per USB (oder drahtlosem adb) in ein Fenster auf deinem Mac. DeXBar ist
ein dünner nativer Wrapper um genau diesen Befehl plus `adb devices` für den Status.

## Lizenz

MIT
