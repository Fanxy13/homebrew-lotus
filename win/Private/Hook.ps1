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
