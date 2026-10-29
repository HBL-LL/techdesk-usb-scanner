#!/bin/bash
# Relève la fiche technique complète de ce Mac, la note dans le journal de la clé et l'envoie à TechDesk. Double-cliquez ce fichier.
/bin/bash "$(dirname "$0")/outils/fiche-mac.sh"
echo
read -n 1 -s -r -p "Appuyez sur une touche pour fermer..."
echo
