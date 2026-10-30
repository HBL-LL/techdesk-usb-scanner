@echo off
rem Lit ce laptop, l'ajoute au stock TechDesk et enregistre sa fiche technique complete.
rem 1 seul clic : stock TechDesk + fiche technique complete (dalle/OLED, couleur, batterie) + journal CSV.
rem Marche aussi pendant l'installation de Windows (Maj+F10).

echo.
echo ============================================================
echo   1/2 - ENREGISTREMENT AU STOCK TECHDESK
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scanner\scan-windows.ps1"

echo.
echo ============================================================
echo   2/2 - FICHE TECHNIQUE COMPLETE ^& JOURNAL CSV
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fiche-technique\outils\fiche-windows.ps1"

echo.
echo ============================================================
echo   TERMINE !
echo ============================================================
echo.
pause
