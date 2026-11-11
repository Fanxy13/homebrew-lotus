@echo off
rem lotus in cmd.exe and the Run dialog: PowerShell runs lotus.ps1 next to this file, with the arguments as they are -
rem PowerShell 7 when it is there, else the Windows PowerShell 5.1 every Windows 11 has (no script policy in the way)
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 goto seven
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0lotus.ps1" %*
exit /b %ERRORLEVEL%
:seven
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0lotus.ps1" %*
exit /b %ERRORLEVEL%
