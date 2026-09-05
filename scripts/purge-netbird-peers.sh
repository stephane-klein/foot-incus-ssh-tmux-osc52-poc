#!/usr/bin/env bash
# Purge les peers NetBird dont l'identité (hostname / FQDN / DNS label) va être
# réutilisée par de nouvelles instances Incus. Typiquement à appeler juste
# avant un `incus-apply` pour "remplacer" l'ancien peer par le nouveau.
#
# Usage: purge-netbird-peers.sh [--dry-run] [FILE.yaml ...] [TOKEN ...]
#
#   --dry-run  liste les peers qui seraient supprimés sans rien supprimer.
#   FILE.yaml  fichier incus-apply : les tokens sont extraits des champs
#              `name:` (top-level) et `hostname:` / `fqdn:` des blocs
#              cloud-init.user-data.
#   TOKEN      hostname ou FQDN explicite à purger.
#
# Garde-fou : un token est ignoré tant qu'une instance Incus du même nom
# (ou dont le premier label correspond au token) existe encore, pour ne jamais
# déconnecter un peer vivant lors d'un `apply` idempotent.
#
# Config : NETBIRD_API_URL (défaut https://api.netbird.io) et PAT lu depuis
# gopass `netbird/apikey` (ou NETBIRD_PAT en variable d'environnement).
set -euo pipefail

cd "$(dirname "$0")/../"

usage() {
  awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0" >&2
  exit "${1:-1}"
}

DRY_RUN=0
FILES=()
EXTRA=()

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage 0
      ;;
    *.yaml | *.yml) FILES+=("$arg") ;;
    *) EXTRA+=("$arg") ;;
  esac
done

API_URL="${NETBIRD_API_URL:-https://api.netbird.io}"
PAT="${NETBIRD_PAT:-$(gopass show -o netbird/apikey)}"
[ -n "$PAT" ] || {
  echo "ERROR: aucun PAT NetBird (gopass netbird/apikey ou NETBIRD_PAT)" >&2
  exit 1
}

JQ="$(command -v jq || { command -v mise >/dev/null 2>&1 && mise which jq 2>/dev/null; } || true)"
[ -n "${JQ:-}" ] || {
  echo "ERROR: jq introuvable" >&2
  exit 1
}

# Extraction des tokens depuis un fichier incus-apply.
extract_tokens() {
  local file="$1"
  sed -nE 's/^name:[[:space:]]+([^[:space:]]+).*/\1/p' "$file"
  sed -nE 's/^[[:space:]]+hostname:[[:space:]]+([^[:space:]]+).*/\1/p' "$file"
  sed -nE 's/^[[:space:]]+fqdn:[[:space:]]+([^[:space:]]+).*/\1/p' "$file"
}

declare -A TOKENS=()
for file in "${FILES[@]}"; do
  [ -f "$file" ] || {
    echo "ERROR: fichier introuvable : $file" >&2
    exit 1
  }
  while IFS= read -r t; do
    [ -n "$t" ] && TOKENS["$t"]=1
  done < <(extract_tokens "$file")
done
for t in "${EXTRA[@]}"; do
  [ -n "$t" ] && TOKENS["$t"]=1
done

[ "${#TOKENS[@]}" -eq 0 ] && {
  echo "Rien à purger : aucun token donné" >&2
  usage 1
}

# Garde-fou : noms des instances Incus encore présentes.
EXISTING_NAMES=""
if INCUS_LIST="$(incus list --format=json 2>/dev/null)"; then
  EXISTING_NAMES="$(printf '%s' "$INCUS_LIST" | "$JQ" -r '.[].name')"
else
  echo "WARN: impossible de lister les instances Incus, garde-fou désactivé" >&2
fi

instance_exists() {
  printf '%s\n' "$EXISTING_NAMES" | grep -qxF "$1"
}

PEERS="$(curl -fsS "${API_URL}/api/peers" -H "Authorization: Token ${PAT}")"

purged=0
absent=0
declare -A DONE=()
for token in "${!TOKENS[@]}"; do
  if instance_exists "$token" || instance_exists "${token%%.*}"; then
    echo "SKIP ${token}: instance Incus encore présente"
    continue
  fi

  while IFS=$'\t' read -r id pname hostname dns_label; do
    [ -z "$id" ] && continue
    if [[ -v DONE[$id] ]]; then
      continue
    fi
    DONE[$id]=1
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] supprimerait le peer NetBird '$pname' (id=$id, hostname=$hostname, dns_label=$dns_label)"
    else
      status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "${API_URL}/api/peers/${id}" -H "Authorization: Token ${PAT}")"
      case "$status" in
        200 | 202 | 204) echo "Supprimé le peer NetBird '$pname' (id=$id, hostname=$hostname, dns_label=$dns_label)" ;;
        404) absent=$((absent + 1)); echo "Peer NetBird '$pname' (id=$id) déjà absent" ;;
        *)
          echo "ERROR: suppression du peer NetBird '$pname' (id=$id) : HTTP $status" >&2
          exit 1
          ;;
      esac
    fi
    purged=$((purged + 1))
  done < <(printf '%s\n' "$PEERS" | "$JQ" -r --arg t "$token" '
    .[] | select(
      (.name == $t) or (.hostname == $t) or (.dns_label == $t) or
      ([.extra_dns_labels[]?] | index($t))
    ) | [.id, .name, .hostname, .dns_label] | @tsv')
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run : ${purged} peer(s) à supprimer"
else
  msg="${purged} peer(s) NetBird supprimé(s)"
  [ "$absent" -gt 0 ] && msg="${msg}, ${absent} déjà absent(s)"
  echo "$msg"
fi
