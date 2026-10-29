@echo off
rem Releve la fiche technique complete de ce laptop, la note dans le journal de la cle et l'envoie a TechDesk. Marche aussi pendant l'installation de Windows (Maj+F10).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0outils\fiche-windows.ps1"
echo.
pause
