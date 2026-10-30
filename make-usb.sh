#!/bin/bash
# Génère 2 fichiers autonomes (scripts + réglages embarqués) : SCAN-WINDOWS.vbs et SCAN-MAC.app.
# Copiez seulement celui (ou ceux) dont vous avez besoin sur une clé exFAT : rien d'autre à copier.
# Au double-clic, le fichier dépose ses scripts (cachés) à côté de lui sur la clé, puis lance le scan.
# Usage : ./make-usb.sh https://techdesk.exemple.com smk_xxxxxxxx [dossier de sortie, par défaut dist/]
set -euo pipefail

URL="${1:-}"; KEY="${2:-}"
URL="${URL%/}"
[[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || { echo "URL invalide : '$URL'"; exit 1; }
[[ "$KEY" =~ ^smk_[A-Za-z0-9]+$ ]] || { echo "Clé invalide : elle doit commencer par smk_"; exit 1; }

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${3:-$SRC/dist}"
mkdir -p "$OUT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

printf '# Réglages du scanner USB TechDesk (générés par make-usb.sh)\nTECHDESK_URL=%s\nAPI_KEY=%s\n' "$URL" "$KEY" > "$TMP/settings.txt"

# ---------------- Windows : un seul .vbs ----------------
vbs_file() { # $1 = chemin sur la clé, $2 = fichier embarqué
  echo '    b = ""'
  { base64 -i "$2" | tr -d '\n'; echo; } | fold -w 200 | sed 's/.*/    b = b \& "&"/'
  echo "    WriteB64 strDir & \"\\$1\", b"
}
{
  awk '{print} /^strDir = /{print "Unpack"}' "$SRC/SCAN-WINDOWS.vbs"
  cat <<'EOF'

' ---- Scripts et reglages embarques (generes par make-usb.sh) ----
Sub Unpack()
    Dim b, f
    For Each f In Array("\scanner", "\fiche-technique", "\fiche-technique\outils", "\scans")
        If Not fso.FolderExists(strDir & f) Then fso.CreateFolder strDir & f
    Next
EOF
  vbs_file 'settings.txt' "$TMP/settings.txt"
  vbs_file 'scanner\scan-windows.ps1' "$SRC/scanner/scan-windows.ps1"
  vbs_file 'fiche-technique\outils\fiche-windows.ps1' "$SRC/fiche-technique/outils/fiche-windows.ps1"
  cat <<'EOF'
    For Each f In Array("\scanner", "\fiche-technique", "\scans")
        fso.GetFolder(strDir & f).Attributes = 2
    Next
    fso.GetFile(strDir & "\settings.txt").Attributes = 2
End Sub

Sub WriteB64(path, data)
    Dim node, stm
    ' Un fichier cache ne peut pas etre ecrase : on retire l'attribut d'abord
    If fso.FileExists(path) Then fso.GetFile(path).Attributes = 0
    Set node = CreateObject("MSXML2.DOMDocument").createElement("b")
    node.dataType = "bin.base64"
    node.text = data
    Set stm = CreateObject("ADODB.Stream")
    stm.Type = 1
    stm.Open
    stm.Write node.nodeTypedValue
    stm.SaveToFile path, 2
    stm.Close
End Sub
EOF
} | perl -pe 's/\r?\n/\r\n/' > "$OUT/SCAN-WINDOWS.vbs"

# ---------------- Mac : une seule app ----------------
cat > "$TMP/scan-mac.applescript" <<'EOF'
set appDir to do shell script "p=" & quoted form of (POSIX path of (path to me)) & "; echo \"${p%/}\""
set usbDir to do shell script "dirname " & quoted form of appDir

try
	do shell script "cd " & quoted form of usbDir & " && ditto --norsrc --noextattr " & quoted form of (appDir & "/Contents/Resources/kit") & " . && mkdir -p scans && chflags hidden settings.txt scanner fiche-technique scans"
on error errMsg
	display dialog "Impossible d'écrire sur la clé USB (pleine ou protégée ?)" & return & return & errMsg with title "TechDesk USB Scanner" buttons {"Fermer"} default button "Fermer" with icon stop
	return
end try

display notification "Scan en cours, veuillez patienter..." with title "TechDesk Scanner" subtitle "Lecture des composants & fiche technique"

set scanOut to ""
try
	set scanOut to do shell script "/bin/bash " & quoted form of (usbDir & "/scanner/scan-mac.sh")
on error errMsg
	set scanOut to errMsg
end try

set ficheOut to ""
try
	set ficheOut to do shell script "/bin/bash " & quoted form of (usbDir & "/fiche-technique/outils/fiche-mac.sh")
on error errMsg
	set ficheOut to errMsg
end try

set summaryText to "✅ Scan terminé !" & return & return
if scanOut contains "AJOUTÉ AU STOCK" then
	set summaryText to summaryText & "• Nouveau Mac AJOUTÉ au stock TechDesk" & return
else if scanOut contains "DÉJÀ EN STOCK" then
	set summaryText to summaryText & "• Ce Mac était DÉJÀ en stock TechDesk" & return
else
	set summaryText to summaryText & "• Enregistré sur la clé USB" & return
end if

if ficheOut contains "ENREGISTRÉ dans" then
	set summaryText to summaryText & "• Fiche technique enregistrée dans le journal CSV" & return
end if
if ficheOut contains "FICHE AJOUTÉE" or ficheOut contains "FICHE ENREGISTRÉE" then
	set summaryText to summaryText & "• Fiche synchronisée avec TechDesk" & return
else
	set summaryText to summaryText & "• En attente de connexion internet pour l'envoi TechDesk" & return
end if

set fullMsg to summaryText & return & "----------------------------------------" & return & ficheOut

display dialog fullMsg with title "TechDesk USB Scanner" buttons {"Fermer"} default button "Fermer" with icon note giving up after 30
EOF
APP="$OUT/SCAN-MAC.app"
rm -rf "$APP"
osacompile -o "$APP" "$TMP/scan-mac.applescript"
KIT="$APP/Contents/Resources/kit"
mkdir -p "$KIT/scanner" "$KIT/fiche-technique/outils"
cp "$TMP/settings.txt" "$KIT/"
cp "$SRC/scanner/scan-mac.sh" "$KIT/scanner/"
cp "$SRC/fiche-technique/outils/fiche-mac.sh" "$KIT/fiche-technique/outils/"
codesign --force --deep --sign - "$APP"

echo "Prêt dans $OUT :"
echo "  SCAN-WINDOWS.vbs → à copier sur la clé pour les laptops Windows"
echo "  SCAN-MAC.app     → à copier sur la clé pour les Mac"
echo "Gardez ces fichiers privés : ils contiennent la clé API."
