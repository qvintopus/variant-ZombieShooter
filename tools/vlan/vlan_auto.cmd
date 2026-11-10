@echo off
rem zs-vlan for Windows: double-click, or "vlan_auto.cmd <command>". See README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0vlan_auto.ps1" %*
rem double-clicked: keep the window open (exit 10 = it reopened itself as admin in its own window)
if "%~1"=="" if not errorlevel 10 pause
