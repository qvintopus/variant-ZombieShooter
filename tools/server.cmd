@echo off
rem Dedicated co-op server for Windows: double-click for the menu (start/stop, status, players, log, console),
rem or "server.cmd start|stop|status|..." ("server.cmd help"). See tools\vlan\README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" %*
if not errorlevel 10 pause
