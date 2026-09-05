#!/usr/bin/env bash
# Diagnostic HITL : trouve la largeur maximale (en pixels) que foot accepte
# d'afficher pour un sixel émis par img2sixel.
#
# Le script est conçu pour être exécuté DANS l'instance (déposé via scp
# depuis le poste foot dans ~/), dans une grande console foot (ex.
# --window-size-chars=110x109), sans redimensionner la fenêtre. Usage :
#
#   bash img2sixel-width-bisect.sh <lo> <hi>
#
# Image test : par défaut ~/poc.jpg, ou via IMG=/path/image.jpg
set -euo pipefail

img="${IMG:-$HOME/poc.jpg}"
lo="${1:-500}"
hi="${2:-4000}"

while (( hi - lo > 1 )); do
  mid=$(( (lo + hi) / 2 ))
  printf '\e[H\e[2J'
  img2sixel -w "$mid" "$img"
  read -r -p "img2sixel w=${mid} px : visible ? [y/n] " ans
  case "$ans" in y|Y) lo=$mid ;; *) hi=$mid ;; esac
done
echo "OK px w=${lo} | echec px w=${hi}"
