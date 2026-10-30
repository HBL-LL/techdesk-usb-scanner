#!/bin/bash
# Lit ce Mac, l'ajoute au stock TechDesk et enregistre sa fiche technique complète.
# 1 seul clic : stock TechDesk + fiche technique complète (dalle/OLED, couleur, batterie) + journal CSV.
DIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo "============================================================"
echo "  1/2 - ENREGISTREMENT AU STOCK TECHDESK"
echo "============================================================"
/bin/bash "$DIR/scanner/scan-mac.sh"

echo
echo "============================================================"
echo "  2/2 - FICHE TECHNIQUE COMPLÈTE & JOURNAL CSV"
echo "============================================================"
/bin/bash "$DIR/fiche-technique/outils/fiche-mac.sh"

echo
echo "============================================================"
echo "  TERMINÉ !"
echo "============================================================"
echo
read -n 1 -s -r -p "Appuyez sur une touche pour fermer..."
echo
