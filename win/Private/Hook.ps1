# The lines in the PowerShell profile that load Lotus (the same marks as in ~/.zshrc and ~/.bashrc).

$script:HookStart = '# >>> lotus >>>'
$script:HookEnd = '# <<< lotus <<<'

function Get-LotusHookBlock {
    $module = Join-Path $script:LotusModuleRoot 'Lotus.psd1'
    @(
        $script:HookStart
        "Import-Module '$($module.Replace("'", "''"))'"
        'lotus shell-init'
        $script:HookEnd
    ) -join "`n"
}

function Get-LotusProfilePath {
    if ($env:LOTUS_PROFILE) { $env:LOTUS_PROFILE } else { $PROFILE.CurrentUserAllHosts }
}

# The profile files that load Lotus: this PowerShell's and, when it is installed, the other one's – Windows PowerShell 5.1
# (the one every Windows 11 has) and PowerShell 7 each read a profile of their own, in Documents\WindowsPowerShell and
# Documents\PowerShell. LOTUS_PROFILE (the tests) names the one file there is.
function Get-LotusProfilePaths {
    $paths = @(Get-LotusProfilePath)
    if ($env:LOTUS_PROFILE -or -not $IsWindows) { return $paths }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $other = Join-Path $docs 'WindowsPowerShell\profile.ps1'
        $there = Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    } else {
        $other = Join-Path $docs 'PowerShell\profile.ps1'
        $there = [bool](Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)
    }
    if ($there -and $other -ne $paths[0]) { $paths += $other }
    $paths
}

function Add-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusFile $ProfilePath
    if ($null -eq $text) { $text = '' }
    $block = Get-LotusHookBlock
    $pattern = '(?s)' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd)
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, { param($m) $block })
    } else {
        $text = $text.TrimEnd() + $(if ($text.Trim()) { "`n`n" } else { '' }) + $block + "`n"
    }
    Write-LotusFile $ProfilePath $text
    $ProfilePath
}

function Remove-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusFile $ProfilePath
    if ($null -eq $text) { return $false }
    $pattern = '(?s)\n*' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd) + '\n?'
    if ($text -notmatch $pattern) { return $false }
    $text = [regex]::Replace($text, $pattern, "`n")
    Write-LotusFile $ProfilePath $text.TrimStart()
    $true
}

function Test-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusFile $ProfilePath
    $null -ne $text -and $text.Contains($script:HookStart)
}
