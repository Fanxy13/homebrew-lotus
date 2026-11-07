@echo off
rem lotus in cmd.exe and the Run dialog: PowerShell 7 runs lotus.ps1 next to this file, with the arguments as they are
where pwsh >nul 2>nul || (echo Lotus needs PowerShell 7: winget install --id Microsoft.PowerShell -e& exit /b 1)
pwsh -NoLogo -NoProfile -File "%~dp0lotus.ps1" %*
exit /b %ERRORLEVEL%
