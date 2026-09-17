#!/usr/bin/env bash
# AlloyX DOOM — roda o engine DOOM escrito em Apex PURO (via allx) e toca o
# resultado como animacao no terminal. O Apex faz todo o trabalho: parseia o
# WAD oficial (E1M1), rasteriza as paredes e raycasta cada frame. Este script
# so remove o prefixo "DEBUG|" e reproduz os frames (clear + sleep).
#
# Uso:
#   ./run.sh                # walkthrough autonomo do E1M1 (demo)
#   ./run.sh fpv            # um frame first-person do ponto de partida
#   ./run.sh automap        # mapa top-down (prova a geometria do WAD)
#   ./run.sh demo 20        # walkthrough a 20 fps
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f WadData.cls ]; then
    [ -f doom1.wad ] || { echo "doom1.wad nao encontrado; coloque o WAD shareware nesta pasta (veja README.md)" >&2; exit 1; }
    python3 tools/wad2apex.py doom1.wad E1M1,E1M2 --out WadData.cls
fi

METHOD="${1:-demo}"
FPS="${2:-14}"
FRAMES_FILE="/tmp/alloyx_doom_frames.txt"

echo "AlloyX DOOM — transpilando Apex -> Java e rodando engine (allx)..." >&2
allx run Doom.cls --method "Doom.$METHOD" 2>/tmp/alloyx_doom_err.txt | sed 's/^DEBUG|//' > "$FRAMES_FILE" || {
    echo "Falha ao rodar via allx:" >&2; cat /tmp/alloyx_doom_err.txt >&2; exit 1; }

# modos de frame unico: imprime direto
if [ "$METHOD" != "demo" ]; then
    cat "$FRAMES_FILE"
    exit 0
fi

delay=$(awk "BEGIN{ d=1.0/$FPS; print (d>0?d:0.07) }")
printf '\033[2J'
buf=""
play() { printf '\033[H%s' "$buf"; }   # home (sem limpar: overwrite reduz flicker)
while IFS= read -r line; do
    if [ "$line" = "@@F@@" ]; then
        if [ -n "$buf" ]; then play; sleep "$delay"; fi
        buf=""
    else
        buf+="$line"$'\n'
    fi
done < "$FRAMES_FILE"
[ -n "$buf" ] && play
printf '\033[%d;1H\n' 48
