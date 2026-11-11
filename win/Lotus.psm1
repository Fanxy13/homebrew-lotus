# Lotus for Windows. The module loads its private helpers and the lotus command; the other commands (Public/*.ps1)
# are loaded the first time they are used, so a new PowerShell window does not wait for all of them.
# The data (themes, commands, logos, texts, the version) is the same files the zsh engine reads: data/, logos/, lib/.
$script:LotusModuleRoot = $PSScriptRoot
# Windows PowerShell 5.1 – the PowerShell every Windows 11 has – is Windows only and has none of PowerShell 7's $IsWindows and
# its kin; TLS 1.2 is added for it (older systems offer only the old ones to .NET Framework programs)
if ($PSVersionTable.PSEdition -ne 'Core') {
    $script:IsWindows = $true; $script:IsLinux = $false; $script:IsMacOS = $false; $script:IsCoreCLR = $false
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
}
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1') { . $file.FullName }
. (Join-Path $PSScriptRoot 'Public/lotus.ps1')
Export-ModuleMember -Function 'lotus'
