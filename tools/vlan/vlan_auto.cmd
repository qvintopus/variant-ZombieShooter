@echo off
rem The virtual LAN script lives in the LAN Party addon; this keeps the old path working.
call "%~dp0..\..\addons\lan_party\tools\vlan\vlan_auto.cmd" %*
