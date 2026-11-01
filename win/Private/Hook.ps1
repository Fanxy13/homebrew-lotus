# The lines in the PowerShell profile that load Lotus (the same marks as in ~/.zshrc and ~/.bashrc).

$script:HookStart = '# >>> lotus >>>'
$script:HookEnd = '# <<< lotus <<<'

function Get-LotusHookBlock {
    $module = Join-Path $script:LotusModuleRoot 'Lotus.psd1'
    @(
        $script:HookStart
        "Import-Module '$($module.Replace("'", "''"))'"
        "if (`$Host.Name -eq 'ConsoleHost' -and [Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) { lotus show }"
        $script:HookEnd
    ) -join "`n"
}

function Get-LotusProfilePath {
    if ($env:LOTUS_PROFILE) { $env:LOTUS_PROFILE } else { $PROFILE.CurrentUserAllHosts }
}

function Add-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = if (Test-Path -LiteralPath $ProfilePath) { Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 } else { '' }
    if ($null -eq $text) { $text = '' }
    $block = Get-LotusHookBlock
    $pattern = '(?s)' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd)
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, { param($m) $block })
    } else {
        $text = $text.TrimEnd() + $(if ($text.Trim()) { "`n`n" } else { '' }) + $block + "`n"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProfilePath) | Out-Null
    [System.IO.File]::WriteAllText($ProfilePath, $text, [System.Text.UTF8Encoding]::new($false))
    $ProfilePath
}

function Remove-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return $false }
    $text = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8
    if ($null -eq $text) { return $false }
    $pattern = '(?s)\r?\n*' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd) + '\r?\n?'
    if ($text -notmatch $pattern) { return $false }
    $text = [regex]::Replace($text, $pattern, "`n")
    [System.IO.File]::WriteAllText($ProfilePath, $text.TrimStart(), [System.Text.UTF8Encoding]::new($false))
    $true
}

function Test-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    (Test-Path -LiteralPath $ProfilePath) -and ((Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8) -like "*$($script:HookStart)*")
}
