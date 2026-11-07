# Lotus for Windows. The module loads its private helpers and the lotus command; the other commands (Public/*.ps1)
# are loaded the first time they are used, so a new PowerShell window does not wait for all of them.
# The data (themes, commands, logos, texts, the version) is the same files the zsh engine reads: data/, logos/, lib/.
$script:LotusModuleRoot = $PSScriptRoot
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1') { . $file.FullName }
. (Join-Path $PSScriptRoot 'Public/lotus.ps1')
Export-ModuleMember -Function 'lotus'
