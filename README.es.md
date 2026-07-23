# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **Español** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

Ejecuta Samsung DeX en tu Mac — sin monitor, sin adaptador HDMI ficticio, sin Miracast.

Samsung retiró el soporte oficial de DeX para PC, pero One UI 8 (Android 16) reconstruyó DeX
sobre el modo escritorio nativo de Android, que admite **pantallas virtuales**.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ puede crear una de esas pantallas
virtuales directamente, así que todo el escritorio DeX aparece en una ventana de tu Mac —
solo con un cable USB.

## Requisitos

- macOS 13+
- Un teléfono/tableta Samsung Galaxy con **One UI 8 o posterior** (Android 16+)
- Cable USB
- [Homebrew](https://brew.sh)

## Dos formas de usarlo

### Opción A — App de barra de menús DeXBar (recomendada)

Una app nativa de barra de menús: elige resolución/DPI, comprueba si el teléfono está
conectado e inicia/detén DeX — todo desde la barra de menús, sin terminal.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # opcional: cp -R build/DeXBar.app /Applications/
```

Requiere `scrcpy` + `adb` (la app te indica el comando de instalación si faltan):

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Haz clic en el icono de pantalla de la barra de menús:

- **Línea de estado** — muestra el modelo del dispositivo conectado, o avisa si la depuración
  USB no está autorizada / no hay dispositivo.
- **Iniciar / Detener DeX** — inicia o cierra la sesión de pantalla virtual de scrcpy.
- **Resolución / DPI** — elige entre los preajustes; tu elección se recuerda.
- **Abrir registro** — abre `~/Library/Logs/DeXBar.log`.

Los ajustes se conservan entre reinicios. La app se ejecuta solo en la barra de menús (sin
icono en el Dock).

### Opción B — install.sh (alias de terminal + lanzador de escritorio)

Si prefieres no usar interfaz gráfica, este script instala las herramientas y configura un
comando `dex` más una `DeX.app` de doble clic en tu escritorio con una resolución/DPI fija.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

Instala `scrcpy`/`adb` si faltan, pregunta la resolución + DPI (por defecto `1920x1080` /
`160`), añade un alias `dex` a `~/.zshrc` y crea `~/Desktop/DeX.app`.

## Configuración inicial del teléfono

1. En el teléfono: **Ajustes → Acerca del teléfono →** toca **Número de compilación** 7 veces
   para desbloquear las Opciones de desarrollador.
2. **Ajustes → Opciones de desarrollador →** activa la **Depuración USB**.
3. Conecta el teléfono al Mac por USB y aprueba el aviso de depuración.

Luego inicia DeX desde DeXBar (o ejecuta `dex`). El escritorio DeX se abre en una ventana de
tu Mac.

## Inalámbrico (sin cable)

DeX puede funcionar por WiFi en lugar de USB. Haces una configuración inicial por USB y luego
prescindes del cable mientras el teléfono y el Mac compartan la misma red WiFi.

```bash
# 1) Configuración única: teléfono conectado por USB (depuración autorizada)
./wireless.sh setup      # cambia adb a WiFi, guarda la IP del teléfono; luego desconectas

# 2) Cuando quieras: reconecta e inicia DeX, sin cable
./wireless.sh start      # o: ./wireless.sh connect (solo reconectar)
```

Una vez que el teléfono esté conectado de forma inalámbrica, **el "Iniciar DeX" de DeXBar
también funciona por WiFi** — la app usa el dispositivo que ve `adb` y aplica automáticamente
ajustes de streaming optimizados para WiFi (ver abajo).

### Fluidez por WiFi

El WiFi añade variación de ancho de banda y fluctuación (jitter), así que tanto
`wireless.sh start` como DeXBar (cuando el dispositivo es inalámbrico) lanzan scrcpy con flags
ajustados:

| Flag | Por qué |
|------|------|
| `--video-codec=h265` | Mejor compresión → menos ancho de banda → menos fotogramas perdidos |
| `--video-buffer=50` | Un pequeño búfer absorbe el jitter de red — la clave contra los tirones (≈50 ms de latencia)|
| `--max-fps=60` | Limita la tasa de captura para un ritmo estable |
| `--video-bit-rate=8M` | Suficiente para un escritorio nítido sin saturar el WiFi |
| `--no-audio` | Elimina la sobrecarga del reenvío de audio |

Puedes sobrescribir cualquiera de ellos en `wireless.sh` con variables de entorno, p. ej.
mantener el audio y subir el búfer en una red inestable:

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

Los lanzamientos por USB se mantienen ligeros (sin búfer/latencia añadidos) porque el enlace ya
es estable.

Notas:
- El teléfono debe permanecer en la misma red WiFi. Tras **reiniciar el teléfono**, el modo TCP
  se restablece — vuelve a ejecutar `./wireless.sh setup` con USB.
- Si usas un proxy/VPN local (**Surge, Clash, etc.**), puede secuestrar la conexión de adb y
  provocar `failed to connect: No route to host`. `wireless.sh` evita el proxy para direcciones
  LAN automáticamente; si aun así ocurre, añade una regla **DIRECT** para tu subred `192.168.*`
  en la app del proxy.

## Ajustar resolución / DPI

A una resolución dada, un **DPI más bajo** muestra más contenido con elementos de interfaz más
pequeños; un **DPI más alto** agranda todo. `1920x1080/160` es un valor por defecto razonable,
tipo escritorio. En DeXBar solo elige desde los menús. Para `install.sh`, vuelve a ejecutarlo o
edita el valor `--new-display=ANCHOxALTO/DPI` en el alias `dex` (`~/.zshrc`).

## Cómo funciona

```bash
scrcpy --new-display=1920x1080/160
```

Este único comando crea una nueva pantalla virtual en el teléfono con la resolución/densidad
dada, lo que hace que el modo escritorio de One UI 8 (DeX) se renderice en ella, y refleja esa
pantalla en una ventana de tu Mac por USB (o adb inalámbrico). DeXBar es una fina envoltura
nativa alrededor exactamente de este comando más `adb devices` para el estado.

## Licencia

MIT
