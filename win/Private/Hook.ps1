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

# A profile is read by PowerShell itself, and the two read it differently: Windows PowerShell 5.1 takes a file without a byte
# order mark for ANSI (the code page of the system), PowerShell 7 for UTF-8. So Lotus reads a profile the way it is written (a
# byte order mark; else UTF-8 when the bytes are valid UTF-8; else ANSI) and writes it so that both read it right: as it is
# for plain ASCII, anything else as UTF-8 with a byte order mark (a user name with an umlaut is in the path of the module).
function Read-LotusProfile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        $utf16 = if ($bytes[0] -eq 0xFF) { [System.Text.Encoding]::Unicode } else { [System.Text.Encoding]::BigEndianUnicode }
        return $utf16.GetString($bytes, 2, $bytes.Length - 2)
    }
    $skip = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    try { return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes, $skip, $bytes.Length - $skip) }
    catch {
        $page = [Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
        $ansi = try { if ($page -gt 0 -and $page -ne 65001) { [System.Text.Encoding]::GetEncoding($page) } else { $null } } catch { $null }
        if (-not $ansi) { $ansi = [System.Text.Encoding]::GetEncoding(28591) }
        return $ansi.GetString($bytes)
    }
}

function Write-LotusProfile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text, [bool]$Crlf)
    if ($Crlf) { $Text = $Text.Replace("`n", "`r`n") }
    $dir = Split-Path -Parent $Path
    if ($dir) { New-LotusDir $dir | Out-Null }
    $tmp = "$Path.$PID.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($Text -cmatch '[^\x00-\x7F]'))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Add-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusProfile $ProfilePath
    if ($null -eq $text) { $text = '' }
    $crlf = $text.Contains("`r`n")
    $text = $text.Replace("`r`n", "`n")
    $block = Get-LotusHookBlock
    $pattern = '(?s)' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd)
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, { param($m) $block })
    } else {
        $text = $text.TrimEnd() + $(if ($text.Trim()) { "`n`n" } else { '' }) + $block + "`n"
    }
    Write-LotusProfile $ProfilePath $text $crlf
    $ProfilePath
}

function Remove-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusProfile $ProfilePath
    if ($null -eq $text) { return $false }
    $crlf = $text.Contains("`r`n")
    $text = $text.Replace("`r`n", "`n")
    $pattern = '(?s)\n*' + [regex]::Escape($script:HookStart) + '.*?' + [regex]::Escape($script:HookEnd) + '\n?'
    if ($text -notmatch $pattern) { return $false }
    $text = [regex]::Replace($text, $pattern, "`n")
    Write-LotusProfile $ProfilePath $text.TrimStart() $crlf
    $true
}

function Test-LotusHook {
    param([string]$ProfilePath = (Get-LotusProfilePath))
    $text = Read-LotusProfile $ProfilePath
    $null -ne $text -and $text.Contains($script:HookStart)
}
