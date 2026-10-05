#!/bin/bash
# Construit le DMG mis en page : fond avec la flèche, icônes placées, fenêtre sans barres.
# Usage : scripts/dmg/build.sh <Magneto.app> <sortie.dmg>
# Ne signe pas : la release signe le DMG après, comme avant.
set -euo pipefail
cd "$(dirname "$0")"

APP="$1"
OUT="$2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift background.swift "$WORK"
# Un TIFF à deux résolutions : le Finder prend la @2x sur un écran Retina.
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff"

dmgbuild -s settings.py -D app="$APP" -D background="$WORK/background.tiff" "Magneto" "$OUT"
