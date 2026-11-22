@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Luftwaechter.ps1" -Uninstall
echo Luftwaechter wurde beendet und der Autostart entfernt. / Luftwaechter was stopped and autostart removed.
pause
