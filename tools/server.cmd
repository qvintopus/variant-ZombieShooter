@echo off
rem The dedicated server launcher lives in the LAN Party addon; this keeps the old path working.
call "%~dp0..\addons\lan_party\tools\server.cmd" %*
