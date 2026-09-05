#!/usr/bin/env bash
# Diagnostic HITL : trouve la hauteur d'image (en cellules) au-delà de
# laquelle foot cesse d'afficher un sixel dans la fenêtre courante.
#
# Le script est conçu pour être exécuté DANS l'instance (déposé via scp
# depuis le poste foot dans ~/). Usage :
#
#   bash sixel-height-scan.sh scan <h_max> <pas>   # balayage linéaire
#   bash sixel-height-scan.sh bisect <lo> <hi>     # affinage dichotomique
#
# Image test : par défaut ~/poc.jpg, ou via IMG=/path/image.jpg
#
# Fenêtre de test conseillée sur le poste foot :
#   foot --config assets/foot.ini --window-size-chars=120x40 -e ssh -t ... bash
# puis, sans redimensionner la fenêtre, lancer le script dans ce bash.
set -euo pipefail

img="${IMG:-$HOME/poc.jpg}"
if ! read -r rows cols < <(stty size 2>/dev/null); then
  rows="${LINES:-24}"
  cols="${COLUMNS:-124}"
fi
wmax=$(( cols > 4 ? cols - 4 : 60 ))

probe() { # probe <h> : affiche une image de h lignes et demande "visible ?"
  local h=$1 w
  w=$(( h * 165 / 100 )); (( w > wmax )) && w=$wmax
  printf '\e[H\e[2J'
  printf '=== H=%s (window %s x %s) ===\n' "$h" "$cols" "$rows"
  chafa --format=sixel --size="${w}x${h}" "$img"
  read -r -p "visible ? [y/n] " ans
  case "$ans" in y|Y) return 0 ;; *) return 1 ;; esac
}

scan() {
  local himax=${1:-80} step=${2:-5} h
  echo "window: ${rows} rows x ${cols} cols"
  for (( h = 20; h <= himax; h += step )); do
    probe "$h" || { printf '>>> H=%s : plus affichee\n' "$h"; return 0; }
  done
}

bisect() {
  local lo=$1 hi=$2 mid
  while (( hi - lo > 1 )); do
    mid=$(( (lo + hi) / 2 ))
    probe "$mid" && lo=$mid || hi=$mid
  done
  echo "dernier OK: H=$lo | premier echec: H=$hi | window=${cols}x${rows} (w_emise=$(( lo * 165 / 100 > wmax ? wmax : lo * 165 / 100 )))"
}

case "${1:-}" in
  scan)   shift; scan "$@";;
  bisect) shift; bisect "$@";;
  *) echo "usage: $0 scan [h_max] [pas] | $0 bisect <lo_ok> <hi_ko>"; exit 1;;
esac
