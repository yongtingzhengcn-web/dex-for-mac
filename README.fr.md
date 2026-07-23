# dex-for-mac

[English](README.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [Español](README.es.md) · **Français** · [Deutsch](README.de.md) · [Português](README.pt.md)

Lancez Samsung DeX sur votre Mac — sans moniteur, sans bouchon HDMI factice, sans Miracast.

Samsung a abandonné la prise en charge officielle de DeX sur PC, mais One UI 8 (Android 16) a
reconstruit DeX au-dessus du mode bureau natif d'Android, qui prend en charge les **écrans
virtuels**. [scrcpy](https://github.com/Genymobile/scrcpy) 4.1+ peut créer un tel écran virtuel
directement, si bien que tout le bureau DeX apparaît dans une fenêtre sur votre Mac — avec un
simple câble USB.

## Prérequis

- macOS 13+
- Un téléphone/tablette Samsung Galaxy sous **One UI 8 ou ultérieur** (Android 16+)
- Câble USB
- [Homebrew](https://brew.sh)

## Deux façons de l'utiliser

### Option A — Application de barre de menus DeXBar (recommandée)

Une application native de barre de menus : choisissez la résolution/DPI, vérifiez si le
téléphone est connecté, et démarrez/arrêtez DeX — tout depuis la barre de menus, sans terminal.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac/app
./build.sh
open build/DeXBar.app     # facultatif : cp -R build/DeXBar.app /Applications/
```

Nécessite `scrcpy` + `adb` (l'app indique la commande d'installation s'ils manquent) :

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Cliquez sur l'icône d'écran dans la barre de menus :

- **Ligne d'état** — affiche le modèle de l'appareil connecté, ou un avertissement si le
  débogage USB n'est pas autorisé / aucun appareil connecté.
- **Démarrer / Arrêter DeX** — lance ou ferme la session d'écran virtuel de scrcpy.
- **Résolution / DPI** — choisissez parmi les préréglages ; votre choix est mémorisé.
- **Ouvrir le journal** — ouvre `~/Library/Logs/DeXBar.log`.

Les réglages sont conservés entre les redémarrages. L'app s'exécute uniquement dans la barre de
menus (pas d'icône dans le Dock).

### Option B — install.sh (alias de terminal + lanceur sur le bureau)

Si vous préférez sans interface graphique, ce script installe les outils et met en place une
commande `dex` ainsi qu'une `DeX.app` à double-clic sur votre bureau, avec une résolution/DPI
fixe.

```bash
git clone https://github.com/yongtingzhengcn-web/dex-for-mac.git
cd dex-for-mac
./install.sh
```

Il installe `scrcpy`/`adb` s'ils manquent, demande la résolution + DPI (par défaut `1920x1080` /
`160`), ajoute un alias `dex` à `~/.zshrc` et crée `~/Desktop/DeX.app`.

## Première configuration du téléphone

1. Sur le téléphone : **Paramètres → À propos du téléphone →** touchez **Numéro de build** 7 fois
   pour déverrouiller les options de développeur.
2. **Paramètres → Options de développeur →** activez le **débogage USB**.
3. Connectez le téléphone au Mac en USB et approuvez l'invite de débogage.

Démarrez ensuite DeX depuis DeXBar (ou exécutez `dex`). Le bureau DeX s'ouvre dans une fenêtre
sur votre Mac.

## Sans fil (sans câble)

DeX peut fonctionner en WiFi plutôt qu'en USB. Vous faites une configuration initiale en USB,
puis vous vous passez du câble tant que le téléphone et le Mac partagent le même réseau WiFi.

```bash
# 1) Configuration unique : téléphone branché en USB (débogage autorisé)
./wireless.sh setup      # bascule adb en WiFi, enregistre l'IP du téléphone ; puis débranchez

# 2) Ensuite, à tout moment : reconnectez et lancez DeX, sans câble
./wireless.sh start      # ou : ./wireless.sh connect (reconnexion seulement)
```

Une fois le téléphone connecté en sans-fil, **le « Démarrer DeX » de DeXBar fonctionne aussi en
WiFi** — l'app utilise simplement l'appareil que voit `adb` et applique automatiquement des
réglages de streaming optimisés pour le WiFi (voir ci-dessous).

### Fluidité en WiFi

Le WiFi ajoute des variations de débit et de la gigue (jitter), donc `wireless.sh start` comme
DeXBar (quand l'appareil est sans fil) lancent scrcpy avec des options ajustées :

| Option | Pourquoi |
|------|------|
| `--video-codec=h265` | Meilleure compression → moins de bande passante → moins d'images perdues |
| `--video-buffer=50` | Un petit tampon absorbe la gigue réseau — le correctif principal contre les saccades (≈50 ms de latence)|
| `--max-fps=60` | Limite la fréquence de capture pour un rythme stable |
| `--video-bit-rate=8M` | Suffisant pour un bureau net sans saturer le WiFi |
| `--no-audio` | Supprime la surcharge de transfert audio |

Vous pouvez remplacer chacune d'elles pour `wireless.sh` via des variables d'environnement, par
ex. garder l'audio et augmenter le tampon sur un réseau instable :

```bash
DEX_AUDIO="" DEX_BUFFER=120 DEX_BITRATE=6M ./wireless.sh start
```

Les lancements en USB restent légers (aucun tampon/latence ajouté) car la liaison est déjà
stable.

Remarques :
- Le téléphone doit rester sur le même WiFi. Après un **redémarrage du téléphone**, le mode TCP
  est réinitialisé — relancez `./wireless.sh setup` en USB.
- Si vous utilisez un proxy/VPN local (**Surge, Clash, etc.**), il peut détourner la connexion
  d'adb et provoquer `failed to connect: No route to host`. `wireless.sh` contourne
  automatiquement le proxy pour les adresses LAN ; si le problème persiste, ajoutez une règle
  **DIRECT** pour votre sous-réseau `192.168.*` dans l'app du proxy.

## Ajuster la résolution / le DPI

À résolution égale, un **DPI plus bas** affiche plus de contenu avec des éléments d'interface
plus petits ; un **DPI plus élevé** agrandit tout. `1920x1080/160` est une valeur par défaut
raisonnable, proche d'un bureau. Dans DeXBar, choisissez simplement depuis les menus. Pour
`install.sh`, relancez-le ou modifiez la valeur `--new-display=LARGEURxHAUTEUR/DPI` dans l'alias
`dex` (`~/.zshrc`).

## Comment ça marche

```bash
scrcpy --new-display=1920x1080/160
```

Cette seule commande crée un nouvel écran virtuel sur le téléphone à la résolution/densité
indiquée, ce qui déclenche le rendu du mode bureau de One UI 8 (DeX) dessus, et reflète cet écran
dans une fenêtre sur votre Mac en USB (ou adb sans fil). DeXBar est une fine surcouche native
autour exactement de cette commande, plus `adb devices` pour l'état.

## Licence

MIT
