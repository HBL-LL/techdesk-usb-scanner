#!/bin/bash
# Lit ce MacBook et l'ajoute au stock TechDesk. Double-cliquez ce fichier sur la clé USB.
/bin/bash "$(dirname "$0")/scanner/scan-mac.sh"
echo
read -n 1 -s -r -p "Appuyez sur une touche pour fermer..."
echo
