#!/bin/bash
# Lit les caractéristiques de ce MacBook et l'ajoute au stock TechDesk (POST /api/v1/products/scan).
# Chaque scan est d'abord enregistré sur la clé (scans/en-attente). Sans internet, il part au prochain scan
# fait avec internet, sur n'importe quel laptop. N'utilise que des outils présents sur tout Mac.
USB="$(cd "$(dirname "$0")/.." && pwd)"
PENDING="$USB/scans/en-attente"
SENT="$USB/scans/envoyes"
mkdir -p "$PENDING" "$SENT"

setting() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$USB/settings.txt" | tr -d '\r' | sed 's/[[:space:]]*$//' | head -n 1; }
URL="$(setting TECHDESK_URL)"; URL="${URL%/}"
KEY="$(setting API_KEY)"

# ---- Lecture du Mac ----
HW="$(system_profiler SPHardwareDataType 2>/dev/null)"
field() { printf '%s\n' "$HW" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -n 1; }
MODEL="$(field 'Model Name')"
CHIP="$(field 'Chip')"
[ -z "$CHIP" ] && CHIP="$(field 'Processor Name')"   # Mac Intel
SERIAL="$(field 'Serial Number (system)')"
RAM="$(sysctl -n hw.memsize)"
DISK="$(diskutil info -plist disk0 2>/dev/null | plutil -extract TotalSize raw -o - - 2>/dev/null)"
RES="$(system_profiler SPDisplaysDataType 2>/dev/null | sed -n 's/^[[:space:]]*Resolution:[[:space:]]*\([0-9]*\) x \([0-9]*\).*/\1 \2/p' | head -n 1)"
WIDTH="${RES% *}"; HEIGHT="${RES#* }"

json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
num() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

echo
echo "  Mac lu :"
echo "    $MODEL - $CHIP"
echo "    RAM $(( $(num "$RAM") / 1073741824 )) Go  -  Disque $(( $(num "$DISK") / 1000000000 )) Go (taille brute)  -  Écran ${WIDTH}x${HEIGHT}"
echo "    N° de série : $SERIAL"

NAME="$(printf '%s' "$SERIAL" | tr -cd 'A-Za-z0-9_-')"
FILE="$PENDING/${NAME:-mac}-$(date +%Y%m%d-%H%M%S).json"
printf '{"os":"mac","model":"%s","cpu":"%s","ramBytes":%s,"diskBytes":%s,"screenWidth":%s,"screenHeight":%s,"serialNumber":"%s"}\n' \
  "$(json "$MODEL")" "$(json "$CHIP")" "$(num "$RAM")" "$(num "$DISK")" "$(num "$WIDTH")" "$(num "$HEIGHT")" "$(json "$SERIAL")" > "$FILE"

# ---- Envoi (ce Mac + les scans restés en attente) ----
case "$KEY" in smk_*) ;; *) KEY="" ;; esac
if [ -z "$URL" ] || [ -z "$KEY" ] || printf '%s' "$URL$KEY" | grep -q 'example\.com\|COLLEZ'; then
  echo
  echo "  Réglages incomplets : ouvrez settings.txt sur la clé et mettez TECHDESK_URL et API_KEY."
  echo "  Le scan est gardé sur la clé et partira au prochain scan."
  exit 1
fi

FAILED=0
REPLY_FILE="$(mktemp -t techdesk-scan)"
for ITEM in "$PENDING"/*.json; do
  [ -e "$ITEM" ] || continue
  STATUS="$(curl -sS -m 20 -o "$REPLY_FILE" -w '%{http_code}' -X POST "$URL/api/v1/products/scan" \
    -H "X-API-Key: $KEY" -H 'Content-Type: application/json; charset=utf-8' --data-binary "@$ITEM" 2>/dev/null)"
  get() { plutil -extract "$1" raw -o - "$REPLY_FILE" 2>/dev/null; }
  echo
  case "$STATUS" in
    200|201)
      if [ "$(get created)" = "true" ]; then echo "  AJOUTÉ AU STOCK : $(get product.brand) $(get product.name)"
      else echo "  DÉJÀ EN STOCK (pas ajouté deux fois) : $(get product.brand) $(get product.name)"; fi
      echo "    $(get product.configuration)"
      echo "    Bar ID : $(get product.barId)   -   Prix et état à compléter dans TechDesk"
      mv -f "$ITEM" "$SENT/" ;;
    401|403) FAILED=1; echo "  TechDesk refuse la clé : vérifiez API_KEY dans settings.txt (clé \"Scanner USB\")." ;;
    000|'') FAILED=1; echo "  Pas de connexion à TechDesk : le scan reste sur la clé et partira au prochain scan avec internet." ;;
    *) FAILED=1; echo "  TechDesk a répondu une erreur ($STATUS) pour $(basename "$ITEM")." ;;
  esac
done
rm -f "$REPLY_FILE"
exit $FAILED
