#!/bin/bash
# Relève la fiche technique complète de ce Mac, l'ajoute au journal de la clé (journal-des-scans.csv) et
# l'envoie à TechDesk (POST /api/v1/products/specs), qui l'affiche sur le produit ayant ce numéro de série.
# N'ajoute rien au stock : c'est SCAN-MAC.command qui le fait, avant ou après. Sans internet, la fiche part
# au prochain envoi fait avec internet. N'utilise que des outils présents sur tout Mac.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$DIR/journal-des-scans.csv"

field() { printf '%s\n' "$2" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -n 1; }
num() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

# ---- Nom ----
HW="$(system_profiler SPHardwareDataType 2>/dev/null)"
MODEL="$(field 'Model Name' "$HW")"
IDENT="$(field 'Model Identifier' "$HW")"
REF="$(field 'Model Number' "$HW")"
SERIAL="$(field 'Serial Number (system)' "$HW")"
# Nom commercial, ex. "MacBook Pro (14-inch, Nov 2024)" (Mac Apple Silicon seulement)
PRODUCT="$(ioreg -rd1 -c IOPlatformDevice 2>/dev/null | sed -n 's/.*"product-name" = <"\(.*\)">.*/\1/p' | head -n 1)"
NAME="${PRODUCT:-$MODEL ($IDENT)}"

# ---- Écran intégré ----
# Taille mesurée par macOS (en mm), arrondie à la taille vendue par Apple
INCHES="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var d = 0, s = $.NSScreen.screens;
  for (var i = 0; i < s.count; i++) {
    var id = ObjC.unwrap(s.objectAtIndex(i).deviceDescription.objectForKey("NSScreenNumber"));
    if ($.CGDisplayIsBuiltin(id)) { var z = $.CGDisplayScreenSize(id); d = Math.sqrt(z.width * z.width + z.height * z.height) / 25.4; }
  } d.toFixed(2)' 2>/dev/null)"
SCREEN="$(LC_ALL=C awk -v d="$INCHES" 'BEGIN { if (d + 0 <= 0) exit
  n = split("11.6 12 13 13.3 13.6 14.2 15 15.3 15.4 16 16.2 17", s, " "); bd = 1
  for (i = 1; i <= n; i++) { x = d - s[i]; if (x < 0) x = -x; if (x < bd) { bd = x; best = s[i] } }
  if (bd > 0.3) best = sprintf("%.1f", d); sub(/\.0$/, "", best); sub(/\./, ",", best); print best "\"" }')"
[ -z "$SCREEN" ] && SCREEN="$(printf '%s' "$PRODUCT" | sed -n 's/.*(\([0-9]*\)-inch.*/\1"/p')"

DXML="$(mktemp -t fiche-mac)"
system_profiler -xml SPDisplaysDataType > "$DXML" 2>/dev/null
px() { plutil -extract "$1" raw -o - "$DXML" 2>/dev/null; }
GPU=""; RES=""; DTYPE=""
g=0
while GNAME="$(px "0._items.$g.sppci_model")" && [ -n "$GNAME" ]; do
  CORES="$(px "0._items.$g.sppci_cores")"
  VRAM="$(px "0._items.$g.spdisplays_vram")"
  GPU="$GPU${GPU:+ + }$GNAME${CORES:+ ($CORES cœurs GPU)}${VRAM:+ ($VRAM)}"
  d=0
  while CONN="$(px "0._items.$g.spdisplays_ndrvs.$d._name")" && [ -n "$CONN" ]; do
    P="0._items.$g.spdisplays_ndrvs.$d"
    KIND="$(px "$P.spdisplays_display_type" | tr 'A-Z' 'a-z')"
    if [ "$(px "$P.spdisplays_connection_type")" = spdisplays_internal ] || case "$KIND" in *built*) true ;; *) false ;; esac; then
      DTYPE="$KIND"
      HZ="$(px "$P._spdisplays_resolution" | sed -n 's/.*@ *\([0-9]*\).*/\1/p')"
      RES="$(px "$P._spdisplays_pixels" | tr -d ' ')${HZ:+ @ $HZ Hz}"
    fi
    d=$((d + 1))
  done
  g=$((g + 1))
done
rm -f "$DXML"
case "$DTYPE" in
  *oled*) PANEL='OLED' ;;
  *xdr*) PANEL='Liquid Retina XDR (mini-LED)' ;;
  *liquid*) PANEL='Liquid Retina (LCD)' ;;
  *retina*) PANEL='Retina (LCD)' ;;
  *) PANEL='LCD' ;;
esac

# ---- Processeur, RAM, stockage ----
CPU="$(field 'Chip' "$HW")"
[ -z "$CPU" ] && CPU="$(field 'Processor Name' "$HW") $(field 'Processor Speed' "$HW")"   # Mac Intel
CORES="$(field 'Total Number of Cores' "$HW" | sed 's/^\([0-9]*\) (\([0-9]*\) Performance and \([0-9]*\) Efficiency)/\1 cœurs : \2 performance + \3 efficacité/')"
case "$CORES" in [0-9]*cœurs*) ;; [0-9]*) CORES="$CORES cœurs" ;; esac
CPU="$CPU${CORES:+ ($CORES)}"

RAMTYPE="$(field 'Type' "$(system_profiler SPMemoryDataType 2>/dev/null)")"
RAM="$(( $(num "$(sysctl -n hw.memsize)") / 1073741824 )) Go${RAMTYPE:+ $RAMTYPE}"

DISK="$(diskutil info -plist disk0 2>/dev/null | plutil -extract TotalSize raw -o - - 2>/dev/null)"
SSD="$(diskutil info disk0 2>/dev/null | sed -n 's/^[[:space:]]*Solid State:[[:space:]]*//p')"
# macOS montre un peu moins que la taille vendue (512 Go -> 500 Go) : on prend la taille Apple la plus proche
STORAGE="$(LC_ALL=C awk -v b="$(num "$DISK")" 'BEGIN { g = b / 1e9; if (g <= 0) exit
  n = split("128 256 512 1000 2000 4000 8000", s, " "); bd = 99
  for (i = 1; i <= n; i++) { r = log(g / s[i]); if (r < 0) r = -r; if (r < bd) { bd = r; best = s[i] } }
  if (best >= 1000) print best / 1000 " To"; else print best " Go" }')"
[ "$SSD" = Yes ] && STORAGE="$STORAGE SSD"

# ---- Batterie ----
PW="$(system_profiler SPPowerDataType 2>/dev/null)"
HEALTH="$(field 'Maximum Capacity' "$PW" | tr -d ' %')"
CYCLES="$(field 'Cycle Count' "$PW")"
CONDITION="$(field 'Condition' "$PW")"
if [ -z "$HEALTH" ]; then   # anciens macOS : capacité actuelle / capacité d'origine
  IOB="$(ioreg -rn AppleSmartBattery 2>/dev/null)"
  iob() { printf '%s\n' "$IOB" | sed -n "s/^[[:space:]|]*\"$1\" = \([0-9]*\)$/\1/p" | head -n 1; }
  MAX="$(num "$(iob AppleRawMaxCapacity)")"; DESIGN="$(num "$(iob DesignCapacity)")"
  [ "$MAX" -gt 0 ] && [ "$DESIGN" -gt 0 ] && HEALTH=$(( (MAX * 100 + DESIGN / 2) / DESIGN ))
  [ -z "$CYCLES" ] && CYCLES="$(iob CycleCount)"
fi
BATTERY="${HEALTH:+$HEALTH %}${CONDITION:+ ($CONDITION)}"

# ---- Affichage ----
echo
echo "  Fiche technique :"
echo "    Nom          : $NAME"
echo "    Référence    : ${REF:-$IDENT}"
echo "    N° de série  : $SERIAL"
echo "    Écran        : ${SCREEN:-?}  -  ${RES:-?}  -  $PANEL"
echo "    Processeur   : $CPU"
echo "    Graphique    : ${GPU:-?}"
echo "    RAM          : $RAM"
echo "    Stockage     : ${STORAGE:-?}"
echo "    Batterie     : ${BATTERY:-pas de batterie}${CYCLES:+  -  $CYCLES cycles}"

# ---- Journal (une ligne par scan, s'ouvre dans Excel ou Numbers) ----
csv() { local out="" v; for v in "$@"; do v="${v//\"/\"\"}"; out="$out${out:+;}\"$v\""; done; printf '%s\r\n' "$out"; }
if [ ! -f "$LOG" ]; then
  { printf '\xEF\xBB\xBF'
    csv 'Date' 'Système' 'Nom' 'Référence' 'N° de série' 'Écran' 'Résolution' "Type d'écran" 'Dalle' \
        'Processeur' 'Carte graphique' 'RAM' 'Stockage' 'Batterie (santé)' 'Cycles batterie'; } > "$LOG"
fi
FAILED=0
if csv "$(date '+%Y-%m-%d %H:%M')" 'Mac' "$NAME" "${REF:-$IDENT}" "$SERIAL" "$SCREEN" "$RES" "$PANEL" '' \
    "$CPU" "$GPU" "$RAM" "$STORAGE" "$BATTERY" "$CYCLES" >> "$LOG"; then
  echo
  echo "  ENREGISTRÉ dans fiche-technique/journal-des-scans.csv"
else
  echo
  echo "  Impossible d'écrire le journal sur la clé (clé pleine ou protégée ?)."
  FAILED=1
fi

# ---- Envoi à TechDesk (cette fiche + celles restées en attente) ----
USB="$(cd "$DIR/.." && pwd)"
PENDING="$USB/scans/fiches-en-attente"
SENT="$USB/scans/fiches-envoyees"
mkdir -p "$PENDING" "$SENT"
setting() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$USB/settings.txt" | tr -d '\r' | sed 's/[[:space:]]*$//' | head -n 1; }
URL="$(setting TECHDESK_URL)"; URL="${URL%/}"
KEY="$(setting API_KEY)"
json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

if [ -z "$SERIAL" ]; then
  echo
  echo "  Pas de numéro de série : la fiche n'est pas envoyée à TechDesk (elle est seulement dans le journal)."
else
  FILE="$PENDING/$(printf '%s' "$SERIAL" | tr -cd 'A-Za-z0-9_-')-$(date +%Y%m%d-%H%M%S)-$$.json"
  printf '{"os":"mac","serialNumber":"%s","name":"%s","reference":"%s","screen":"%s","resolution":"%s","screenType":"%s","panel":"","cpu":"%s","gpu":"%s","ram":"%s","storage":"%s","battery":"%s","batteryCycles":"%s"}\n' \
    "$(json "$SERIAL")" "$(json "$NAME")" "$(json "${REF:-$IDENT}")" "$(json "$SCREEN")" "$(json "$RES")" "$(json "$PANEL")" \
    "$(json "$CPU")" "$(json "$GPU")" "$(json "$RAM")" "$(json "$STORAGE")" "$(json "$BATTERY")" "$(json "$CYCLES")" > "$FILE"
fi

case "$KEY" in smk_*) ;; *) KEY="" ;; esac
if [ -z "$URL" ] || [ -z "$KEY" ] || printf '%s' "$URL$KEY" | grep -q 'example\.com\|COLLEZ'; then
  echo
  echo "  Réglages incomplets : ouvrez settings.txt sur la clé et mettez TECHDESK_URL et API_KEY."
  echo "  La fiche est gardée sur la clé et partira au prochain envoi."
  exit 1
fi

REPLY_FILE="$(mktemp -t techdesk-fiche)"
for ITEM in "$PENDING"/*.json; do
  [ -e "$ITEM" ] || continue
  STATUS="$(curl -sS -m 20 -o "$REPLY_FILE" -w '%{http_code}' -X POST "$URL/api/v1/products/specs" \
    -H "X-API-Key: $KEY" -H 'Content-Type: application/json; charset=utf-8' --data-binary "@$ITEM" 2>/dev/null)"
  get() { plutil -extract "$1" raw -o - "$REPLY_FILE" 2>/dev/null; }
  echo
  case "$STATUS" in
    200)
      if [ -n "$(get product.barId)" ]; then
        echo "  FICHE AJOUTÉE dans TechDesk : $(get product.brand) $(get product.name)  (Bar ID $(get product.barId))"
      else
        echo "  FICHE ENREGISTRÉE dans TechDesk (N° de série $(get serialNumber))."
        echo "    Ce laptop n'est pas encore en stock : lancez SCAN-MAC.command, la fiche s'affichera sur le produit."
      fi
      mv -f "$ITEM" "$SENT/" ;;
    400) echo "  TechDesk refuse la fiche $(basename "$ITEM") : elle reste seulement dans le journal."; mv -f "$ITEM" "$SENT/" ;;
    401|403) FAILED=1; echo "  TechDesk refuse la clé : vérifiez API_KEY dans settings.txt (clé \"Scanner USB\")." ;;
    000|'') FAILED=1; echo "  Pas de connexion à TechDesk : la fiche reste sur la clé et partira au prochain envoi avec internet." ;;
    *) FAILED=1; echo "  TechDesk a répondu une erreur ($STATUS) pour $(basename "$ITEM")." ;;
  esac
done
rm -f "$REPLY_FILE"
exit $FAILED
