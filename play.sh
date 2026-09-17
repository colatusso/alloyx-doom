#!/usr/bin/env bash
# AlloyX DOOM — jogo jogavel em tempo real. O ENGINE e Apex (Doom.cls/Wad.cls),
# transpilado p/ Java pelo AlloyX; este script compila tudo e abre a janela.
#
#   ./play.sh            # compila e joga
#   ./play.sh --build    # so compila (nao abre a janela)
#
# Controles: W/S frente-tras | A/D viram | Q/E strafe | Ctrl atira | SPACE usa | 2-7 arma | ESC sai
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f WadData.cls ]; then
    [ -f doom1.wad ] || { echo "doom1.wad nao encontrado; coloque o WAD shareware nesta pasta (veja README.md)" >&2; exit 1; }
    python3 tools/wad2apex.py doom1.wad E1M1,E1M2 --out WadData.cls
fi

ALLOY_LIB="../apex-local/build/install/allx/lib"
[ -d "$ALLOY_LIB" ] || { echo "runtime do AlloyX nao encontrado em $ALLOY_LIB (rode ./gradlew installDist no apex-local)"; exit 1; }
CP=".apexcache:$ALLOY_LIB/*"

echo "[1/3] compilando o engine Apex -> .class (allx)..." >&2
allx run Doom.cls --method Doom.gtest >/dev/null 2>&1 || { echo "falha ao compilar o Apex"; allx run Doom.cls --method Doom.gtest; exit 1; }

echo "[2/3] compilando o host Java (Game.java)..." >&2
javac -cp "$CP" -d . Game.java

if [ "${1:-}" = "--build" ]; then echo "build ok."; exit 0; fi

echo "[3/3] abrindo o jogo  (W/S anda | A/D vira | Q/E strafe | Ctrl atira | SPACE usa | 2-7 arma | ESC sai)" >&2
exec java -cp ".:$CP" Game
