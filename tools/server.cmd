@echo off
rem Dedicated co-op server for Windows: double-click, or "server.cmd [--vlan] [options]". See tools\vlan\README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" %*
if not errorlevel 10 pause
