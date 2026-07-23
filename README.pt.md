# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Português**

Rode o Samsung DeX no seu Mac — sem monitor, sem plugue HDMI falso, sem Miracast.

A Samsung encerrou o suporte oficial do DeX para PC, mas o One UI 8 (Android 16) reconstruiu o
DeX sobre o modo desktop nativo do Android, que suporta **telas virtuais**.
[scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ consegue criar uma dessas telas virtuais
diretamente, então toda a área de trabalho do DeX aparece em uma janela no seu Mac — apenas com
um cabo USB.

## Requisitos

- macOS 13+
- Um celular/tablet Samsung Galaxy com **One UI 8 ou posterior** (Android 16+)
- Cabo USB
- [Homebrew](https://brew.sh)

## Duas formas de usar

### Opção A — App de barra de menus DeXBar (recomendada)

Um app nativo de barra de menus: escolha resolução/DPI, veja se o celular está conectado e
inicie/pare o DeX — tudo pela barra de menus, sem terminal.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # opcional: cp -R build/DeXBar.app /Applications/
```

Requer `scrcpy` + `adb` (o app informa o comando de instalação se estiverem faltando):

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Clique no ícone de tela na barra de menus:

- **Linha de status** — mostra o modelo do dispositivo conectado, ou avisa se a depuração USB não
  está autorizada / não há dispositivo conectado.
- **Iniciar / Parar DeX** — inicia ou encerra a sessão de tela virtual do scrcpy.
- **Resolução / DPI** — escolha entre as predefinições; sua escolha é lembrada.
- **Abrir registro** — abre `~/Library/Logs/DeXBar.log`.

As configurações persistem entre reinicializações. O app roda apenas na barra de menus (sem ícone
no Dock).

### Opção B — install.sh (alias de terminal + lançador na área de trabalho)

Se você prefere sem interface gráfica, este script instala as ferramentas e configura um comando
`dex` mais um `DeX.app` de duplo clique na sua área de trabalho com resolução/DPI fixos.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

Ele instala `scrcpy`/`adb` se faltarem, pergunta a resolução + DPI (padrão `1920x1080` / `160`),
adiciona um alias `dex` ao `~/.zshrc` e cria `~/Desktop/DeX.app`.

## Configuração inicial do celular

1. No celular: **Configurações → Sobre o telefone →** toque em **Número da versão** 7 vezes para
   desbloquear as opções do desenvolvedor.
2. **Configurações → Opções do desenvolvedor →** ative a **Depuração USB**.
3. Conecte o celular ao Mac por USB e aprove o aviso de depuração.

Depois inicie o DeX pelo DeXBar (ou rode `dex`). A área de trabalho do DeX abre em uma janela no
seu Mac.

## Sem fio (sem cabo)

O DeX pode funcionar por WiFi em vez de USB. Você faz uma configuração inicial por USB e depois
dispensa o cabo enquanto o celular e o Mac estiverem na mesma rede WiFi.

```bash
# 1) Configuração única: celular conectado por USB (depuração autorizada)
./wireless.sh setup      # muda o adb para WiFi, salva o IP do celular; depois você desconecta

# 2) Depois, a qualquer momento: reconecte e inicie o DeX, sem cabo
./wireless.sh start      # ou: ./wireless.sh connect (apenas reconectar)
```

Assim que o celular estiver conectado sem fio, **o "Iniciar DeX" do DeXBar também funciona por
WiFi** — o app usa o dispositivo que o `adb` enxerga e aplica automaticamente configurações de
streaming otimizadas para WiFi (veja abaixo).

### Fluidez por WiFi

O WiFi adiciona variação de banda e jitter, então tanto `wireless.sh start` quanto o DeXBar
(quando o dispositivo é sem fio) iniciam o scrcpy com flags ajustados:

| Flag | Por quê |
|------|------|
| `--video-codec=h265` | Melhor compressão → menos banda → menos quadros perdidos |
| `--video-buffer=50` | Um pequeno buffer absorve o jitter de rede — a principal correção contra travadas (≈50 ms de latência)|
| `--max-fps=60` | Limita a taxa de captura para um ritmo estável |
| `--video-bit-rate=8M` | Suficiente para uma área de trabalho nítida sem saturar o WiFi |
| `--no-audio` | Elimina a sobrecarga do encaminhamento de áudio |

Você pode sobrescrever qualquer um deles para o `wireless.sh` via variáveis de ambiente, por ex.
manter o áudio e aumentar o buffer em uma rede instável:

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

As inicializações por USB permanecem enxutas (sem buffer/latência adicionados) porque o link já é
estável.

Observações:
- O celular deve permanecer na mesma rede WiFi. Após **reiniciar o celular**, o modo TCP é
  redefinido — rode `./wireless.sh setup` novamente com USB.
- Se você usa um proxy/VPN local (**Surge, Clash, etc.**), ele pode sequestrar a conexão do adb e
  causar `failed to connect: No route to host`. O `wireless.sh` ignora o proxy para endereços LAN
  automaticamente; se ainda acontecer, adicione uma regra **DIRECT** para a sua sub-rede
  `192.168.*` no app do proxy.

## Ajustar resolução / DPI

Em uma dada resolução, um **DPI mais baixo** mostra mais conteúdo com elementos de interface
menores; um **DPI mais alto** deixa tudo maior. `1920x1080/160` é um padrão razoável, parecido com
desktop. No DeXBar, basta escolher pelos menus. Para o `install.sh`, rode-o novamente ou edite o
valor `--new-display=LARGURAxALTURA/DPI` no alias `dex` (`~/.zshrc`).

## Como funciona

```bash
scrcpy --new-display=1920x1080/160
```

Este único comando cria uma nova tela virtual no celular na resolução/densidade indicada, o que
faz o modo desktop do One UI 8 (DeX) renderizar nela, e espelha essa tela em uma janela no seu Mac
por USB (ou adb sem fio). O DeXBar é um fino wrapper nativo em torno exatamente deste comando mais
`adb devices` para o status.

## Licença

MIT
