# Lotus for Windows. The module loads its private helpers, then the public command.
# The data (themes, commands, logos, the version) is the same files the zsh engine reads: data/, logos/, lib/core.zsh.
$script:LotusModuleRoot = $PSScriptRoot
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1') { . $file.FullName }
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1') { . $file.FullName }
Export-ModuleMember -Function 'lotus'
