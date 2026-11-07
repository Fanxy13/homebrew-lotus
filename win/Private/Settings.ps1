# settings.zsh: one line KEY='value' for every setting and the shortcuts as a zsh array – the file zsh sources. The same
# file on every system, so it can move between them. The keys, their order and their defaults are read from
# lib/core.zsh itself (LOTUS_KEYS, lotus_defaults), so the two engines never disagree about them.

$script:S = [ordered]@{}
$script:Shortcuts = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
$script:SExtra = [ordered]@{}           # LOTUS_* keys of newer versions: kept and written back
$script:SSaved = @{}

# LOTUS_KEYS and the defaults from lib/core.zsh (read once)
function Get-LotusSchema {
    if ($script:Schema) { return $script:Schema }
    $core = Read-LotusFile (Join-Path (Get-LotusRoot) 'lib/core.zsh')
    $keys = Get-LotusZshArray -Text $core -Name 'LOTUS_KEYS'
    if (-not $keys) { throw 'lib/core.zsh has no LOTUS_KEYS.' }
    $m = [regex]::Match($core, '(?ms)^lotus_defaults\(\)\s*\{[^\n]*\n(.*?)^\}')
    $defaults = @{}
    foreach ($cmd in Get-LotusZshCommands $m.Groups[1].Value) {
        if ($cmd.Count -lt 2 -or $cmd[0] -cne 'typeset' -or $cmd[1] -cne '-g') { continue }
        foreach ($w in $cmd[2..($cmd.Count - 1)]) {
            if ($w -cmatch '^(LOTUS_[A-Z0-9_]+)=(.*)$') { $defaults[$Matches[1]] = $Matches[2] }
        }
    }
    $script:Schema = [pscustomobject]@{ Keys = $keys; Defaults = $defaults }
    $script:Schema
}

function Reset-LotusSettings {
    # lotus_defaults
    $schema = Get-LotusSchema
    $script:S = [ordered]@{}
    foreach ($k in $schema.Keys) { $script:S[$k] = if ($schema.Defaults.ContainsKey($k)) { $schema.Defaults[$k] } else { '' } }
    if ($IsMacOS) { $script:S['LOTUS_PET_BRAIN'] = 'apple' }
    $script:Shortcuts = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $script:SExtra = [ordered]@{}
}

# What a settings file says (as zsh would read it) → @{ Values = ordered; Shortcuts = dictionary }
function Read-LotusSettings {
    param([Parameter(Mandatory)][string]$Path)
    $values = [ordered]@{}
    $shortcuts = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $text = Read-LotusFile $Path
    if ($null -eq $text) { return [pscustomobject]@{ Values = $values; Shortcuts = $shortcuts } }
    try { $tokens = Split-LotusZsh $text } catch { Write-LotusLog WARN settings "settings.zsh could not be read: $_"; return [pscustomobject]@{ Values = $values; Shortcuts = $shortcuts } }
    foreach ($cmd in Get-LotusZshCommands -Tokens $tokens) {
        $words = @($cmd)
        if ($words.Count -and $words[0] -cin 'typeset', 'export', 'local', 'declare') { $words = @($words | Select-Object -Skip 1 | Where-Object { $_ -notlike '-*' }) }
        foreach ($w in $words) {
            if ($w -cmatch '^(LOTUS_[A-Z0-9_]+)=([\s\S]*)$' -and $Matches[1] -cne 'LOTUS_SHORTCUTS') { $values[$Matches[1]] = $Matches[2] }
        }
    }
    $sc = Get-LotusZshArray -Text $text -Name 'LOTUS_SHORTCUTS' -All -Tokens $tokens
    if ($sc) { for ($i = 0; $i + 1 -lt $sc.Count; $i += 2) { $shortcuts[$sc[$i]] = $sc[$i + 1] } }
    [pscustomobject]@{ Values = $values; Shortcuts = $shortcuts }
}

# Is a setting on? zsh's (( LOTUS_X )): a number other than 0
function Test-LotusOn {
    param([AllowEmptyString()][AllowNull()]$Value)
    $n = 0L
    [long]::TryParse([string]$Value, [ref]$n) -and $n -ne 0
}
function Get-LotusInt {
    param([AllowEmptyString()][AllowNull()]$Value, [long]$Default = 0)
    $n = 0L
    if ([long]::TryParse([string]$Value, [ref]$n)) { $n } else { $Default }
}

# lotus_load: defaults, the file, migrations, then what the engine corrects in memory
function Import-LotusSettings {
    Reset-LotusSettings
    $schema = Get-LotusSchema
    $file = $script:Paths.Settings
    $hasFile = Test-Path -LiteralPath $file -PathType Leaf
    if ($hasFile) {
        $read = Read-LotusSettings $file
        foreach ($k in $read.Values.Keys) {
            if ($script:S.Contains($k)) { $script:S[$k] = $read.Values[$k] } else { $script:SExtra[$k] = $read.Values[$k] }
        }
        $script:Shortcuts = $read.Shortcuts
        Update-LotusSettingsVersion
    }
    $s = $script:S
    if (-not $s['LOTUS_NAME']) {
        $full = @((Get-LotusFullName) -split '\s+' | Where-Object { $_ })
        $s['LOTUS_NAME'] = if ($full.Count -and $full[0].Length -gt 1) { $full[0] } else {
            $u = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { [Environment]::UserName }
            if ($u) { $u.Substring(0, 1).ToUpperInvariant() + $u.Substring(1).ToLowerInvariant() } else { '' }
        }
    }
    $iv = Get-LotusInt $s['LOTUS_INTERVAL'] -1
    if ($iv -lt 1 -or $iv -gt 60 -or $s['LOTUS_INTERVAL'] -notmatch '^\d+$') { $s['LOTUS_INTERVAL'] = '2' }
    $known = @('zsh', 'bash')
    $shells = [System.Collections.Generic.List[string]]::new()
    foreach ($x in ([string]$s['LOTUS_SHELLS'] -split '\s+')) { if ($x -cin $known -and -not $shells.Contains($x)) { $shells.Add($x) } }
    $s['LOTUS_SHELLS'] = $shells -join ' '
    foreach ($k in 'LOTUS_LOGO_THEME', 'LOTUS_LOGO_FADE', 'LOTUS_COVER') { if ($s[$k] -cne '0') { $s[$k] = '1' } }
    $port = Get-LotusInt $s['LOTUS_AI_SERVER_PORT'] -1
    if ($s['LOTUS_AI_SERVER_PORT'] -notmatch '^\d+$' -or $port -lt 1024 -or $port -gt 65535) { $s['LOTUS_AI_SERVER_PORT'] = '3000' }
    if ($s['LOTUS_AI_ENHANCE'] -cnotin 'off', 'on', 'ask') { $s['LOTUS_AI_ENHANCE'] = 'off' }
    foreach ($k in 'LOTUS_AI_SERVER_BOOT', 'LOTUS_AI_SERVER_LAN') { if ($s[$k] -cne '1') { $s[$k] = '0' } }
    if (-not $script:LogRank.ContainsKey([string]$s['LOTUS_LOG_LEVEL']) -or $s['LOTUS_LOG_LEVEL'] -cne ([string]$s['LOTUS_LOG_LEVEL']).ToLowerInvariant()) { $s['LOTUS_LOG_LEVEL'] = 'info' }
    $script:LogMax = -1
    Save-LotusSnapshot
}

# Settings written by older versions keep working: every key that is missing gets its default, nothing the user chose
# is changed (lotus_migrate):  1.x → 2.0 the bottom greeting is off, the wizard is not shown again
function Update-LotusSettingsVersion {
    $s = $script:S
    if ($s['LOTUS_LOGO'] -ceq 'heart') { $s['LOTUS_LOGO'] = 'lotus' }
    $v = Get-LotusInt $s['LOTUS_CONFIG_VERSION']
    if ($v -ge 3) { return }
    if ($v -lt 2) { $s['LOTUS_SALUTE'] = 'off'; $s['LOTUS_CONFIGURED'] = '1' }
    $s['LOTUS_CONFIG_VERSION'] = '3'
    try {
        Save-LotusSettings -Quiet
        Write-LotusLog INFO settings "Settings migrated from version $v to 3 (Lotus $(Get-LotusVersion))"
    } catch { }
}

# The text of settings.zsh, as lotus_save writes it (shortcuts by name; zsh writes them in its own hash order)
function Get-LotusSettingsText {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("# lotus – settings (easier: lotus settings)`n")
    foreach ($k in (Get-LotusSchema).Keys) { [void]$sb.Append("$k=$(ConvertTo-LotusQuoted $script:S[$k])`n") }
    foreach ($k in $script:SExtra.Keys) { [void]$sb.Append("$k=$(ConvertTo-LotusQuoted $script:SExtra[$k])`n") }
    if ($script:Shortcuts.Count) {
        $parts = foreach ($kv in $script:Shortcuts.GetEnumerator()) { (ConvertTo-LotusQuoted $kv.Key) + ' ' + (ConvertTo-LotusQuoted $kv.Value) }
        [void]$sb.Append("typeset -gA LOTUS_SHORTCUTS=($($parts -join ' '))`n")
    } else {
        [void]$sb.Append("typeset -gA LOTUS_SHORTCUTS=()`n")
    }
    $sb.ToString()
}

# lotus_save: writes the file; changed keys are logged (personal values only as "changed")
function Save-LotusSettings {
    param([switch]$Quiet)
    foreach ($k in $script:S.Keys) {
        if ([string]$script:S[$k] -match "[`r`n]") { throw "$k is one line." }
    }
    Write-LotusFile $script:Paths.Settings (Get-LotusSettingsText)
    if (-not $Quiet) {
        $changed = @(foreach ($k in (Get-LotusSchema).Keys) { if ($script:SSaved.ContainsKey($k) -and [string]$script:SSaved[$k] -cne [string]$script:S[$k]) { $k } })
        if ($changed.Count) {
            Write-LotusLog INFO settings ('Changed: ' + (($changed | ForEach-Object { $_ -replace '^LOTUS_', '' }) -join ' '))
            foreach ($k in $changed) {
                if ($k -cin 'LOTUS_NAME', 'LOTUS_WEATHER_LOCATION', 'LOTUS_BG_OUTPUT', 'LOTUS_AI_URL') { continue }
                Write-LotusLog DEBUG settings "$($k -replace '^LOTUS_', '') = $($script:S[$k])"
            }
        }
    }
    Save-LotusSnapshot
}

function Save-LotusSnapshot {
    $script:SSaved = @{}
    foreach ($k in $script:S.Keys) { $script:SSaved[$k] = $script:S[$k] }
}

# One setting changed and saved (lotus settings set NAME VALUE; for scripts)
function Set-LotusSetting {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Name -cnotmatch '^LOTUS_[A-Z0-9_]+$') { throw "Not a Lotus setting name: $Name" }
    if ($Value -match "[`r`n]") { throw 'A setting is one line.' }
    if ($Name -ceq 'LOTUS_SHORTCUTS') { throw 'Shortcuts are changed with: lotus shortcut add' }
    if ($script:S.Contains($Name)) { $script:S[$Name] = $Value } else { $script:SExtra[$Name] = $Value }
    Save-LotusSettings
}
