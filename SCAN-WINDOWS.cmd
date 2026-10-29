@echo off
rem Lit ce laptop et l'ajoute au stock TechDesk. Marche aussi pendant l'installation de Windows (Maj+F10).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scanner\scan-windows.ps1"
echo.
pause
