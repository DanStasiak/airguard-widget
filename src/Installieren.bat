@echo off
echo Luftwaechter wird installiert / Installing Luftwaechter ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Luftwaechter.ps1" -Install
echo.
echo Fertig / Done. Das Fenster erscheint in wenigen Sekunden oben rechts. The window appears at the top right in a few seconds.
echo Es startet ab jetzt automatisch mit Windows. It now starts automatically with Windows.
echo Beim ersten Mal: Rechtsklick auf das Fenster - Konfiguration oeffnen / Open configuration.
pause
