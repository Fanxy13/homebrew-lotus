# lotus outside the PowerShell windows that load Lotus: cmd.exe, the Run dialog, a shortcut, a script - bin\lotus.cmd
# runs this with PowerShell 7 or Windows PowerShell 5.1. It loads the module next to it and runs the command; in a
# PowerShell window with Lotus in its profile, the module's own lotus function answers instead. (Windows PowerShell 5.1
# must be able to read this.)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host 'Lotus needs Windows PowerShell 5.1 (every Windows 11 has it) or PowerShell 7.'
    exit 1
}
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'win/Lotus.psd1')
lotus @args
exit $LASTEXITCODE
